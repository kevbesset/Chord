import AppKit

/// The menu bar. Every shortcut lives here, so it is discoverable from the menus.
/// Items have no target: they travel the responder chain to the window controller.
///
/// Shortcuts are Arc's wherever Arc has one. Each can be remapped in the settings; an
/// item's identifier (its action, plus its tag for numbered items) keys the remapping.
public enum MainMenu {
    /// The shortcuts as built, by item identifier, so that a remapping can be undone.
    private static var defaults: [String: Shortcut] = [:]

    public static func build(appName: String) -> NSMenu {
        let main = NSMenu()
        typealias C = BrowserWindowController

        main.addItem(submenu(appName, [
            item("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            // Handled by ChordUIHost's updater (Sparkle).
            item("Check for Updates…", Selector(("checkForUpdates:"))),
            .separator(),
            item("Settings…", #selector(C.showSettings(_:)), ","),
            .separator(),
            item("Hide \(appName)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        main.addItem(submenu("File", [
            item("New Tab", #selector(C.newTab(_:)), "t"),
            // Handled by ChordUIHost's app actions, so that they work with no window open.
            item("New Window", Selector(("newWindow:")), "n"),
            item("New Private Window", Selector(("newPrivateWindow:")), "n", [.command, .shift]),
            item("New Little Window", #selector(C.newLittleWindow(_:)), "n", [.command, .option]),
            item("Open Location", #selector(C.openLocation(_:)), "l"),
            .separator(),
            item("Close Tab", #selector(C.closeTab(_:)), "w"),
            item("Reopen Closed Tab", #selector(C.reopenClosedTab(_:)), "t", [.command, .shift]),
            item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]),
            .separator(),
            item("Import from Arc…", #selector(C.importFromArc(_:))),
            item("Import Logins from Arc…", #selector(C.importArcLogins(_:))),
        ]))

        main.addItem(submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Copy URL", #selector(C.copyURL(_:)), "c", [.command, .shift]),
        ]))

        main.addItem(submenu("View", [
            item("Hide Sidebar", #selector(C.toggleSidebarVisibility(_:)), "s"),
            hidden(item("Sidebar (second shortcut)", #selector(C.toggleSidebarVisibility(_:)), "b", tag: 2)),
            // Arc's shortcuts: ⌃⇧= for the split view, ⇧⌘D for the address bar's place.
            item("Split View", #selector(C.toggleSplitView(_:)), "=", [.control, .shift]),
            item("Address Bar on Top", #selector(C.toggleAddressBarPosition(_:)), "d", [.command, .shift]),
            item("Edgeless Mode", #selector(C.toggleEdgeless(_:))),
            .separator(),
            item("Reload Page", #selector(C.reloadPage(_:)), "r"),
            item("Reload Ignoring Cache", #selector(C.reloadPageIgnoringCache(_:)), "r", [.command, .shift]),
            item("Stop Loading", #selector(C.stopLoading(_:)), "."),
            .separator(),
            item("Developer Tools", #selector(C.toggleDevTools(_:)), "i", [.command, .option]),
            item("Picture in Picture", #selector(C.togglePictureInPicture(_:)), "p", [.command, .control]),
            .separator(),
            item("Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))

        main.addItem(submenu("History", [
            item("Back", #selector(C.goBack(_:)), "["),
            item("Forward", #selector(C.goForward(_:)), "]"),
            // ⌘← and ⌘→ too, like Arc and Chrome; off while typing, where they move the caret.
            hidden(item("Back (arrow)", #selector(C.goBack(_:)), arrow(NSLeftArrowFunctionKey), tag: 2)),
            hidden(item("Forward (arrow)", #selector(C.goForward(_:)), arrow(NSRightArrowFunctionKey), tag: 2)),
        ]))

        var tabItems: [NSMenuItem] = [
            item("Next Tab", #selector(C.nextTab(_:)), "\t", [.control]),
            item("Previous Tab", #selector(C.previousTab(_:)), "\t", [.control, .shift]),
            .separator(),
            item("Pin Tab", #selector(C.togglePinTab(_:)), "d"),
            item("Add to Favorites", #selector(C.toggleFavoriteTab(_:))),
            item("New Folder", #selector(C.newFolder(_:))),
            .separator(),
        ]
        for number in 1...9 {
            let title = number == 9 ? "Last Tab" : "Tab \(number)"
            tabItems.append(item(title, #selector(C.selectTabByNumber(_:)), "\(number)", tag: number))
        }
        main.addItem(submenu("Tabs", tabItems))

        var spaceItems: [NSMenuItem] = [
            item("Next Space", #selector(C.nextSpace(_:)), arrow(NSRightArrowFunctionKey), [.command, .option]),
            item("Previous Space", #selector(C.previousSpace(_:)), arrow(NSLeftArrowFunctionKey), [.command, .option]),
            .separator(),
        ]
        for number in 1...9 {
            spaceItems.append(item("Space \(number)", #selector(C.selectSpaceByNumber(_:)), "\(number)", [.control], tag: number))
        }
        spaceItems += [
            .separator(),
            item("New Space", #selector(C.newSpace(_:))),
            item("Rename Space…", #selector(C.renameSpace(_:))),
        ]
        main.addItem(submenu("Spaces", spaceItems))

        let windowMenu = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Downloads", #selector(C.showDownloads(_:)), "j", [.command, .shift]),
        ])
        main.addItem(windowMenu)
        NSApp.windowsMenu = windowMenu.submenu

        defaults = [:]
        forEachItem(in: main) { item in
            if let id = item.identifier?.rawValue { defaults[id] = Shortcut(key: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask) }
        }
        return main
    }

    // MARK: - Remapping

    /// A key equivalent and its modifiers, stored as "key|modifiers".
    public struct Shortcut: Equatable {
        public var key: String
        public var modifiers: NSEvent.ModifierFlags

        init(key: String, modifiers: NSEvent.ModifierFlags) {
            self.key = key
            self.modifiers = key.isEmpty ? [] : modifiers.intersection([.command, .option, .control, .shift])
        }

        init?(stored: String) {
            let parts = stored.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let raw = UInt(parts[1]) else { return nil }
            self.init(key: String(parts[0]), modifiers: NSEvent.ModifierFlags(rawValue: raw))
        }

        var stored: String { "\(key)|\(modifiers.rawValue)" }

        /// "⇧⌘C", in the order macOS shows modifiers.
        public var display: String {
            guard !key.isEmpty else { return "—" }
            var text = ""
            if modifiers.contains(.control) { text += "⌃" }
            if modifiers.contains(.option) { text += "⌥" }
            if modifiers.contains(.shift) { text += "⇧" }
            if modifiers.contains(.command) { text += "⌘" }
            let names: [String: String] = [
                "\t": "⇥", "\r": "↩", " ": "Space", "\u{1b}": "⎋",
                MainMenu.arrow(NSLeftArrowFunctionKey): "←", MainMenu.arrow(NSRightArrowFunctionKey): "→",
                MainMenu.arrow(NSUpArrowFunctionKey): "↑", MainMenu.arrow(NSDownArrowFunctionKey): "↓",
            ]
            return text + (names[key] ?? key.uppercased())
        }
    }

    /// Shortcuts every Mac app shares, which stay as they are: editing (⌘Z, ⌘X, ⌘C, ⌘V,
    /// ⌘A) and the app menu (⌘, ⌘H ⌘Q).
    private static let reservedActions: Set<Selector> = [
        Selector(("undo:")), Selector(("redo:")), #selector(NSText.cut(_:)), #selector(NSText.copy(_:)),
        #selector(NSText.paste(_:)), #selector(NSText.selectAll(_:)),
    ]

    private static func isReserved(_ item: NSMenuItem, in menu: NSMenu) -> Bool {
        if let action = item.action, reservedActions.contains(action) { return true }
        // The app menu (About, Settings, Hide, Quit).
        guard let appMenu = menu.items.first?.submenu else { return false }
        return appMenu.items.contains { $0 === item }
    }

    /// The items that can be remapped, menu by menu, for the settings.
    public static func remappableItems(in menu: NSMenu?) -> [(menu: String, title: String, id: String)] {
        guard let menu else { return [] }
        var result: [(String, String, String)] = []
        for top in menu.items.dropFirst() {
            for item in top.submenu?.items ?? [] {
                // Only Chord's own items: macOS adds some (Close All…) that it manages itself.
                guard let id = item.identifier?.rawValue, defaults[id] != nil, !isReserved(item, in: menu) else { continue }
                result.append((top.title, item.title, id))
            }
        }
        return result
    }

    /// Who already answers `shortcut`, besides the item `id`: another command, or a
    /// reserved shortcut that cannot be taken.
    public static func owner(of shortcut: Shortcut, besides id: String, in menu: NSMenu?) -> (id: String, title: String, reserved: Bool)? {
        guard let menu, !shortcut.key.isEmpty else { return nil }
        var found: (String, String, Bool)?
        forEachItem(in: menu) { item in
            guard found == nil, let itemID = item.identifier?.rawValue, itemID != id, defaults[itemID] != nil,
                  Shortcut(key: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask) == shortcut else { return }
            found = (itemID, item.title, isReserved(item, in: menu))
        }
        return found
    }

    public static func defaultShortcut(for id: String) -> Shortcut? { defaults[id] }

    public static func currentShortcut(for id: String, in menu: NSMenu?) -> Shortcut? {
        var found: Shortcut?
        if let menu {
            forEachItem(in: menu) { item in
                if item.identifier?.rawValue == id { found = Shortcut(key: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask) }
            }
        }
        return found
    }

    /// Applies the remapped shortcuts (and puts back the default for the others).
    public static func apply(_ overrides: [String: String], to menu: NSMenu?) {
        guard let menu else { return }
        forEachItem(in: menu) { item in
            guard let id = item.identifier?.rawValue, let original = defaults[id] else { return }
            let shortcut = overrides[id].flatMap(Shortcut.init(stored:)) ?? original
            item.keyEquivalent = shortcut.key
            item.keyEquivalentModifierMask = shortcut.modifiers
        }
    }

    // MARK: - Building

    private static func forEachItem(in menu: NSMenu, _ body: (NSMenuItem) -> Void) {
        for item in menu.items {
            body(item)
            if let submenu = item.submenu { forEachItem(in: submenu, body) }
        }
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = [.command], tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.tag = tag
        if let action {
            let name = NSStringFromSelector(action)
            item.identifier = NSUserInterfaceItemIdentifier(tag == 0 ? name : "\(name)#\(tag)")
        }
        return item
    }

    /// Points the items with these actions at `target` instead of the responder chain.
    public static func setTarget(_ target: AnyObject, for actions: [Selector], in menu: NSMenu) {
        items(with: actions, in: menu).forEach { $0.target = target }
    }

    /// The items of `menu` and its submenus with one of these actions.
    static func items(with actions: [Selector], in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item -> [NSMenuItem] in
            let own = item.action.map(actions.contains) == true ? [item] : []
            return own + (item.submenu.map { items(with: actions, in: $0) } ?? [])
        }
    }

    /// An item that is not shown in the menu but still answers its shortcut: a second
    /// shortcut for an action (⌘B besides ⌘S for the sidebar).
    private static func hidden(_ item: NSMenuItem) -> NSMenuItem {
        item.isHidden = true
        item.allowsKeyEquivalentWhenHidden = true
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach { menu.addItem($0) }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = menu
        return parent
    }

    fileprivate static func arrow(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt32(key))!))
    }
}
