#!/usr/bin/env swift
// Walks the accessibility tree of a running Chord, as VoiceOver reads it, and lists what
// VoiceOver would read badly: controls with no name, images that say nothing, single
// characters read on their own (a site's initial). Pages are skipped: they are
// Chromium's, with its own accessibility.
//
//   swift app/scripts/ax-audit.swift            # the running Chord
//   swift app/scripts/ax-audit.swift <pid>      # another instance (a test copy)
//   swift app/scripts/ax-audit.swift <pid> --tree
//
// The shell needs the Accessibility permission (System Settings › Privacy & Security).
// Open what you want audited first (the command bar, a panel, a Peek): only what is on
// screen is in the tree. See docs/ACCESSIBILITY.md.
import AppKit
import ApplicationServices

let arguments = CommandLine.arguments.dropFirst()
let printsTree = arguments.contains("--tree")
let pid: pid_t = arguments.first { Int32($0) != nil }.flatMap { Int32($0) }
    ?? NSRunningApplication.runningApplications(withBundleIdentifier: "app.chord.Chord").first?.processIdentifier
    ?? { print("No Chord running"); exit(1) }()

guard AXIsProcessTrusted() else {
    print("Give this terminal the Accessibility permission (System Settings › Privacy & Security › Accessibility).")
    exit(1)
}

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func string(_ element: AXUIElement, _ name: String) -> String {
    (attribute(element, name) as? String) ?? ""
}

/// What VoiceOver says for the element: its description, title, or value for text.
func name(_ element: AXUIElement) -> String {
    for key in [kAXDescriptionAttribute, kAXTitleAttribute] {
        let text = string(element, key)
        if !text.isEmpty { return text }
    }
    if let label = attribute(element, kAXTitleUIElementAttribute) {
        return string(label as! AXUIElement, kAXValueAttribute)
    }
    return ""
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

/// Some text inside, which VoiceOver reads for a control without a name of its own.
func innerText(_ element: AXUIElement, depth: Int = 0) -> String {
    guard depth < 4 else { return "" }
    for child in children(element) {
        let role = string(child, kAXRoleAttribute)
        if role == kAXStaticTextRole, !string(child, kAXValueAttribute).isEmpty { return string(child, kAXValueAttribute) }
        let text = innerText(child, depth: depth + 1)
        if !text.isEmpty { return text }
    }
    return ""
}

/// The window's own buttons, which macOS names itself.
let windowButtons: Set<String> = [kAXCloseButtonSubrole, kAXMinimizeButtonSubrole, kAXZoomButtonSubrole, kAXFullScreenButtonSubrole]

let controls: Set<String> = [kAXButtonRole, kAXMenuButtonRole, kAXCheckBoxRole, kAXRadioButtonRole,
                             kAXPopUpButtonRole, kAXTextFieldRole, kAXSliderRole, kAXCellRole]
var problems: [String] = []
var path: [String] = []

func walk(_ element: AXUIElement, depth: Int, insideNamedControl: Bool) {
    let role = string(element, kAXRoleAttribute)
    guard role != "AXWebArea" else { return }
    let label = name(element)
    let value = string(element, kAXValueAttribute)
    if printsTree {
        print(String(repeating: "  ", count: depth) + role + (label.isEmpty ? "" : " “\(label)”") + (value.isEmpty ? "" : " = \(value.prefix(50))"))
    }
    let here = (path + [role + (label.isEmpty ? "" : " “\(label)”")]).suffix(3).joined(separator: " › ")
    if controls.contains(role), label.isEmpty, innerText(element).isEmpty, string(element, kAXPlaceholderValueAttribute).isEmpty,
       !windowButtons.contains(string(element, kAXSubroleAttribute)) {
        problems.append("unnamed \(role): \(here)")
    }
    if role == kAXImageRole, label.isEmpty, !insideNamedControl {
        problems.append("image without a description: \(here)")
    }
    if role == kAXStaticTextRole, value.count == 1, !insideNamedControl, Int(value) == nil {
        problems.append("single character read alone (“\(value)”): \(here)")
    }
    path.append(role + (label.isEmpty ? "" : " “\(label)”"))
    let named = insideNamedControl || (controls.contains(role) && !label.isEmpty)
    for child in children(element) { walk(child, depth: depth + 1, insideNamedControl: named) }
    path.removeLast()
}

let app = AXUIElementCreateApplication(pid)
for window in (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
    walk(window, depth: 0, insideNamedControl: false)
}
if problems.isEmpty {
    print("Nothing for VoiceOver to stumble on in what is on screen.")
} else {
    print("\(problems.count) to look at:")
    problems.forEach { print("- " + $0) }
    exit(1)
}
