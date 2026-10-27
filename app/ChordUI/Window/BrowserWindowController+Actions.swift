import AppKit
import Combine

// Menu actions, find, zoom and print.
extension BrowserWindowController {
    // MARK: - Menu actions (reached through the responder chain)

    @objc public func newTab(_ sender: Any?) {
        presentCommandBar(mode: .newTab, text: "")
    }

    @objc public func newLittleWindow(_ sender: Any?) {
        openLittleWindow(url: nil)
    }

    /// ⌘L or a click on the address: like Arc, the compact bar over the address field
    /// when one is on screen.
    @objc public func openLocation(_ sender: Any?) {
        presentCommandBar(mode: .currentTab, text: state.selectedTab?.url?.editableString ?? "", anchoredTo: visibleAddressField)
    }

    @objc public func closeTab(_ sender: Any?) {
        if peek.isVisible {
            peek.dismiss()
        } else if siteControls.isVisible {
            siteControls.dismiss()
        } else if commandBar.isVisible {
            commandBar.dismiss()
        } else if let tab = state.selectedTab {
            state.close(tab)
        }
    }

    @objc public func reopenClosedTab(_ sender: Any?) {
        state.reopenClosedTab()
    }

    /// ⌘S, and ⌘B. Not named `toggleSidebar:`: AppKit's windows answer that action for
    /// their own split-view sidebars and disable it, so the menu item never reached Chord.
    @objc public func toggleSidebarVisibility(_ sender: Any?) {
        setSidebarMode(sidebarMode == .docked ? .hidden : .docked, animated: true)
    }

    /// ⌃⇧=: from a Peek, puts it beside the page; otherwise opens a split by asking for
    /// the second page in the command bar, or leaves the split on screen.
    @objc public func toggleSplitView(_ sender: Any?) {
        let interval = Perf.begin("split.toggle")
        if peek.isVisible {
            peek.openInSplit()
        } else if state.isSplit {
            state.unsplit()
        } else if state.selectedTab != nil {
            presentCommandBar(mode: .split, text: "")
        }
        DispatchQueue.main.async { interval.end() }
    }

    @objc public func toggleEdgeless(_ sender: Any?) {
        settings.edgeless.toggle()
    }

    /// Only for the profile of the Space shown: Spaces on other profiles keep theirs.
    @objc public func toggleAddressBarPosition(_ sender: Any?) {
        state.setAddressBarOnTop(!addressBarOnTop, for: state.activeSpace)
    }

    @objc public func togglePinTab(_ sender: Any?) {
        if let tab = state.selectedTab { state.togglePin(tab) }
    }

    @objc public func toggleFavoriteTab(_ sender: Any?) {
        if let tab = state.selectedTab { state.toggleFavorite(tab) }
    }

    /// A folder in the pinned tabs, named right away.
    @objc public func newFolder(_ sender: Any?) {
        promptRename(state.newFolder())
    }

    @objc public func reloadPage(_ sender: Any?) {
        state.selectedTab?.page?.reload()
    }

    /// ⇧⌘R: reload without the cache, falling back to a plain reload.
    @objc public func reloadPageIgnoringCache(_ sender: Any?) {
        guard let page = state.selectedTab?.page else { return }
        if let reloadIgnoringCache = page.reloadIgnoringCache { reloadIgnoringCache() } else { page.reload() }
    }

    @objc public func stopLoading(_ sender: Any?) {
        state.selectedTab?.page?.stopLoading()
    }

    /// ⌥⌘I, when the engine has developer tools (Chromium's DevTools).
    @objc public func toggleDevTools(_ sender: Any?) {
        state.selectedTab?.page?.toggleDevTools?()
    }

    /// ⌃⌘P: the page's video in a picture-in-picture window, or back.
    @objc public func togglePictureInPicture(_ sender: Any?) {
        state.selectedTab?.page?.togglePictureInPicture?()
    }

    /// The reload buttons turn into stop buttons while the page loads, like Arc's.
    func reloadOrStop() {
        if state.selectedTab?.page?.isLoading == true { stopLoading(nil) } else { reloadPage(nil) }
    }

    @objc public func goBack(_ sender: Any?) {
        state.selectedTab?.page?.goBack()
    }

    @objc public func goForward(_ sender: Any?) {
        state.selectedTab?.page?.goForward()
    }

    @objc public func nextTab(_ sender: Any?) {
        state.selectTab(offset: 1)
    }

    @objc public func previousTab(_ sender: Any?) {
        state.selectTab(offset: -1)
    }

