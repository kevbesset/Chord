import AppKit
import Combine

// Opening, closing, moving and selecting tabs; folders; split view.
extension BrowserState {
    // MARK: - Tabs

    /// Opens a tab at the top of today's tabs, in the active Space or in `space`. `page`,
    /// when given, is adopted as it is (from a Peek or a little window) instead of
    /// loading the URL again.
    @discardableResult
    public func openTab(url: URL, select: Bool = true, adopting page: ChordWebPage? = nil, in space: Space? = nil) -> Tab {
        let space = space ?? activeSpace
        // Opening a tab counts as using it: it does not go to sleep before the older ones.
        let tab = Tab(url: page?.url ?? url, title: page?.title ?? url.host ?? "", lastSelected: Date())
        // A page of another profile's session loads again in the Space's own.
        if let page, engine(for: space).ownsPage?(page) ?? true {
            page.delegate = self
            tab.page = page
        }
        space.today.insert(tab, at: 0)
        changes.send(.tabs)
        if select { self.select(tab) }
        scheduleSave()
        return tab
    }

    /// Adds a tab without selecting it, where a dragged link was dropped.
    @discardableResult
    public func insertTab(url: URL, at destination: TabDestination) -> Tab {
        let tab = Tab(url: url, title: url.host ?? "")
        insert(tab, at: destination, in: activeSpace)
        changes.send(.tabs)
        scheduleSave()
        return tab
    }

    public func select(_ tab: Tab) {
        guard let space = owningSpace(of: tab) else { return }
        let switchesSpace = space.id != activeSpaceID
        activeSpaceID = space.id
        // Picking a tab outside the split leaves the split, which stays for later.
        space.selectedTabID = tab.id
        tab.lastSelected = Date()
        // A tab picked with ⌘1…9 or the command bar shows, even inside a closed folder.
        for folder in space.ancestors(of: tab) { folder.isExpanded = true }
        for visible in visibleTabs { page(for: visible) }
        enforceSleepPolicy()
        changes.send(switchesSpace ? .activeSpace : .selection)
        scheduleSave()
    }

    public func close(_ tab: Tab) {
        let space = owningSpace(of: tab) ?? activeSpace
        let wasSelected = space.selectedTabID == tab.id
        let wasVisible = visibleTabs.contains { $0 === tab }
        let splitPartners = space.split.filter { $0 != tab.id }

        // Like Arc, favorites and pinned tabs are never removed: they go back to sleep, on
        // the page they were pinned on.
        tab.page = nil
        tab.returnToPinnedURL()
        if tab.section == .today {
            space.today.removeAll { $0 === tab }
            closedTabs.append((tab.snapshot, space.id))
            if closedTabs.count > 50 { closedTabs.removeFirst() }
            addToArchive([(tab, space)])
        }
        removeFromSplits(tab)

        if wasSelected {
            // Back to the other pane of a split, else to the most recently used tab that is
            // still awake, like Arc. Sleeping tabs are not woken up: with none awake, the
            // Space shows Chord's home page.
            let next: Tab?
            if let partner = splitPartners.first.flatMap({ id in self.tab(withID: id) }), wasVisible {
                next = partner
            } else {
                next = sidebarTabs(in: space)
                    .filter { $0 !== tab && $0.isAwake }
                    .max { $0.lastSelected < $1.lastSelected }
            }
            space.selectedTabID = next?.id
            if let next, space.id == activeSpaceID {
                next.lastSelected = Date()
                for visible in visibleTabs { page(for: visible) }
            }
        }
        changes.send(.tabs)
        if wasSelected || wasVisible { changes.send(.selection) }
        scheduleSave()
    }

    /// ⇧⌘T: brings back the last tab closed with ⌘W.
    public func reopenClosedTab() {
        guard let closed = closedTabs.popLast() else { return }
        let space = spaces.first { $0.id == closed.spaceID } ?? activeSpace
        let tab = Tab(snapshot: closed.snapshot, section: .today)
        removeFromArchive(id: tab.id)
        space.today.insert(tab, at: 0)
        changes.send(.tabs)
        select(tab)
    }

    public var canReopenClosedTab: Bool { !closedTabs.isEmpty }

