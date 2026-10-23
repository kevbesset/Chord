import Foundation

/// Where a tab lives in the sidebar, top to bottom.
public enum TabSection: Equatable {
    /// The tile grid at the top of the sidebar, shared by every Space.
    case favorites
    case pinned
    case today
}

/// A tab inside a Space, or a favorite. Its page exists only while the tab is awake.
public final class Tab {
    public let id: UUID
    public internal(set) var url: URL?
    public internal(set) var title: String
    public internal(set) var section: TabSection
    /// The live page, or nil when the tab is asleep.
    var page: ChordWebPage?
    /// Used to decide which tabs go to sleep first.
    var lastSelected: Date

    init(id: UUID = UUID(), url: URL?, title: String = "", section: TabSection = .today, lastSelected: Date = .distantPast) {
        self.id = id
        self.url = url
        self.title = title
        self.section = section
        self.lastSelected = lastSelected
    }

    public var isPinned: Bool { section == .pinned }
    public var isFavorite: Bool { section == .favorites }

    public var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = url?.host, !host.isEmpty { return host }
        return url?.absoluteString ?? "Nouvel onglet"
    }
}
