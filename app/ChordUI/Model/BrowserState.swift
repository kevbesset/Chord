import AppKit
import Combine

public enum StateChange: Equatable {
    /// Spaces were added, removed, renamed, recoloured or moved to another profile.
    case spaces
    /// Another Space is now active.
    case activeSpace
    /// Tabs or folders were added, removed, moved or pinned, or the favorites changed.
    case tabs
    /// The selected tab of the active Space changed, or the split around it.
    case selection
    /// A tab's URL, title, icon or navigation state changed.
    case tab(UUID)
    /// A page asked for a link to open in a Peek.
    case peek(URL)
    /// A download started.
    case downloadStarted
}

/// Where a tab goes in the sidebar.
public enum TabDestination {
    case favorites(Int)
    /// In a folder of pinned tabs, or at the top level for nil.
    case pinned(Folder?, Int)
    case today(Int)
}

/// What one browser window shows: its Space, and in each Space its selected tab and
/// split. Windows share the Spaces and their tabs, like Arc's; each picks its own.
public final class WindowSelection {
    fileprivate var activeSpaceID: UUID
    fileprivate var selectedTabIDs: [UUID: UUID] = [:]
    fileprivate var splits: [UUID: [UUID]] = [:]

    fileprivate init(activeSpaceID: UUID) {
        self.activeSpaceID = activeSpaceID
    }
}

/// Spaces, favorites, tabs and selection. The single source of truth for ChordUI.
///
/// The selection read and changed through `activeSpaceID`, `Space.selectedTabID` and
/// `Space.split` is the loaded window's (see `withWindow(_:_:)`): the window the user
/// acts in, or the one being drawn.
public final class BrowserState: NSObject {
    public let engine: ChordWebEngine
    /// A private browsing window's state: one Space, nothing saved.
    public let isPrivate: Bool
    public let changes = PassthroughSubject<StateChange, Never>()
    public private(set) var spaces: [Space] = []
    public private(set) var activeSpaceID: UUID
    /// This session's downloads and the Downloads folder's recent files.
    public let downloads = Downloads()

    /// Favorites by profile. Like Arc, Spaces that share a profile share favorites.
    private var favoritesByProfile: [String: [Tab]] = [:]
    /// How many pages stay alive besides the visible ones. Older tabs go to sleep.
    var maxAwakeTabs = 8
    /// Pages of tabs closed while their download runs: kept alive until it ends, since
    /// an engine may stop a download whose page goes away.
    private var downloadingPages: [String: ChordWebPage] = [:]
    /// Most recent last, for ⇧⌘T.
    private var closedTabs: [(snapshot: TabSnapshot, spaceID: UUID)] = []

    private let store: SessionStore?
    private var pendingSave: DispatchWorkItem?

    /// The selection of each open window; `loaded` is the one the Spaces hold now.
    private var windows: [WindowSelection] = []
    private var loaded: WindowSelection?

    public init(engine: ChordWebEngine, store: SessionStore?, isPrivate: Bool = false) {
        self.engine = engine
        self.store = store
        self.isPrivate = isPrivate
        if isPrivate {
            let space = Space(name: "Navigation privée", colorHex: Theme.privateSpaceColor)
            spaces = [space]
            activeSpaceID = space.id
        } else if let snapshot = store?.load(), !snapshot.spaces.isEmpty {
            let restored = snapshot.spaces.map(Space.init(snapshot:))
            spaces = restored
            activeSpaceID = restored.contains { $0.id == snapshot.activeSpaceID } ? snapshot.activeSpaceID : restored[0].id
            if let byProfile = snapshot.profileFavorites {
                favoritesByProfile = byProfile.mapValues { $0.map { Tab(snapshot: $0, section: .favorites) } }
            } else if let shared = snapshot.favorites {
                favoritesByProfile[Space.defaultProfile] = shared.map { Tab(snapshot: $0, section: .favorites) }
            }
        } else {
            let first = Space(name: "Chord", colorHex: Theme.spacePalette[0])
            spaces = [first, Space(name: "Perso", colorHex: Theme.spacePalette[1])]
            activeSpaceID = first.id
        }
        super.init()
        engine.setDelegate?(self)
    }

    // MARK: - Windows

