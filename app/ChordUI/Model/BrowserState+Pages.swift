import AppKit
import Combine

// Tabs' pages and the session; what the engine tells about pages.
extension BrowserState {
    // MARK: - Pages

    /// The engine of a profile, whose pages run in that profile's session.
    func engine(forProfile id: String) -> ChordWebEngine {
        guard !isPrivate, id != Space.defaultProfile else { return engine }
        if let known = profileEngines[id] { return known }
        let other = engine.engine?(forProfile: id) ?? engine
        other.setDelegate?(self)
        profileEngines[id] = other
        return other
    }

    /// The engine for pages shown in a Space: its profile's.
    public func engine(for space: Space) -> ChordWebEngine {
        engine(forProfile: space.profileID)
    }

    /// The Space a page an engine opened by itself goes to, when no tab opened it: the
    /// active Space if it is on the engine's profile, else the first one that is.
    func space(for engine: ChordWebEngine) -> Space {
        let profile = isPrivate || engine === self.engine
            ? Space.defaultProfile
            : profileEngines.first { $0.value === engine }?.key
        if activeSpace.profileID == profile { return activeSpace }
        return spaces.first { $0.profileID == profile } ?? activeSpace
    }

    /// The tab's page, created and loaded on first use, woken up when it sleeps.
    @discardableResult
    func page(for tab: Tab) -> ChordWebPage {
        if let page = tab.page {
            if page.isAsleep == true {
                page.wake?()
                // Asleep with nothing to load again: back to the tab's address.
                if page.url == nil, let url = tab.url { page.load(url) }
            }
            return page
        }
        let page = engine(forProfile: profileID(of: tab)).makePage()
        page.delegate = self
        tab.page = page
        if let url = tab.url { page.load(url) }
        return page
    }

    /// Keeps the visible tabs and the most recently used ones awake; the rest sleep,
    /// except those playing sound or using the camera, the microphone or the screen (a
    /// call, music). A sleeping page keeps its history, scroll position and forms.
    func enforceSleepPolicy() {
        let awake = everyTab
            .filter(\.isAwake)
            .sorted { $0.lastSelected > $1.lastSelected }
        var keep = Set(awake.prefix(maxAwakeTabs).map(\.id))
        for visible in visibleTabs { keep.insert(visible.id) }
        // What the other windows show stays awake too.
        for window in windows where window !== loaded {
            for visible in withWindow(window, { visibleTabs }) { keep.insert(visible.id) }
        }
        for tab in awake where !keep.contains(tab.id) {
            guard let page = tab.page, page.isAudible != true, page.isCapturingMedia != true else { continue }
            if let sleep = page.sleep {
                // A page the engine cannot put to sleep (in picture in picture) stays awake.
                _ = sleep()
            } else {
                tab.page = nil
            }
        }
    }

    /// The tab the sidebar's media controls show, like Arc's mini player: the most
    /// recently used tab playing sound or video (or paused from the controls) that is
    /// not on screen.
    public var mediaTab: Tab? {
        let visible = Set(visibleTabs.map(\.id))
        return everyTab
            .filter { !visible.contains($0.id) && $0.page?.hasMedia == true }
            .max { $0.lastSelected < $1.lastSelected }
    }

    /// Pauses the tab's media, or plays it again.
    public func toggleMediaPlayback(_ tab: Tab) {
        tab.page?.toggleMediaPlayback?()
        changes.send(.tab(tab.id))
    }

    /// Mutes the tab's page, or gives it its sound back.
    public func toggleMute(_ tab: Tab) {
        guard let page = tab.page else { return }
        page.setMuted?(!(page.isMuted ?? false))
        changes.send(.tab(tab.id))
    }

    func tab(owning page: ChordWebPage) -> Tab? {
        everyTab.first { $0.page === page }
    }

    // MARK: - Session

    func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    public func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        store?.save(SessionSnapshot(spaces: spaces.map(\.snapshot), activeSpaceID: activeSpaceID,
                                    profileFavorites: favoritesByProfile.mapValues { $0.map(\.snapshot) },
                                    profileAddressBarOnTop: addressBarOnTopByProfile.isEmpty ? nil : addressBarOnTopByProfile,
                                    archive: archive.isEmpty ? nil : archive.map { ArchivedTabSnapshot(tab: $0.snapshot, spaceID: $0.spaceID, date: $0.date) }))
    }

    /// Adds Spaces and favorites made elsewhere (the Arc import). A Space with the same
    /// name as an existing one replaces it in place, so that importing again updates
    /// rather than duplicates. A first launch with nothing open loses its default Spaces.
    func add(spaces imported: [Space], favorites importedFavorites: [String: [Tab]]) {
        guard !imported.isEmpty || !importedFavorites.isEmpty else { return }
        let used = Set(spaces.map(\.profileID))
        if isPristine, !imported.isEmpty {
            spaces = imported
        } else {
            for space in imported {
                if let index = spaces.firstIndex(where: { $0.name == space.name }) {
                    for tab in spaces[index].allTabs { tab.page = nil }
                    spaces[index] = space
                } else {
                    spaces.append(space)
                }
            }
        }
        for (profile, tabs) in importedFavorites {
            for tab in favoritesByProfile[profile] ?? [] { tab.page = nil }
            favoritesByProfile[profile] = tabs
        }
        dropUnusedProfiles(previouslyUsed: used)
        if !spaces.contains(where: { $0.id == activeSpaceID }) { activeSpaceID = imported.first?.id ?? spaces[0].id }
        changes.send(.spaces)
        changes.send(.activeSpace)
        saveNow()
    }
}


