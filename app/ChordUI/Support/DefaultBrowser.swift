import AppKit
import UniformTypeIdentifiers

/// Chord as the Mac's default web browser. Chord.app declares http, https and HTML files
/// (Chromium's Info.plist); macOS asks the user to confirm the change.
enum DefaultBrowser {
    private static let probe = URL(string: "https://example.com")!

    /// The app that opens web links now.
    static var current: URL? { NSWorkspace.shared.urlForApplication(toOpen: probe) }

    /// Launch Services keeps the handler by bundle identifier: any copy of Chord counts.
    static var isChord: Bool {
        guard let current, let id = Bundle(url: current)?.bundleIdentifier else { return false }
        return id == Bundle.main.bundleIdentifier
    }

    /// "Safari", "Arc"…
    static var currentName: String? {
        guard let current else { return nil }
        let name = FileManager.default.displayName(atPath: current.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Asks macOS to make Chord the default browser; `completion` gets the result once
    /// the user has answered the system's dialog. Follows Chromium's SetAsDefaultBrowser.
    static func makeChord(completion: @escaping (Bool) -> Void) {
        let workspace = NSWorkspace.shared
        let app = Bundle.main.bundleURL
        workspace.setDefaultApplication(at: app, toOpenURLsWithScheme: "http") { error in
            // Asking for https after a "Keep Safari" would show the dialog a second time.
            guard error == nil else {
                DispatchQueue.main.async { completion(isChord) }
                return
            }
            workspace.setDefaultApplication(at: app, toOpenURLsWithScheme: "https") { _ in
                DispatchQueue.main.async { completion(isChord) }
            }
        }
        // From macOS 26.4, HTML files bring a second confirmation, from the Finder.
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if (version.majorVersion, version.minorVersion) < (26, 4) {
            workspace.setDefaultApplication(at: app, toOpen: .html) { _ in }
        }
        // The confirmation sometimes opens behind Chord's windows, unseen: bring it forward.
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.coreservices.uiagent" }?
            .activate(options: .activateAllWindows)
    }
}