    /// Moves a tab to another section, folder, position or Space. The index is counted in
    /// the destination list as it was before the move, like a drop indicator.
    public func move(_ tab: Tab, to destination: TabDestination, in target: Space? = nil) {
        let source = space(containing: tab)
        let sourceProfile = profile(ofFavorite: tab)
        let space = target ?? source ?? activeSpace
        var destination = destination

        // Positions shift when a tab moves down inside its own list.
        switch destination {
        case .favorites(let index):
            if sourceProfile == space.profileID, let old = favorites(of: space).firstIndex(where: { $0 === tab }), old < index {
                destination = .favorites(index - 1)
            }
        case .pinned(let folder, let index):
            if source === space, tab.isPinned, space.parent(of: tab) === folder,
               let old = space.items(in: folder).firstIndex(where: { $0.object === tab }), old < index {
                destination = .pinned(folder, index - 1)
            }
        case .today(let index):
            if source === space, let old = space.today.firstIndex(where: { $0 === tab }), old < index {
                destination = .today(index - 1)
            }
        }

        let oldProfile = sourceProfile ?? source?.profileID
        if let sourceProfile { favoritesByProfile[sourceProfile]?.removeAll { $0 === tab } }
        source?.removePinned(tab)
        source?.today.removeAll { $0 === tab }
        insert(tab, at: destination, in: space)

        // Moved to another profile, the tab loads again in that profile's session.
        if oldProfile != space.profileID, tab.page != nil {
            tab.page = nil
            if visibleTabs.contains(where: { $0 === tab }) {
                for visible in visibleTabs { page(for: visible) }
                changes.send(.selection)
            }
        }

        // A tab sent to another Space leaves the selection and split of its old one.
        if let source, source !== space {
            source.split.removeAll { $0 == tab.id }
            if source.split.count < 2 { source.split = [] }
            if source.selectedTabID == tab.id {
                source.selectedTabID = (source.today.first ?? source.pinned.first)?.id
                if source.id == activeSpaceID { changes.send(.selection) }
            }
        }
        changes.send(.tabs)
        scheduleSave()
    }

    func insert(_ tab: Tab, at destination: TabDestination, in space: Space) {
        switch destination {
        case .favorites(let index):
            tab.section = .favorites
            var list = favorites(of: space)
            list.insert(tab, at: max(0, min(index, list.count)))
            favoritesByProfile[space.profileID] = list
        case .pinned(let folder, let index):
            tab.section = .pinned
            space.insertPinned(.tab(tab), in: folder, at: index)
        case .today(let index):
            tab.section = .today
            space.today.insert(tab, at: max(0, min(index, space.today.count)))
        }
    }

    /// ⌘D, like Arc: pins a tab, or sends a pinned one back to today's tabs.
    public func togglePin(_ tab: Tab) {
        let space = space(containing: tab) ?? activeSpace
        if tab.isPinned {
            move(tab, to: .today(0), in: space)
        } else {
            move(tab, to: .pinned(nil, space.pinnedItems.count), in: space)
        }
    }

    public func toggleFavorite(_ tab: Tab) {
        let space = owningSpace(of: tab) ?? activeSpace
        if tab.isFavorite {
            move(tab, to: .today(0), in: space)
        } else {
            move(tab, to: .favorites(favorites(of: space).count), in: space)
        }
    }

    /// Loads `url` in the selected tab, or in a new tab when nothing is selected.
    public func navigateSelected(to url: URL) {
        guard let tab = selectedTab else {
            openTab(url: url)
            return
        }
        tab.url = url
        page(for: tab).load(url)
        changes.send(.tab(tab.id))
        scheduleSave()
    }

    public func selectTab(offset: Int) {
        let space = activeSpace
        let tabs = sidebarTabs(in: space)
        guard !tabs.isEmpty else { return }
        let current = tabs.firstIndex { $0.id == space.selectedTabID } ?? -1
        let next = ((current + offset) % tabs.count + tabs.count) % tabs.count
        select(tabs[next])
    }

    /// ⌘1…⌘8 select that tab of the sidebar, favorites first, ⌘9 the last one.
    public func selectTab(number: Int) {
        let tabs = sidebarTabs(in: activeSpace)
        guard !tabs.isEmpty, number >= 1 else { return }
        let index = number == 9 ? tabs.count - 1 : number - 1
        guard index < tabs.count else { return }
        select(tabs[index])
    }


    // MARK: - Folders