extension BrowserState: ChordWebPageDelegate {
    public func pageDidUpdate(_ page: ChordWebPage) {
        PageHostView.pageDidUpdate(page)
        guard let tab = tab(owning: page) else { return }
        if let url = page.url { tab.url = url }
        if let title = page.title, !title.isEmpty {
            tab.title = title
            // The pinned page's own title, once it has loaded, rather than its host.
            if tab.pinnedURL != nil, tab.url == tab.pinnedURL { tab.pinnedTitle = title }
        }
        // The live page knows its real icon: keep it for when the tab sleeps.
        if let icon = page.faviconData ?? nil, let url = tab.url {
            FaviconStore.shared.useIcon(icon, for: url)
        }
        changes.send(.tab(tab.id))
        scheduleSave()
    }

    public func page(_ page: ChordWebPage, didFindMatches count: Int, activeMatch: Int, isFinal: Bool) {
        changes.send(.findResult(FindResult(page: page, count: count, activeMatch: activeMatch)))
    }

    public func page(_ page: ChordWebPage, wantsNewTabWith url: URL) {
        openTab(url: url, in: space(opening: page))
    }

    /// The Space of the tab showing `page`, for the tabs it opens.
    func space(opening page: ChordWebPage) -> Space? {
        tab(owning: page).flatMap { owningSpace(of: $0) }
    }

    /// ⇧-click opens a Peek, ⌘-click a background tab. Like Arc, a link that leaves the
    /// site of a favorite or pinned tab opens in a Peek, so the tab stays where it was.
    public func page(_ page: ChordWebPage, shouldFollowLinkTo url: URL, modifiers: NSEvent.ModifierFlags) -> Bool {
        if modifiers.contains(.shift) {
            changes.send(.peek(url))
            return false
        }
        if modifiers.contains(.command) {
            openTab(url: url, select: false, in: space(opening: page))
            return false
        }
        if let tab = tab(owning: page), tab.section != .today,
           let from = tab.url?.host, let to = url.host, Self.site(of: from) != Self.site(of: to) {
            changes.send(.peek(url))
            return false
        }
        return true
    }

    public func page(_ page: ChordWebPage, didStartDownload id: String, destination: URL) {
        downloads.start(id: id, destination: destination)
        changes.send(.downloadStarted)
        // A new tab opened only for this file has nothing to show: close it, like Arc.
        if let tab = tab(owning: page), tab.section == .today, !page.canGoBack, (page.title ?? "").isEmpty {
            downloadingPages[id] = page
            close(tab)
        }
    }

    public func page(_ page: ChordWebPage, download id: String, didProgress fraction: Double) {
        downloads.progress(id: id, fraction: fraction)
    }

    public func page(_ page: ChordWebPage, download id: String, didFinishAt fileURL: URL?) {
        downloads.finish(id: id, fileURL: fileURL)
        downloadingPages[id] = nil
    }

    public func page(_ page: ChordWebPage, download id: String, needsApproval warning: String) {
        downloads.needsApproval(id: id, warning: warning)
        changes.send(.downloadStarted)
    }

    /// Stops a running download.
    public func cancelDownload(_ id: String) {
        engine.cancelDownload?(id)
    }

    /// Saves a download the engine held back, as the user chose.
    public func keepDownload(_ id: String) {
        engine.keepDownload?(id)
        downloads.approve(id: id)
    }

    /// The last two labels of a host, close enough to a registrable domain here.
    static func site(of host: String) -> String {
        host.split(separator: ".").suffix(2).joined(separator: ".")
    }
}

extension BrowserState: ChordWebEngineDelegate {
    /// A page the engine opened by itself goes to the top of today's tabs, in the Space
    /// of the page that opened it.
    public func engine(_ engine: ChordWebEngine, didOpen page: ChordWebPage, opener: ChordWebPage?, inBackground: Bool) {
        guard tab(owning: page) == nil else { return }
        let space = opener.flatMap { self.space(opening: $0) } ?? self.space(for: engine)
        openTab(url: page.url ?? URL(string: "about:blank")!, select: !inBackground, adopting: page, in: space)
    }

    public func engine(_ engine: ChordWebEngine, didClose page: ChordWebPage) {
        if let tab = tab(owning: page) { close(tab) }
    }

    public func engine(_ engine: ChordWebEngine, wantsToShow page: ChordWebPage) {
        if let tab = tab(owning: page) { select(tab) }
    }

    public func engineExtensionsDidChange(_ engine: ChordWebEngine) {
        changes.send(.extensions)
    }

    public func engine(_ engine: ChordWebEngine, page: ChordWebPage, requests request: ChordPermissionRequest) {
        changes.send(.permission(PermissionAsk(page: page, request: request)))
    }
}