    /// A new window's selection: the Space of the window it opens from, no tab yet
    /// (it shows the home page). The first window takes the restored selection.
    public func openWindow() -> WindowSelection {
        let window = WindowSelection(activeSpaceID: activeSpaceID)
        if loaded == nil {
            loaded = window
        }
        windows.append(window)
        return window
    }

    public func closeWindow(_ window: WindowSelection) {
        if loaded === window, let other = windows.first(where: { $0 !== window }) {
            load(other)
        }
        windows.removeAll { $0 === window }
        if windows.isEmpty { loaded = nil }
    }

    /// The window the user acts in: its selection stays loaded.
    public func activate(_ window: WindowSelection) {
        load(window)
    }

    /// Runs `body` with `window`'s selection loaded, then brings the previous one back.
    /// Each window draws itself this way when the state changes.
    public func withWindow<T>(_ window: WindowSelection, _ body: () -> T) -> T {
        guard let previous = loaded, previous !== window, windows.contains(where: { $0 === window }) else { return body() }
        load(window)
        defer { load(previous) }
        return body()
    }

    /// Puts the loaded window's selection away and brings `window`'s into the Spaces.
    private func load(_ window: WindowSelection) {
        guard let current = loaded, current !== window else { return }
        current.activeSpaceID = activeSpaceID
        for space in spaces {
            current.selectedTabIDs[space.id] = space.selectedTabID
            current.splits[space.id] = space.split
        }
        activeSpaceID = spaces.contains { $0.id == window.activeSpaceID } ? window.activeSpaceID : spaces[0].id
        for space in spaces {
            space.selectedTabID = window.selectedTabIDs[space.id]
            space.split = window.splits[space.id] ?? []
        }
        loaded = window
    }

    // MARK: - Reading

    public var activeSpace: Space {
        spaces.first { $0.id == activeSpaceID } ?? spaces[0]
    }

    /// The active Space's favorites.
    public var favorites: [Tab] {
        favorites(of: activeSpace)
    }

    func favorites(of space: Space) -> [Tab] {
        favoritesByProfile[space.profileID] ?? []
    }

    public var selectedTab: Tab? {
        selectedTab(in: activeSpace)
    }

    func selectedTab(in space: Space) -> Tab? {
        guard let id = space.selectedTabID else { return nil }
        return tab(withID: id, in: space)
    }

    /// A tab the Space shows: its own, or a favorite of its profile.
    private func tab(withID id: UUID, in space: Space) -> Tab? {
        favorites(of: space).first { $0.id == id } ?? space.allTabs.first { $0.id == id }
    }

    /// The tabs on screen: the split around the selected tab, or the selected tab alone.
    public var visibleTabs: [Tab] {
        let space = activeSpace
        guard let selected = selectedTab(in: space) else { return [] }
        if space.split.contains(selected.id) {
            let panes = space.split.compactMap { tab(withID: $0, in: space) }
            if panes.count >= 2 { return panes }
        }
        return [selected]
    }

    /// Whether the selected tab is shown in a split.
    public var isSplit: Bool { visibleTabs.count > 1 }

    /// Favorites, pinned, then today: the order of the sidebar.
    func sidebarTabs(in space: Space) -> [Tab] {
        favorites(of: space) + space.allTabs
    }

    /// Every tab, active Space first with its favorites.
    var allTabs: [(tab: Tab, space: Space)] {
        let active = activeSpace
        let ordered = [active] + spaces.filter { $0 !== active }
        return ordered.flatMap { space -> [(tab: Tab, space: Space)] in
            let favorites = space === active || space.profileID != active.profileID ? favorites(of: space) : []
            return (favorites + space.allTabs).map { (tab: $0, space: space) }
        }
    }

    private var everyTab: [Tab] {
        favoritesByProfile.values.flatMap { $0 } + spaces.flatMap(\.allTabs)
    }

    func tab(withID id: UUID) -> Tab? {
        everyTab.first { $0.id == id }
    }

    func space(containing tab: Tab) -> Space? {
        spaces.first { $0.contains(tab) }
    }

    private func profile(ofFavorite tab: Tab) -> String? {
        favoritesByProfile.first { $0.value.contains { $0 === tab } }?.key
    }