    /// A new folder in the active Space's pinned tabs. With a tab, the folder takes the
    /// tab's place (pinning it first if needed) and holds it.
    @discardableResult
    public func newFolder(with tab: Tab? = nil) -> Folder {
        let space = tab.flatMap { self.space(containing: $0) } ?? activeSpace
        let folder = Folder(name: String(localized: "New Folder", bundle: .chordUI))
        if let tab, tab.isPinned, let place = space.removePinned(tab) {
            space.insertPinned(.folder(folder), in: place.parent, at: place.index)
            folder.items = [.tab(tab)]
        } else {
            space.insertPinned(.folder(folder), in: nil, at: space.pinnedItems.count)
            if let tab {
                space.today.removeAll { $0 === tab }
                if let profile = profile(ofFavorite: tab) { favoritesByProfile[profile]?.removeAll { $0 === tab } }
                tab.section = .pinned
                folder.items = [.tab(tab)]
            }
        }
        changes.send(.tabs)
        scheduleSave()
        return folder
    }

    /// Moves a folder, with everything in it, into another folder or the top level.
    public func move(_ folder: Folder, into parent: Folder?, at index: Int) {
        let space = activeSpace
        if let parent, space.folder(folder, contains: parent) { return }
        var index = index
        if space.parent(of: folder) === parent,
           let old = space.items(in: parent).firstIndex(where: { $0.object === folder }), old < index {
            index -= 1
        }
        guard space.removePinned(folder) != nil else { return }
        space.insertPinned(.folder(folder), in: parent, at: index)
        changes.send(.tabs)
        scheduleSave()
    }

    public func rename(_ folder: Folder, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folder.name else { return }
        folder.name = trimmed
        changes.send(.tabs)
        scheduleSave()
    }

    /// Remembers whether a folder is open. The outline view already shows it.
    public func setExpanded(_ folder: Folder, _ expanded: Bool) {
        guard folder.isExpanded != expanded else { return }
        folder.isExpanded = expanded
        scheduleSave()
    }

    /// Removes the folder but keeps its contents, in its place.
    public func ungroup(_ folder: Folder) {
        let space = activeSpace
        guard let place = space.removePinned(folder) else { return }
        for (offset, item) in folder.items.enumerated() {
            space.insertPinned(item, in: place.parent, at: place.index + offset)
        }
        changes.send(.tabs)
        scheduleSave()
    }

    /// Deletes the folder and the tabs in it.
    public func delete(_ folder: Folder) {
        let space = activeSpace
        let tabs = folder.tabs
        guard space.removePinned(folder) != nil else { return }
        for tab in tabs {
            tab.page = nil
            removeFromSplits(tab)
        }
        if let selected = space.selectedTabID, tabs.contains(where: { $0.id == selected }) {
            space.selectedTabID = (space.today.first ?? space.pinned.first)?.id
            changes.send(.selection)
        }
        changes.send(.tabs)
        scheduleSave()
    }

    // MARK: - Split view

    /// Shows `tab` beside the selected tab, up to four panes, and makes it active.
    public func addToSplit(_ tab: Tab) {
        let space = activeSpace
        guard let current = selectedTab(in: space), current !== tab,
              self.tab(withID: tab.id, in: space) != nil else { return }
        var panes = space.split.contains(current.id) ? space.split : [current.id]
        panes.removeAll { $0 == tab.id }
        guard panes.count < 4 else { return }
        panes.append(tab.id)
        space.split = panes
        select(tab)
    }

    /// Takes a tab out of the split. The tab itself stays in the sidebar.
    public func removeFromSplit(_ tab: Tab) {
        let space = activeSpace
        guard space.split.contains(tab.id) else { return }
        let remaining = space.split.filter { $0 != tab.id }
        space.split = remaining.count < 2 ? [] : remaining
        if space.selectedTabID == tab.id, let next = remaining.first.flatMap({ self.tab(withID: $0) }) {
            select(next)
        } else {
            changes.send(.selection)
            scheduleSave()
        }
    }

    public func unsplit() {
        guard !activeSpace.split.isEmpty else { return }
        activeSpace.split = []
        changes.send(.selection)
        scheduleSave()
    }

    func removeFromSplits(_ tab: Tab) {
        for space in spaces where space.split.contains(tab.id) {
            space.split.removeAll { $0 == tab.id }
            if space.split.count < 2 { space.split = [] }
        }
    }
}
