import AppKit

/// A folder of pinned tabs, which may hold other folders, like Arc's.
public final class Folder {
    public let id: UUID
    public internal(set) var name: String
    var isExpanded: Bool
    var items: [PinnedItem]

    init(id: UUID = UUID(), name: String, isExpanded: Bool = true, items: [PinnedItem] = []) {
        self.id = id
        self.name = name
        self.isExpanded = isExpanded
        self.items = items
    }

    /// Every tab inside, depth first.
    var tabs: [Tab] { items.flatMap(\.tabs) }
}

/// One entry of a Space's pinned tabs: a tab, or a folder of them.
public enum PinnedItem {
    case tab(Tab)
    case folder(Folder)

    var tabs: [Tab] {
        switch self {
        case .tab(let tab): return [tab]
        case .folder(let folder): return folder.tabs
        }
    }

    /// The tab or folder itself, for identity checks and outline views.
    var object: AnyObject {
        switch self {
        case .tab(let tab): return tab
        case .folder(let folder): return folder
        }
    }
}

/// A context with its own colour, pinned tabs (in folders or not) and today's tabs.
public final class Space {
    public let id: UUID
    public internal(set) var name: String
    public internal(set) var colorHex: String
    /// An emoji standing for the Space, like Arc's Space icons: shown in place of its
    /// coloured dot. Nil for the dot alone.
    public internal(set) var icon: String?
    /// Like Arc, a Space belongs to a profile, and favorites and the session (cookies,
    /// storage, extensions) belong to the profile: Spaces sharing a profile share them.
    public internal(set) var profileID: String
    /// The pinned tabs as shown: folders included, top level first.
    var pinnedItems: [PinnedItem]
    /// Newest first, like Arc.
    var today: [Tab]
    /// May point at a favorite of the Space's profile.
    var selectedTabID: UUID?
    /// The tabs shown side by side (⌃⇧=), left to right. Empty, or two to four tabs.
    var split: [UUID]

    static let defaultProfile = "default"

    init(id: UUID = UUID(), name: String, colorHex: String, icon: String? = nil, profileID: String = Space.defaultProfile,
         pinnedItems: [PinnedItem] = [], today: [Tab] = [], selectedTabID: UUID? = nil, split: [UUID] = []) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.profileID = profileID
        self.pinnedItems = pinnedItems
        self.today = today
        self.selectedTabID = selectedTabID
        self.split = split
    }

    public var color: NSColor { NSColor(hex: colorHex) }

    /// A few icons to pick from at once; any emoji works.
    public static let suggestedIcons = ["🏠", "💼", "💻", "🧪", "🚀", "🎨", "📚", "🎵", "🎮", "✈️", "🌱", "⭐️"]

    /// The first character of `text` when it is an emoji (flags and skin tones
    /// included), else nil.
    static func icon(from text: String) -> String? {
        guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first,
              first.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x238C })
        else { return nil }
        return String(first)
    }

    /// The colour for accents (the mark's chord, selection, the active split pane). A
    /// neutral Space (grey, black or white, as Arc themes can be) has no accent of its
    /// own, so it gets Chord's indigo; its tint keeps its own colour.
    public var accent: NSColor {
        let color = self.color.usingColorSpace(.sRGB) ?? self.color
        return color.saturationComponent < 0.15 ? NSColor(hex: Theme.spacePalette[0]) : self.color
    }

    /// Every pinned tab, folders flattened, in sidebar order.
    var pinned: [Tab] { pinnedItems.flatMap(\.tabs) }

    var allTabs: [Tab] { pinned + today }

    func contains(_ tab: Tab) -> Bool {
        allTabs.contains { $0 === tab }
    }

    // MARK: - Pinned tree

    /// The items of a folder, or the top level for nil.
    func items(in folder: Folder?) -> [PinnedItem] {
        folder?.items ?? pinnedItems
    }

    func setItems(_ items: [PinnedItem], in folder: Folder?) {
        if let folder { folder.items = items } else { pinnedItems = items }
    }

    /// Every folder, depth first.
    var folders: [Folder] {
        func walk(_ items: [PinnedItem]) -> [Folder] {
            items.flatMap { item -> [Folder] in
                guard case .folder(let folder) = item else { return [] }
                return [folder] + walk(folder.items)
            }
        }
        return walk(pinnedItems)
    }

    /// The folder holding a tab or folder, nil at the top level or when absent.
    func parent(of object: AnyObject) -> Folder? {
        folders.first { folder in folder.items.contains { $0.object === object } }
    }

    /// The folders around a pinned tab, outermost first.
    func ancestors(of object: AnyObject) -> [Folder] {
        var chain: [Folder] = []
        var current = parent(of: object)
        while let folder = current {
            chain.insert(folder, at: 0)
            current = parent(of: folder)
        }
        return chain
    }

    /// Takes a tab or folder out of the pinned tree. Returns where it was.
    @discardableResult
    func removePinned(_ object: AnyObject) -> (parent: Folder?, index: Int)? {
        let parent = parent(of: object)
        var items = items(in: parent)
        guard let index = items.firstIndex(where: { $0.object === object }) else { return nil }
        items.remove(at: index)
        setItems(items, in: parent)
        return (parent, index)
    }

    func insertPinned(_ item: PinnedItem, in folder: Folder?, at index: Int) {
        var items = items(in: folder)
        items.insert(item, at: max(0, min(index, items.count)))
        setItems(items, in: folder)
    }

    /// Whether `folder` is `other` or contains it, at any depth.
    func folder(_ folder: Folder, contains other: Folder) -> Bool {
        folder === other || folder.items.contains { item in
            if case .folder(let inner) = item { return self.folder(inner, contains: other) }
            return false
        }
    }
}