    /// ⌘1…⌘9; the menu item's tag is the number.
    @objc public func selectTabByNumber(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        state.selectTab(number: item.tag)
    }

    @objc public func copyURL(_ sender: Any?) {
        copy(state.selectedTab?.url)
    }

    // MARK: - Find, zoom, print

    func setUpFindBar() {
        let bar = pageArea.findBar
        bar.onChange = { [weak self] text in self?.findPage?.find?(text, forward: true) }
        bar.onNext = { [weak self] in self?.findNext(nil) }
        bar.onPrevious = { [weak self] in self?.findPrevious(nil) }
        bar.onClose = { [weak self] in self?.closeFindBar(focusPage: true) }
    }

    /// ⌘F: the find bar over the selected page, its text selected to type a new one.
    /// The text stays from one search to the next, like Safari's.
    @objc public func showFindBar(_ sender: Any?) {
        guard let page = state.selectedTab?.page, page.find != nil else { return }
        let interval = Perf.begin("find.open")
        if commandBar.isVisible { commandBar.dismiss() }
        let bar = pageArea.findBar
        let wasHidden = bar.isHidden
        if findPage !== page {
            findPage?.stopFinding?()
            findPage = page
        }
        if wasHidden {
            bar.clearResult()
            bar.isHidden = false
            pageArea.needsLayout = true
            pageArea.layoutSubtreeIfNeeded()
            bar.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                bar.animator().alphaValue = 1
            }
            // Searches the text left from the last time again.
            if !bar.text.isEmpty { page.find?(bar.text, forward: true) }
        }
        bar.focus()
        DispatchQueue.main.async { interval.end() }
    }

    /// ⌘G and ⇧⌘G: the next or previous match, opening the find bar if needed.
    @objc public func findNext(_ sender: Any?) {
        find(forward: true)
    }

    @objc public func findPrevious(_ sender: Any?) {
        find(forward: false)
    }

    func find(forward: Bool) {
        let bar = pageArea.findBar
        guard !bar.isHidden, let page = findPage else {
            showFindBar(nil)
            return
        }
        guard !bar.text.isEmpty else { return }
        page.find?(bar.text, forward: forward)
    }

    func closeFindBar(focusPage focus: Bool) {
        let bar = pageArea.findBar
        guard !bar.isHidden else { return }
        findPage?.stopFinding?()
        findPage = nil
        bar.isHidden = true
        if focus { focusPage() }
    }

    @objc public func zoomIn(_ sender: Any?) { zoom(1) }
    @objc public func zoomOut(_ sender: Any?) { zoom(-1) }
    @objc public func actualSize(_ sender: Any?) { zoom(0) }

    /// The engine keeps the zoom per site; the toast says where it is now.
    func zoom(_ direction: Int) {
        guard let page = state.selectedTab?.page, let zoomPage = page.zoom else { return }
        zoomPage(direction)
        let percent = page.zoomPercent ?? 100
        let text = (Double(percent) / 100).formatted(.percent.locale(.chordUI))
        let symbol = direction > 0 ? "plus.magnifyingglass" : direction < 0 ? "minus.magnifyingglass" : "1.magnifyingglass"
        toast.show(text, detail: state.selectedTab?.url?.displayHost, symbol: symbol, in: rootView, over: pageArea, accent: state.activeSpace.accent)
    }

    @objc public func printPage(_ sender: Any?) {
        state.selectedTab?.page?.printPage?()
    }

    /// ⌥⌘U: the page's source, in a new tab.
    @objc public func viewSource(_ sender: Any?) {
        guard let url = state.selectedTab?.url, !url.absoluteString.hasPrefix("view-source:"),
              let source = URL(string: "view-source:" + url.absoluteString) else { return }
        state.openTab(url: source)
    }

    @objc public func toggleMuteTab(_ sender: Any?) {
        if let tab = state.selectedTab { state.toggleMute(tab) }
    }

    /// One of Chromium's internal pages (chord://settings…), in a new tab.
    func openInternalPage(_ path: String) {
        guard let url = URL(string: "chrome://\(path)") else { return }
        state.openTab(url: url)
    }

    /// The selected page's site controls (permissions, quick actions), like Arc's.
    func showSiteControls(from anchor: NSView) {
        guard let tab = state.selectedTab, let page = tab.page, let url = tab.url else { return }
        pendingHide?.cancel()
        if commandBar.isVisible { commandBar.dismiss() }
        siteControls.isGlass = settings.commandBarGlass
        siteControls.onCopy = { [weak self] in self?.copy(url) }
        siteControls.onOpen = { [weak self] url in self?.state.openTab(url: url) }
        siteControls.onDismiss = { [weak self] in
            self?.focusPage()
            self?.resumePermissionPrompt()
        }
        // A site's question waiting there steps aside, and comes back after.
        permissionPrompt.suspend()
        siteControlsTabID = tab.id
        siteControls.present(page: page, url: url, in: rootView, below: anchor)
    }

    @objc public func nextSpace(_ sender: Any?) {
        state.selectSpace(offset: 1)
    }

    @objc public func previousSpace(_ sender: Any?) {
        state.selectSpace(offset: -1)
    }

    /// ⌃1…⌃9; the menu item's tag is the number.
    @objc public func selectSpaceByNumber(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        state.selectSpace(number: item.tag)
    }

    @objc public func newSpace(_ sender: Any?) {
        let space = state.addSpace()
        promptRename(space)
    }

    @objc public func renameSpace(_ sender: Any?) {
        promptRename(state.activeSpace)
    }

    @objc public func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(state: state, settings: settings,
                                                      onImportArc: { [weak self] in self?.importFromArc(nil) },
                                                      onImportBrowser: { [weak self] in self?.importFromBrowser(nil) })
            settingsWindow?.window?.appearance = settings.appearance.nsAppearance
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    /// Arc's sidebar, then the logins, passwords and history of its profiles.
    @objc public func importFromArc(_ sender: Any?) {
        guard let window else { return }
        let sidebar: String
        do {
            let result = try ArcImport.load()
            let count = state.importFromArc(result)
            let favorites = result.favorites.values.reduce(0) { $0 + $1.count }
            sidebar = String(localized: "\(result.spaces.count) Spaces, \(result.folderCount) folders, \(favorites) favorites, \(count) tabs in all, with Arc's icons. A Space imported before is updated rather than duplicated.", bundle: .chordUI)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Couldn't import from Arc", bundle: .chordUI)
            alert.informativeText = (error as? ArcImport.Failure) == .notFound
                ? String(localized: "Arc's sidebar can't be found on this Mac.", bundle: .chordUI)
                : String(localized: "Arc's sidebar file couldn't be read.", bundle: .chordUI)
            alert.beginSheetModal(for: window)
            return
        }
        state.importArcData { [weak self] data in
            self?.showArcImport(title: String(localized: "Arc imported", bundle: .chordUI), sidebar: sidebar, data: data)
        }
    }

    /// Only the logins, passwords and history of Arc's profiles, into the profiles of
    /// the Spaces that came from them, without touching the sidebar.
    @objc public func importArcLogins(_ sender: Any?) {
        state.importArcData { [weak self] data in
            self?.showArcImport(title: String(localized: "Arc logins imported", bundle: .chordUI), sidebar: nil, data: data)
        }
    }

    func showArcImport(title: String, sidebar: String?, data: BrowserState.ArcDataImport) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        var lines: [String] = sidebar.map { [$0] } ?? []
        if data.profiles == 0 {
            lines.append(String(localized: "No Space comes from an Arc profile: nothing else to bring over.", bundle: .chordUI))
        } else if data.keyDenied {
            alert.alertStyle = .warning
            lines.append(String(localized: "macOS didn't give access to Arc's key: logins and passwords stayed in Arc. \(data.pages) history pages imported.", bundle: .chordUI))
        } else {
            lines.append(String(localized: "\(data.cookies) login cookies, \(data.passwords) passwords and \(data.pages) history pages imported, each into the profile of its Spaces. What was already in Chord is kept.", bundle: .chordUI))
        }
        if data.extensions > 0 {
            lines.append(data.extensions == 1 ? String(localized: "1 extension installed from the Chrome Web Store.", bundle: .chordUI) : String(localized: "\(data.extensions) extensions installed from the Chrome Web Store.", bundle: .chordUI))
        }
        if data.siteStorage || data.extensions > 0 {
            lines.append(String(localized: "Site and extension data arrive at Chord's next launch.", bundle: .chordUI))
        }
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.beginSheetModal(for: window)
    }

    /// ⇧⌘J: the downloads panel, above the downloads button, or from the window's
    /// bottom-left corner while the sidebar is hidden.
    @objc public func showDownloads(_ sender: Any?) {
        if downloadsPopover.isShown {
            downloadsPopover.performClose(nil)
            return
        }
        if sidebarMode == .hidden {
            let corner = NSRect(x: 16, y: 8, width: 1, height: 1)
            downloadsPopover.show(relativeTo: corner, of: rootView, preferredEdge: .maxY)
        } else {
            let anchor = sidebar.downloadsAnchor
            downloadsPopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        }
    }

    func makeDownloadsPopover() -> NSPopover {
        let panel = DownloadsPanelController(downloads: state.downloads)
        panel.onCancel = { [weak self] id in self?.state.cancelDownload(id) }
        panel.onKeep = { [weak self] id in self?.state.keepDownload(id) }
        panel.onDismissFailed = { [weak self] id in self?.state.downloads.remove(id: id) }
        let popover = NSPopover()
        popover.contentViewController = panel
        popover.behavior = .transient
        popover.animates = true
        return popover
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleEdgeless(_:)):
            menuItem.state = settings.edgeless ? .on : .off
            return true
        case #selector(toggleAddressBarPosition(_:)):
            menuItem.state = addressBarOnTop ? .on : .off
            return true
        case #selector(toggleSidebarVisibility(_:)):
            // The hidden ⌘B item keeps its own name in the shortcut settings.
            if menuItem.tag == 0 {
                menuItem.title = sidebarMode == .docked ? String(localized: "Hide Sidebar", bundle: .chordUI) : String(localized: "Show Sidebar", bundle: .chordUI)
            }
            return true
        case #selector(toggleSplitView(_:)):
            menuItem.title = state.isSplit ? String(localized: "Exit Split View", bundle: .chordUI) : String(localized: "Split View", bundle: .chordUI)
            return state.selectedTab != nil
        case #selector(togglePinTab(_:)):
            menuItem.title = state.selectedTab?.isPinned == true ? String(localized: "Unpin Tab", bundle: .chordUI) : String(localized: "Pin Tab", bundle: .chordUI)
            return state.selectedTab != nil
        case #selector(toggleFavoriteTab(_:)):
            menuItem.title = state.selectedTab?.isFavorite == true ? String(localized: "Remove from Favorites", bundle: .chordUI) : String(localized: "Add to Favorites", bundle: .chordUI)
            return state.selectedTab != nil
        case #selector(reopenClosedTab(_:)):
            return state.canReopenClosedTab
        case #selector(selectSpaceByNumber(_:)):
            return menuItem.tag <= state.spaces.count
        case #selector(importFromArc(_:)):
            return ArcImport.isAvailable
        case #selector(importArcLogins(_:)):
            return !state.isPrivate && state.spaces.contains { ArcImport.profileFolder(forChordProfile: $0.profileID) != nil }
        case #selector(goBack(_:)), #selector(goForward(_:)):
            // ⌘← / ⌘→ belong to the text being typed, in the command bar or a field.
            if menuItem.tag == 2, window?.firstResponder is NSText { return false }
            let page = state.selectedTab?.page
            return (menuItem.action == #selector(goBack(_:)) ? page?.canGoBack : page?.canGoForward) ?? false
        case #selector(togglePictureInPicture(_:)):
            return (state.selectedTab?.page as AnyObject?)?.responds(to: #selector(ChordWebPage.togglePictureInPicture)) ?? false
        case #selector(toggleDevTools(_:)):
            return (state.selectedTab?.page as AnyObject?)?.responds(to: #selector(ChordWebPage.toggleDevTools)) ?? false
        case #selector(stopLoading(_:)):
            return state.selectedTab?.page?.isLoading ?? false
        case #selector(reloadPage(_:)), #selector(reloadPageIgnoringCache(_:)), #selector(copyURL(_:)):
            return state.selectedTab != nil
        case #selector(showFindBar(_:)), #selector(findNext(_:)), #selector(findPrevious(_:)):
            return state.selectedTab?.page?.find != nil
        case #selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(actualSize(_:)):
            return state.selectedTab?.page?.zoom != nil
        case #selector(printPage(_:)):
            return state.selectedTab?.page?.printPage != nil
        case #selector(viewSource(_:)):
            guard let url = state.selectedTab?.url else { return false }
            return !url.absoluteString.hasPrefix("view-source:") && url.scheme != "chrome"
        case #selector(toggleMuteTab(_:)):
            let page = state.selectedTab?.page
            menuItem.title = page?.isMuted == true ? String(localized: "Unmute Tab", bundle: .chordUI) : String(localized: "Mute Tab", bundle: .chordUI)
            return page?.setMuted != nil
        case #selector(closeTab(_:)):
            return state.selectedTab != nil || commandBar.isVisible || peek.isVisible
        default:
            return true
        }
    }
}