    /// The Space that shows a tab: its own Space, or for a favorite the active Space when
    /// it shares the profile, else the first Space that does.
    private func owningSpace(of tab: Tab) -> Space? {
        if let space = space(containing: tab) { return space }
        guard let profile = profile(ofFavorite: tab) else { return nil }
        if activeSpace.profileID == profile { return activeSpace }
        return spaces.first { $0.profileID == profile }
    }

    /// True on first launch, before anything was opened or imported.
    public var isPristine: Bool {
        favoritesByProfile.values.allSatisfy(\.isEmpty) && spaces.allSatisfy { $0.allTabs.isEmpty }
    }

    // MARK: - Tabs

    /// Opens a tab at the top of today's tabs, in the active Space or in `space`. `page`,
    /// when given, is adopted as it is (from a Peek or a little window) instead of
    /// loading the URL again.
    @discardableResult
    public func openTab(url: URL, select: Bool = true, adopting page: ChordWebPage? = nil, in space: Space? = nil) -> Tab {
        let tab = Tab(url: page?.url ?? url, title: page?.title ?? url.host ?? "")
        if let page {
            page.delegate = self
            tab.page = page
        }
        (space ?? activeSpace).today.insert(tab, at: 0)
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

        // Like Arc, favorites and pinned tabs are never removed: they go back to sleep.
        tab.page = nil
        if tab.section == .today {
            space.today.removeAll { $0 === tab }
            closedTabs.append((tab.snapshot, space.id))
            if closedTabs.count > 50 { closedTabs.removeFirst() }
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
                    .filter { $0 !== tab && $0.page != nil }
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

        if let sourceProfile { favoritesByProfile[sourceProfile]?.removeAll { $0 === tab } }
        source?.removePinned(tab)
        source?.today.removeAll { $0 === tab }
        insert(tab, at: destination, in: space)

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

    private func insert(_ tab: Tab, at destination: TabDestination, in space: Space) {
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
        let folder = Folder(name: "Nouveau dossier")
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

    private func removeFromSplits(_ tab: Tab) {
        for space in spaces where space.split.contains(tab.id) {
            space.split.removeAll { $0 == tab.id }
            if space.split.count < 2 { space.split = [] }
        }
    }

    // MARK: - Spaces

    public func selectSpace(_ space: Space) {
        guard space.id != activeSpaceID else { return }
        activeSpaceID = space.id
        if let tab = selectedTab(in: space) {
            tab.lastSelected = Date()
        }
        for visible in visibleTabs { page(for: visible) }
        enforceSleepPolicy()
        changes.send(.activeSpace)
        scheduleSave()
    }

    public func selectSpace(offset: Int) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        let next = ((index + offset) % spaces.count + spaces.count) % spaces.count
        selectSpace(spaces[next])
    }

    /// ⌃1…⌃9, like Arc.
    public func selectSpace(number: Int) {
        guard number >= 1, number <= spaces.count else { return }
        selectSpace(spaces[number - 1])
    }

    /// A new Space shares the active Space's profile, and so its favorites.
    @discardableResult
    public func addSpace(name: String? = nil, colorHex: String? = nil) -> Space {
        let color = colorHex ?? Theme.spacePalette[spaces.count % Theme.spacePalette.count]
        let space = Space(name: name ?? "Space \(spaces.count + 1)", colorHex: color, profileID: activeSpace.profileID)
        spaces.append(space)
        changes.send(.spaces)
        selectSpace(space)
        return space
    }

    public func rename(_ space: Space, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != space.name else { return }
        space.name = trimmed
        changes.send(.spaces)
        scheduleSave()
    }

    public func setColor(_ space: Space, hex: String) {
        guard hex != space.colorHex else { return }
        space.colorHex = hex
        changes.send(.spaces)
        scheduleSave()
    }

    /// The profiles in use, each with the Spaces that share it, in Space order.
    public var profiles: [(id: String, spaces: [Space])] {
        var order: [String] = []
        for space in spaces where !order.contains(space.profileID) { order.append(space.profileID) }
        return order.map { id in (id, spaces.filter { $0.profileID == id }) }
    }

    /// Moves a Space to another profile: it then shows that profile's favorites.
    /// A new id gives the Space favorites of its own.
    public func setProfile(_ space: Space, to profileID: String) {
        guard space.profileID != profileID else { return }
        space.profileID = profileID
        dropUnusedFavorites()
        changes.send(.spaces)
        changes.send(.tabs)
        if space.id == activeSpaceID { changes.send(.selection) }
        scheduleSave()
    }

    /// Deletes a Space and its tabs. The last Space cannot be deleted.
    public func delete(_ space: Space) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0 === space }) else { return }
        for tab in space.allTabs { tab.page = nil }
        let wasActive = space.id == activeSpaceID
        spaces.remove(at: index)
        dropUnusedFavorites()
        if wasActive {
            activeSpaceID = spaces[max(0, index - 1)].id
            for visible in visibleTabs { page(for: visible) }
            changes.send(.activeSpace)
        }
        changes.send(.spaces)
        scheduleSave()
    }

    /// Favorites of a profile no Space uses any more.
    private func dropUnusedFavorites() {
        let used = Set(spaces.map(\.profileID))
        for (profile, tabs) in favoritesByProfile where !used.contains(profile) {
            for tab in tabs { tab.page = nil }
            favoritesByProfile[profile] = nil
        }
    }

    // MARK: - Pages

    /// The tab's page, created and loaded on first use.
    @discardableResult
    func page(for tab: Tab) -> ChordWebPage {
        if let page = tab.page { return page }
        let page = engine.makePage()
        page.delegate = self
        tab.page = page
        if let url = tab.url { page.load(url) }
        return page
    }

    /// Keeps the visible tabs and the most recently used ones awake; the rest sleep.
    func enforceSleepPolicy() {
        let awake = everyTab
            .filter { $0.page != nil }
            .sorted { $0.lastSelected > $1.lastSelected }
        var keep = Set(awake.prefix(maxAwakeTabs).map(\.id))
        for visible in visibleTabs { keep.insert(visible.id) }
        // What the other windows show stays awake too.
        for window in windows where window !== loaded {
            for visible in withWindow(window, { visibleTabs }) { keep.insert(visible.id) }
        }
        for tab in awake where !keep.contains(tab.id) {
            tab.page = nil
        }
    }

    private func tab(owning page: ChordWebPage) -> Tab? {
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
                                    profileFavorites: favoritesByProfile.mapValues { $0.map(\.snapshot) }))
    }

    /// Adds Spaces and favorites made elsewhere (the Arc import). A Space with the same
    /// name as an existing one replaces it in place, so that importing again updates
    /// rather than duplicates. A first launch with nothing open loses its default Spaces.
    func add(spaces imported: [Space], favorites importedFavorites: [String: [Tab]]) {
        guard !imported.isEmpty || !importedFavorites.isEmpty else { return }
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
        dropUnusedFavorites()
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
        if let title = page.title, !title.isEmpty { tab.title = title }
        // The live page knows its real icon: keep it for when the tab sleeps.
        if let iconURL = page.faviconURL ?? nil, let url = tab.url {
            let id = tab.id
            FaviconStore.shared.useIcon(at: iconURL, for: url) { [weak self] in self?.changes.send(.tab(id)) }
        }
        changes.send(.tab(tab.id))
        scheduleSave()
    }

    public func page(_ page: ChordWebPage, wantsNewTabWith url: URL) {
        openTab(url: url)
    }

    /// ⇧-click opens a Peek, ⌘-click a background tab. Like Arc, a link that leaves the
    /// site of a favorite or pinned tab opens in a Peek, so the tab stays where it was.
    public func page(_ page: ChordWebPage, shouldFollowLinkTo url: URL, modifiers: NSEvent.ModifierFlags) -> Bool {
        if modifiers.contains(.shift) {
            changes.send(.peek(url))
            return false
        }
        if modifiers.contains(.command) {
            openTab(url: url, select: false)
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

    /// Stops a running download.
    public func cancelDownload(_ id: String) {
        engine.cancelDownload?(id)
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
        let space = opener.flatMap { tab(owning: $0) }.flatMap { owningSpace(of: $0) }
        openTab(url: page.url ?? URL(string: "about:blank")!, select: !inBackground, adopting: page, in: space)
    }

    public func engine(_ engine: ChordWebEngine, didClose page: ChordWebPage) {
        if let tab = tab(owning: page) { close(tab) }
    }

    public func engine(_ engine: ChordWebEngine, wantsToShow page: ChordWebPage) {
        if let tab = tab(owning: page) { select(tab) }
    }
}
