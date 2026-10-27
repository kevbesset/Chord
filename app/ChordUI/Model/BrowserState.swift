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
    /// A page's site asks for permissions: the window showing the page asks the user.
    case permission(PermissionAsk)
    /// What a search in a page found (⌘F).
    case findResult(FindResult)
    /// Extensions were added, removed or pinned, or a badge or icon changed.
    case extensions
    /// A profile's address bar moved between the sidebar and the top of the page.
    case addressBar
    /// Tabs went to the archive, or came back from it.
    case archive
}

/// A tab of the archive: closed with ⌘W, or archived after a while unused, like Arc's.
/// Restoring it opens it again in its Space.
public struct ArchivedTab {
    public let id: UUID
    public let url: URL?
    public let title: String
    public let spaceID: UUID
    public let date: Date
    let snapshot: TabSnapshot

    init(snapshot: TabSnapshot, spaceID: UUID, date: Date) {
        id = snapshot.id
        url = snapshot.url
        title = snapshot.title
        self.spaceID = spaceID
        self.date = date
        self.snapshot = snapshot
    }

    public var displayTitle: String {
        if !title.isEmpty { return title }
        return url?.host ?? url?.absoluteString ?? String(localized: "New Tab", bundle: .chordUI)
    }
}

/// A site's question, with the page it comes from.
public struct PermissionAsk: Equatable {
    public let page: ChordWebPage
    public let request: ChordPermissionRequest

    public static func == (lhs: PermissionAsk, rhs: PermissionAsk) -> Bool {
        lhs.page === rhs.page && lhs.request === rhs.request
    }
}

/// What a search in a page found: `count` matches, the `activeMatch`th selected.
public struct FindResult: Equatable {
    public let page: ChordWebPage
    public let count: Int
    public let activeMatch: Int

    public static func == (lhs: FindResult, rhs: FindResult) -> Bool {
        lhs.page === rhs.page && lhs.count == rhs.count && lhs.activeMatch == rhs.activeMatch
    }
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
    var activeSpaceID: UUID
    var selectedTabIDs: [UUID: UUID] = [:]
    var splits: [UUID: [UUID]] = [:]

    init(activeSpaceID: UUID) {
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
    public internal(set) var spaces: [Space] = []
    public internal(set) var activeSpaceID: UUID
    /// This session's downloads and the Downloads folder's recent files.
    public let downloads = Downloads()

    /// Favorites by profile. Like Arc, Spaces that share a profile share favorites.
    var favoritesByProfile: [String: [Tab]] = [:]
    /// Where each profile's address bar sits: on top of the page or in the sidebar. A
    /// profile missing here follows the default of the settings.
    var addressBarOnTopByProfile: [String: Bool] = [:]
    /// The engines of the profiles other than the default one, made on first use.
    var profileEngines: [String: ChordWebEngine] = [:]
    /// How many pages stay alive besides the visible ones. Older tabs go to sleep.
    var maxAwakeTabs = 8
    /// Pages of tabs closed while their download runs: kept alive until it ends, since
    /// an engine may stop a download whose page goes away.
    var downloadingPages: [String: ChordWebPage] = [:]
    /// Most recent last, for ⇧⌘T.
    var closedTabs: [(snapshot: TabSnapshot, spaceID: UUID)] = []
    /// Archived tabs, newest first: kept 30 days, at most `archiveLimit`.
    public internal(set) var archive: [ArchivedTab] = []
    static let archiveLimit = 500
    static let archiveKept: TimeInterval = 30 * 24 * 3600
    var archiveTimer: Timer?

    let store: SessionStore?
    var pendingSave: DispatchWorkItem?

    /// The selection of each open window; `loaded` is the one the Spaces hold now.
    var windows: [WindowSelection] = []
    var loaded: WindowSelection?

    public init(engine: ChordWebEngine, store: SessionStore?, isPrivate: Bool = false) {
        self.engine = engine
        self.store = store
        self.isPrivate = isPrivate
        var fromVersion = SessionSnapshot.currentVersion
        var readSession = false
        if isPrivate {
            let space = Space(name: String(localized: "Private Browsing", bundle: .chordUI), colorHex: Theme.privateSpaceColor)
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
            addressBarOnTopByProfile = snapshot.profileAddressBarOnTop ?? [:]
            archive = (snapshot.archive ?? []).map { ArchivedTab(snapshot: $0.tab, spaceID: $0.spaceID, date: $0.date) }
            fromVersion = snapshot.version
            readSession = true
        } else {
            let first = Space(name: "Chord", colorHex: Theme.spacePalette[0])
            spaces = [first, Space(name: String(localized: "Personal", bundle: .chordUI), colorHex: Theme.spacePalette[1], profileID: UUID().uuidString)]
            activeSpaceID = first.id
        }
        super.init()
        engine.setDelegate?(self)
        if fromVersion < 4 { separateSessions() }
        // Profiles left behind (a Space deleted while Chord did not quit properly) go,
        // judged against a session actually read: never against a fresh one.
        if readSession { engine.deleteProfiles?(except: Array(Set(spaces.map(\.profileID)))) }
        if !isPrivate { startArchiving() }
    }

    /// Before version 4 a profile only grouped favorites, and every Space shared one
    /// session. Arc's default profile, imported as "arc:Default", becomes Chord's
    /// default one; the Spaces left on the default profile by default (the first
    /// launch's "Personal", Spaces added since) get a profile, and so a session, of their own.
    func separateSessions() {
        let arcDefault = "arc:Default"
        if !spaces.contains(where: { $0.profileID == Space.defaultProfile }) {
            for space in spaces where space.profileID == arcDefault { space.profileID = Space.defaultProfile }
            if let favorites = favoritesByProfile.removeValue(forKey: arcDefault) {
                favoritesByProfile[Space.defaultProfile] = favorites
            }
        }
        for space in spaces.filter({ $0.profileID == Space.defaultProfile }).dropFirst() {
            space.profileID = UUID().uuidString
        }
        scheduleSave()
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
    func load(_ window: WindowSelection) {
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
    func tab(withID id: UUID, in space: Space) -> Tab? {
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

    var everyTab: [Tab] {
        favoritesByProfile.values.flatMap { $0 } + spaces.flatMap(\.allTabs)
    }

    func tab(withID id: UUID) -> Tab? {
        everyTab.first { $0.id == id }
    }

    func space(containing tab: Tab) -> Space? {
        spaces.first { $0.contains(tab) }
    }

    func profile(ofFavorite tab: Tab) -> String? {
        favoritesByProfile.first { $0.value.contains { $0 === tab } }?.key
    }

    /// The profile whose session a tab's page runs in.
    func profileID(of tab: Tab) -> String {
        profile(ofFavorite: tab) ?? space(containing: tab)?.profileID ?? activeSpace.profileID
    }

    /// The Space that shows a tab: its own Space, or for a favorite the active Space when
    /// it shares the profile, else the first Space that does.
    func owningSpace(of tab: Tab) -> Space? {
        if let space = space(containing: tab) { return space }
        guard let profile = profile(ofFavorite: tab) else { return nil }
        if activeSpace.profileID == profile { return activeSpace }
        return spaces.first { $0.profileID == profile }
    }

    /// True on first launch, before anything was opened or imported.
    public var isPristine: Bool {
        favoritesByProfile.values.allSatisfy(\.isEmpty) && spaces.allSatisfy { $0.allTabs.isEmpty }
    }

}
