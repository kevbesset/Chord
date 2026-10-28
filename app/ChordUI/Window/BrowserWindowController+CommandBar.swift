import AppKit
import Combine

// The command bar and the Peek.
extension BrowserWindowController {
    // MARK: - Command bar

    func presentCommandBar(mode: CommandBarController.Mode, text: String, anchoredTo anchor: NSView? = nil) {
        pendingHide?.cancel()
        if peek.isVisible { peek.dismiss() }
        commandBar.present(in: rootView, centeredOn: pageArea, anchoredTo: anchor, mode: mode, text: text, accent: state.activeSpace.accent)
    }

    /// The address field on screen, if there is one: the top bar's, or the sidebar's
    /// while the sidebar shows.
    var visibleAddressField: NSView? {
        let toolbarAddress = pageArea.toolbar.addressAnchor
        if addressBarOnTop {
            return toolbarAddress.window != nil && !toolbarAddress.isHiddenOrHasHiddenAncestor ? toolbarAddress : nil
        }
        return sidebarMode == .hidden ? nil : sidebar.addressAnchor
    }

    func commandActions() -> [CommandItem] {
        let selected = state.selectedTab
        var actions = [
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: state.isSplit ? String(localized: "Exit Split View", bundle: .chordUI) : String(localized: "Open in Split View", bundle: .chordUI),
                        symbol: "rectangle.split.2x1", shortcut: "⌃⇧=", action: .run { [weak self] in self?.toggleSplitView(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Open in Little Window", bundle: .chordUI), symbol: "macwindow.on.rectangle", shortcut: "⌥⌘N",
                        action: .run { [weak self] in self?.openLittleWindow(url: self?.state.selectedTab?.url) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "New Tab in Space \(state.activeSpace.name)", bundle: .chordUI), symbol: "plus", shortcut: "⌘T",
                        action: .run { [weak self] in self?.newTab(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: sidebarMode == .docked ? String(localized: "Hide Sidebar", bundle: .chordUI) : String(localized: "Show Sidebar", bundle: .chordUI),
                        symbol: "sidebar.left", shortcut: "⌘S", action: .run { [weak self] in self?.toggleSidebarVisibility(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Copy URL", bundle: .chordUI), symbol: "link", shortcut: "⇧⌘C",
                        action: .run { [weak self] in self?.copyURL(nil) }),
        ]
        if let selected {
            actions += [
                CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: selected.isPinned ? String(localized: "Unpin Tab", bundle: .chordUI) : String(localized: "Pin Tab", bundle: .chordUI), symbol: "pin",
                            shortcut: "⌘D", action: .run { [weak self] in self?.togglePinTab(nil) }),
                CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: selected.isFavorite ? String(localized: "Remove from Favorites", bundle: .chordUI) : String(localized: "Add to Favorites", bundle: .chordUI), symbol: "star",
                            action: .run { [weak self] in self?.toggleFavoriteTab(nil) }),
            ]
        }
        actions += [
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Reopen Closed Tab", bundle: .chordUI), symbol: "arrow.uturn.backward", shortcut: "⇧⌘T",
                        action: .run { [weak self] in self?.reopenClosedTab(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "History", bundle: .chordUI), subtitle: "chord://history", symbol: "clock.arrow.circlepath",
                        shortcut: "⌘Y", action: .run { [weak self] in self?.showHistory(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Browser Settings", bundle: .chordUI), subtitle: "chord://settings", symbol: "gearshape",
                        action: .run { [weak self] in self?.openInternalPage("settings") }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Extensions", bundle: .chordUI), subtitle: "chord://extensions", symbol: "puzzlepiece.extension",
                        action: .run { [weak self] in self?.openInternalPage("extensions") }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "New Folder", bundle: .chordUI), symbol: "folder.badge.plus",
                        action: .run { [weak self] in self?.newFolder(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "New Space", bundle: .chordUI), symbol: "square.stack",
                        action: .run { [weak self] in self?.newSpace(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Rename Space", bundle: .chordUI), symbol: "pencil",
                        action: .run { [weak self] in self?.renameSpace(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Next Space", bundle: .chordUI), symbol: "arrow.right.square", shortcut: "⌥⌘→",
                        action: .run { [weak self] in self?.nextSpace(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: addressBarOnTop ? String(localized: "Address Bar in Sidebar", bundle: .chordUI) : String(localized: "Address Bar on Top", bundle: .chordUI),
                        symbol: "menubar.rectangle", shortcut: "⇧⌘D", action: .run { [weak self] in self?.toggleAddressBarPosition(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: settings.edgeless ? String(localized: "Turn Off Edgeless Mode", bundle: .chordUI) : String(localized: "Turn On Edgeless Mode", bundle: .chordUI),
                        symbol: "rectangle.inset.filled", action: .run { [weak self] in self?.toggleEdgeless(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Import from Arc", bundle: .chordUI), symbol: "square.and.arrow.down",
                        action: .run { [weak self] in self?.importFromArc(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Import Logins from Arc", bundle: .chordUI), symbol: "key",
                        action: .run { [weak self] in self?.importArcLogins(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Import from Another Browser", bundle: .chordUI), symbol: "square.and.arrow.down.on.square",
                        action: .run { [weak self] in self?.importFromBrowser(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Archived Tabs", bundle: .chordUI), symbol: "archivebox", shortcut: "⌥⌘A",
                        action: .run { [weak self] in self?.showArchive(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Settings", bundle: .chordUI), symbol: "gearshape", shortcut: "⌘,",
                        action: .run { [weak self] in self?.showSettings(nil) }),
        ]
        return actions
    }

    // MARK: - Peek

    func makePeek() -> PeekController {
        let peek = PeekController(engine: { [state] in state.engine(for: state.activeSpace) })
        peek.onOpenInTab = { [weak self] page in
            guard let self else { return }
            self.state.openTab(url: page.url ?? URL(string: "about:blank")!, adopting: page)
        }
        peek.onSplit = { [weak self] page in
            guard let self else { return }
            let tab = self.state.openTab(url: page.url ?? URL(string: "about:blank")!, select: false, adopting: page)
            self.state.addToSplit(tab)
        }
        peek.onNewTab = { [weak self] url in self?.state.openTab(url: url) }
        peek.onDismiss = { [weak self] in self?.focusPage() }
        return peek
    }

    func presentPeek(_ url: URL) {
        if commandBar.isVisible { commandBar.dismiss() }
        let inset = sidebarMode == .docked ? settings.sidebarWidth : 0
        peek.present(url: url, in: rootView, contentInset: inset, accent: state.activeSpace.accent)
    }
}
