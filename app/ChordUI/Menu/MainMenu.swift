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
            item("À propos de \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Réglages…", #selector(C.showSettings(_:)), ","),
            .separator(),
            item("Masquer \(appName)", #selector(NSApplication.hide(_:)), "h"),
            item("Masquer les autres", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Tout afficher", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quitter \(appName)", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        main.addItem(submenu("Fichier", [
            item("Nouvel onglet", #selector(C.newTab(_:)), "t"),
            item("Nouvelle petite fenêtre", #selector(C.newLittleWindow(_:)), "n", [.command, .option]),
            item("Ouvrir l'adresse", #selector(C.openLocation(_:)), "l"),
            .separator(),
            item("Fermer l'onglet", #selector(C.closeTab(_:)), "w"),
            item("Rouvrir l'onglet fermé", #selector(C.reopenClosedTab(_:)), "t", [.command, .shift]),
            item("Fermer la fenêtre", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]),
            .separator(),
            item("Importer depuis Arc…", #selector(C.importFromArc(_:))),
        ]))

        main.addItem(submenu("Édition", [
            item("Annuler", Selector(("undo:")), "z"),
            item("Rétablir", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Couper", #selector(NSText.cut(_:)), "x"),
            item("Copier", #selector(NSText.copy(_:)), "c"),
            item("Coller", #selector(NSText.paste(_:)), "v"),
            item("Tout sélectionner", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Copier l'URL", #selector(C.copyURL(_:)), "c", [.command, .shift]),
        ]))

        main.addItem(submenu("Affichage", [
            item("Masquer la barre latérale", #selector(C.toggleSidebarVisibility(_:)), "s"),
            hidden(item("Barre latérale (second raccourci)", #selector(C.toggleSidebarVisibility(_:)), "b", tag: 2)),
            item("Split view", #selector(C.toggleSplitView(_:)), "d", [.command, .shift]),
            item("Barre d'adresse en haut", #selector(C.toggleAddressBarPosition(_:))),
            item("Mode edgeless", #selector(C.toggleEdgeless(_:))),
            .separator(),
            item("Recharger la page", #selector(C.reloadPage(_:)), "r"),
            item("Recharger sans le cache", #selector(C.reloadPageIgnoringCache(_:)), "r", [.command, .shift]),
            item("Arrêter le chargement", #selector(C.stopLoading(_:)), "."),
            .separator(),
            item("Plein écran", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))

        main.addItem(submenu("Historique", [
            item("Précédent", #selector(C.goBack(_:)), "["),
            item("Suivant", #selector(C.goForward(_:)), "]"),
        ]))

        var tabItems: [NSMenuItem] = [
            item("Onglet suivant", #selector(C.nextTab(_:)), "\t", [.control]),
            item("Onglet précédent", #selector(C.previousTab(_:)), "\t", [.control, .shift]),
            .separator(),
            item("Épingler l'onglet", #selector(C.togglePinTab(_:)), "d"),
            item("Ajouter aux favoris", #selector(C.toggleFavoriteTab(_:))),
            item("Nouveau dossier", #selector(C.newFolder(_:))),
            .separator(),
        ]
        for number in 1...9 {
            let title = number == 9 ? "Dernier onglet" : "Onglet \(number)"
            tabItems.append(item(title, #selector(C.selectTabByNumber(_:)), "\(number)", tag: number))
        }
        main.addItem(submenu("Onglets", tabItems))

        var spaceItems: [NSMenuItem] = [
            item("Space suivant", #selector(C.nextSpace(_:)), arrow(NSRightArrowFunctionKey), [.command, .option]),
            item("Space précédent", #selector(C.previousSpace(_:)), arrow(NSLeftArrowFunctionKey), [.command, .option]),
            .separator(),
        ]
        for number in 1...9 {
            spaceItems.append(item("Space \(number)", #selector(C.selectSpaceByNumber(_:)), "\(number)", [.control], tag: number))
        }
        spaceItems += [
            .separator(),
            item("Nouveau Space", #selector(C.newSpace(_:))),
            item("Renommer le Space…", #selector(C.renameSpace(_:))),
        ]
        main.addItem(submenu("Spaces", spaceItems))

        let windowMenu = submenu("Fenêtre", [
            item("Réduire", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Agrandir", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Téléchargements", #selector(C.showDownloads(_:)), "j", [.command, .shift]),
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

        /// "⇧⌘D", in the order macOS shows modifiers.
        public var display: String {
            guard !key.isEmpty else { return "—" }
            var text = ""
            if modifiers.contains(.control) { text += "⌃" }
            if modifiers.contains(.option) { text += "⌥" }
            if modifiers.contains(.shift) { text += "⇧" }
            if modifiers.contains(.command) { text += "⌘" }
            let names: [String: String] = [
                "\t": "⇥", "\r": "↩", " ": "Espace", "\u{1b}": "⎋",
                MainMenu.arrow(NSLeftArrowFunctionKey): "←", MainMenu.arrow(NSRightArrowFunctionKey): "→",
                MainMenu.arrow(NSUpArrowFunctionKey): "↑", MainMenu.arrow(NSDownArrowFunctionKey): "↓",
            ]
            return text + (names[key] ?? key.uppercased())
        }
    }

    /// The items that can be remapped, menu by menu, for the settings.
    public static func remappableItems(in menu: NSMenu?) -> [(menu: String, title: String, id: String)] {
        guard let menu else { return [] }
        var result: [(String, String, String)] = []
        for top in menu.items.dropFirst() {
            for item in top.submenu?.items ?? [] {
                // Only Chord's own items: macOS adds some (Tout fermer…) that it manages itself.
                guard let id = item.identifier?.rawValue, defaults[id] != nil else { continue }
                result.append((top.title, item.title, id))
            }
        }
        return result
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
