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
    public internal(set) var section: TabSection {
        didSet {
            guard section != oldValue else { return }
            if section == .today {
                pinnedURL = nil
                pinnedTitle = nil
            } else if oldValue == .today {
                pinnedURL = url
                pinnedTitle = title
            }
        }
    }
    /// For a pinned tab or a favorite, the page it was pinned on, like Arc's: browsing
    /// moves the tab away from it, closing the tab brings it back there.
    public internal(set) var pinnedURL: URL?
    var pinnedTitle: String?
    /// The tab's page: nil when the tab has not loaded since launch, or was put to sleep
    /// by an engine that cannot keep a sleeping page (see `isAwake`).
    var page: ChordWebPage?
    /// Used to decide which tabs go to sleep first.
    var lastSelected: Date

    init(id: UUID = UUID(), url: URL?, title: String = "", section: TabSection = .today, lastSelected: Date = .distantPast,
         pinnedURL: URL? = nil, pinnedTitle: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.section = section
        self.lastSelected = lastSelected
        if section != .today {
            self.pinnedURL = pinnedURL ?? url
            self.pinnedTitle = pinnedTitle ?? title
        }
    }

    /// The page is alive: loaded, and not asleep (put to sleep by Chord, or by the
    /// engine when memory runs short). A sleeping page keeps its history and where it
    /// was, and loads again when shown.
    var isAwake: Bool {
        guard let page else { return false }
        return !(page.isAsleep ?? false)
    }

    /// The address field says "Not Secure": Chromium's verdict while the page is awake
    /// (a certificate error the user went past, mixed content), else the address's
    /// scheme.
    var isNotSecure: Bool {
        guard let url else { return false }
        switch isAwake ? page?.securityState : nil {
        case "dangerous", "warning": return true
        case "secure": return false
        default: return url.isInsecure
        }
    }

    /// The page shares its screen, a window or a tab, or is the tab being shared.
    var isSharing: Bool {
        guard let page else { return false }
        return page.isSharingScreen == true || page.isBeingShared == true
    }

    public var isPinned: Bool { section == .pinned }
    public var isFavorite: Bool { section == .favorites }

    /// Back on the page it was pinned on, for a pinned tab or a favorite that browsed away.
    func returnToPinnedURL() {
        guard let pinnedURL else { return }
        url = pinnedURL
        if let pinnedTitle { title = pinnedTitle }
    }

    public var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = url?.host, !host.isEmpty { return host }
        return url?.absoluteString ?? String(localized: "New Tab", bundle: .chordUI)
    }
}
