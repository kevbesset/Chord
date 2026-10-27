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
            item(String(localized: "About \(appName)", bundle: .chordUI), #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            // Handled by ChordUIHost's updater (Sparkle).
            item(String(localized: "Check for Updates…", bundle: .chordUI), Selector(("checkForUpdates:"))),
            .separator(),
            item(String(localized: "Settings…", bundle: .chordUI), #selector(C.showSettings(_:)), ","),
            .separator(),
            item(String(localized: "Hide \(appName)", bundle: .chordUI), #selector(NSApplication.hide(_:)), "h"),
            item(String(localized: "Hide Others", bundle: .chordUI), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item(String(localized: "Show All", bundle: .chordUI), #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item(String(localized: "Quit \(appName)", bundle: .chordUI), #selector(NSApplication.terminate(_:)), "q"),
        ]))

        main.addItem(submenu(String(localized: "File", bundle: .chordUI), [
            item(String(localized: "New Tab", bundle: .chordUI), #selector(C.newTab(_:)), "t"),
            // Handled by ChordUIHost's app actions, so that they work with no window open.
            item(String(localized: "New Window", bundle: .chordUI), Selector(("newWindow:")), "n"),
            item(String(localized: "New Private Window", bundle: .chordUI), Selector(("newPrivateWindow:")), "n", [.command, .shift]),
            item(String(localized: "New Little Window", bundle: .chordUI), #selector(C.newLittleWindow(_:)), "n", [.command, .option]),
            item(String(localized: "Open Location", bundle: .chordUI), #selector(C.openLocation(_:)), "l"),
            .separator(),
            item(String(localized: "Close Tab", bundle: .chordUI), #selector(C.closeTab(_:)), "w"),
            item(String(localized: "Reopen Closed Tab", bundle: .chordUI), #selector(C.reopenClosedTab(_:)), "t", [.command, .shift]),
            item(String(localized: "Close Window", bundle: .chordUI), #selector(NSWindow.performClose(_:)), "w", [.command, .shift]),
            .separator(),
            item(String(localized: "Print…", bundle: .chordUI), #selector(C.printPage(_:)), "p"),
            .separator(),
            item(String(localized: "Import from Arc…", bundle: .chordUI), #selector(C.importFromArc(_:))),
            item(String(localized: "Import Logins from Arc…", bundle: .chordUI), #selector(C.importArcLogins(_:))),
        ]))

        main.addItem(submenu(String(localized: "Edit", bundle: .chordUI), [
            item(String(localized: "Undo", bundle: .chordUI), Selector(("undo:")), "z"),
            item(String(localized: "Redo", bundle: .chordUI), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item(String(localized: "Cut", bundle: .chordUI), #selector(NSText.cut(_:)), "x"),
            item(String(localized: "Copy", bundle: .chordUI), #selector(NSText.copy(_:)), "c"),
            item(String(localized: "Paste", bundle: .chordUI), #selector(NSText.paste(_:)), "v"),
            item(String(localized: "Select All", bundle: .chordUI), #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item(String(localized: "Copy URL", bundle: .chordUI), #selector(C.copyURL(_:)), "c", [.command, .shift]),
            .separator(),
            submenu(String(localized: "Find", bundle: .chordUI), [
                item(String(localized: "Find…", bundle: .chordUI), #selector(C.showFindBar(_:)), "f"),
                item(String(localized: "Find Next", bundle: .chordUI), #selector(C.findNext(_:)), "g"),
                item(String(localized: "Find Previous", bundle: .chordUI), #selector(C.findPrevious(_:)), "g", [.command, .shift]),
            ]),
        ]))

        main.addItem(submenu(String(localized: "View", bundle: .chordUI), [
            item(String(localized: "Hide Sidebar", bundle: .chordUI), #selector(C.toggleSidebarVisibility(_:)), "s"),
            hidden(item(String(localized: "Sidebar (second shortcut)", bundle: .chordUI), #selector(C.toggleSidebarVisibility(_:)), "b", tag: 2)),
            // Arc's shortcuts: ⌃⇧= for the split view, ⇧⌘D for the address bar's place.
            item(String(localized: "Split View", bundle: .chordUI), #selector(C.toggleSplitView(_:)), "=", [.control, .shift]),
            item(String(localized: "Address Bar on Top", bundle: .chordUI), #selector(C.toggleAddressBarPosition(_:)), "d", [.command, .shift]),
            item(String(localized: "Edgeless Mode", bundle: .chordUI), #selector(C.toggleEdgeless(_:))),
            .separator(),
            item(String(localized: "Reload Page", bundle: .chordUI), #selector(C.reloadPage(_:)), "r"),
            item(String(localized: "Reload Ignoring Cache", bundle: .chordUI), #selector(C.reloadPageIgnoringCache(_:)), "r", [.command, .shift]),
            item(String(localized: "Stop Loading", bundle: .chordUI), #selector(C.stopLoading(_:)), "."),
            .separator(),
            // ⌘+ and ⌘= both zoom in, like Chrome and Arc.
            item(String(localized: "Zoom In", bundle: .chordUI), #selector(C.zoomIn(_:)), "+"),
            hidden(item(String(localized: "Zoom In (second shortcut)", bundle: .chordUI), #selector(C.zoomIn(_:)), "=", tag: 2)),
            item(String(localized: "Zoom Out", bundle: .chordUI), #selector(C.zoomOut(_:)), "-"),
            item(String(localized: "Actual Size", bundle: .chordUI), #selector(C.actualSize(_:)), "0"),
            .separator(),
            item(String(localized: "Translate Page", bundle: .chordUI), #selector(C.toggleTranslation(_:))),
            .separator(),
            item(String(localized: "Developer Tools", bundle: .chordUI), #selector(C.toggleDevTools(_:)), "i", [.command, .option]),
            item(String(localized: "View Source", bundle: .chordUI), #selector(C.viewSource(_:)), "u", [.command, .option]),
            item(String(localized: "Picture in Picture", bundle: .chordUI), #selector(C.togglePictureInPicture(_:)), "p", [.command, .control]),
            .separator(),
            item(String(localized: "Full Screen", bundle: .chordUI), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))

        main.addItem(submenu(String(localized: "History", bundle: .chordUI), [
            item(String(localized: "Back", bundle: .chordUI), #selector(C.goBack(_:)), "["),
            item(String(localized: "Forward", bundle: .chordUI), #selector(C.goForward(_:)), "]"),
            // ⌘← and ⌘→ too, like Arc and Chrome; off while typing, where they move the caret.
            hidden(item(String(localized: "Back (arrow)", bundle: .chordUI), #selector(C.goBack(_:)), arrow(NSLeftArrowFunctionKey), tag: 2)),
            hidden(item(String(localized: "Forward (arrow)", bundle: .chordUI), #selector(C.goForward(_:)), arrow(NSRightArrowFunctionKey), tag: 2)),
        ]))

        var tabItems: [NSMenuItem] = [
            item(String(localized: "Next Tab", bundle: .chordUI), #selector(C.nextTab(_:)), "\t", [.control]),
            item(String(localized: "Previous Tab", bundle: .chordUI), #selector(C.previousTab(_:)), "\t", [.control, .shift]),
            .separator(),
            item(String(localized: "Pin Tab", bundle: .chordUI), #selector(C.togglePinTab(_:)), "d"),
            item(String(localized: "Mute Tab", bundle: .chordUI), #selector(C.toggleMuteTab(_:))),
            item(String(localized: "Add to Favorites", bundle: .chordUI), #selector(C.toggleFavoriteTab(_:))),
            item(String(localized: "New Folder", bundle: .chordUI), #selector(C.newFolder(_:))),
            .separator(),
        ]
        for number in 1...9 {
            let title = number == 9 ? String(localized: "Last Tab", bundle: .chordUI) : String(localized: "Tab \(number)", bundle: .chordUI)
            tabItems.append(item(title, #selector(C.selectTabByNumber(_:)), "\(number)", tag: number))
        }
        main.addItem(submenu(String(localized: "Tabs", bundle: .chordUI), tabItems))

        var spaceItems: [NSMenuItem] = [
            item(String(localized: "Next Space", bundle: .chordUI), #selector(C.nextSpace(_:)), arrow(NSRightArrowFunctionKey), [.command, .option]),
            item(String(localized: "Previous Space", bundle: .chordUI), #selector(C.previousSpace(_:)), arrow(NSLeftArrowFunctionKey), [.command, .option]),
            .separator(),
        ]
        for number in 1...9 {
            spaceItems.append(item(String(localized: "Space \(number)", bundle: .chordUI), #selector(C.selectSpaceByNumber(_:)), "\(number)", [.control], tag: number))
        }
        spaceItems += [
            .separator(),
            item(String(localized: "New Space", bundle: .chordUI), #selector(C.newSpace(_:))),
            item(String(localized: "Rename Space…", bundle: .chordUI), #selector(C.renameSpace(_:))),
        ]
        main.addItem(submenu(String(localized: "Spaces", bundle: .chordUI), spaceItems))

        let windowMenu = submenu(String(localized: "Window", bundle: .chordUI), [
            item(String(localized: "Minimize", bundle: .chordUI), #selector(NSWindow.performMiniaturize(_:)), "m"),
            item(String(localized: "Zoom", bundle: .chordUI), #selector(NSWindow.performZoom(_:))),
            .separator(),
            item(String(localized: "Downloads", bundle: .chordUI), #selector(C.showDownloads(_:)), "j", [.command, .shift]),
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
                "\t": "⇥", "\r": "↩", " ": MainMenu.spaceKeyName, "\u{1b}": "⎋",
                MainMenu.arrow(NSLeftArrowFunctionKey): "←", MainMenu.arrow(NSRightArrowFunctionKey): "→",
                MainMenu.arrow(NSUpArrowFunctionKey): "↑", MainMenu.arrow(NSDownArrowFunctionKey): "↓",
            ]
            return text + (names[key] ?? key.uppercased())
        }
    }

    /// The space bar's name in a shortcut ("⌃Space").
    static let spaceKeyName = String(localized: "key.space", defaultValue: "Space", bundle: .chordUI,
                                     comment: "The space bar, in a shortcut such as ⌃Space")

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
