import Foundation

struct TabSnapshot: Codable {
    var id: UUID
    var url: URL?
    var title: String
}

struct FolderSnapshot: Codable {
    var id: UUID
    var name: String
    var isExpanded: Bool
    var items: [PinnedSnapshot]
}

enum PinnedSnapshot: Codable {
    case tab(TabSnapshot)
    case folder(FolderSnapshot)
}

struct SpaceSnapshot: Codable {
    var id: UUID
    var name: String
    var colorHex: String
    /// Every pinned tab, flattened. Read only when `pinnedTree` is missing (version 1 and 2).
    var pinned: [TabSnapshot]
    var today: [TabSnapshot]
    var selectedTabID: UUID?
    /// Added in version 2.
    var split: [UUID]?
    /// Added in version 3: pinned tabs with their folders.
    var pinnedTree: [PinnedSnapshot]?
    /// Added in version 3.
    var profileID: String?
}

struct SessionSnapshot: Codable {
    var version: Int = 3
    var spaces: [SpaceSnapshot]
    var activeSpaceID: UUID
    /// Version 2: favorites shared by every Space. Read as the default profile's.
    var favorites: [TabSnapshot]?
    /// Added in version 3: favorites by profile.
    var profileFavorites: [String: [TabSnapshot]]?
}

/// Saves and restores Spaces and tabs as a small JSON file.
public final class SessionStore {
    let fileURL: URL

    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("session.json")
    }

    func load() -> SessionSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    func save(_ snapshot: SessionSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension Tab {
    convenience init(snapshot: TabSnapshot, section: TabSection) {
        self.init(id: snapshot.id, url: snapshot.url, title: snapshot.title, section: section)
    }

    var snapshot: TabSnapshot {
        TabSnapshot(id: id, url: url, title: title)
    }
}

extension PinnedItem {
    init(snapshot: PinnedSnapshot) {
        switch snapshot {
        case .tab(let tab):
            self = .tab(Tab(snapshot: tab, section: .pinned))
        case .folder(let folder):
            self = .folder(Folder(id: folder.id, name: folder.name, isExpanded: folder.isExpanded,
                                  items: folder.items.map(PinnedItem.init(snapshot:))))
        }
    }

    var snapshot: PinnedSnapshot {
        switch self {
        case .tab(let tab):
            return .tab(tab.snapshot)
        case .folder(let folder):
            return .folder(FolderSnapshot(id: folder.id, name: folder.name, isExpanded: folder.isExpanded,
                                          items: folder.items.map(\.snapshot)))
        }
    }
}

extension Space {
    convenience init(snapshot: SpaceSnapshot) {
        let pinned = snapshot.pinnedTree?.map(PinnedItem.init(snapshot:))
            ?? snapshot.pinned.map { .tab(Tab(snapshot: $0, section: .pinned)) }
        self.init(
            id: snapshot.id,
            name: snapshot.name,
            colorHex: snapshot.colorHex,
            profileID: snapshot.profileID ?? Space.defaultProfile,
            pinnedItems: pinned,
            today: snapshot.today.map { Tab(snapshot: $0, section: .today) },
            selectedTabID: snapshot.selectedTabID,
            split: snapshot.split ?? []
        )
    }

    var snapshot: SpaceSnapshot {
        SpaceSnapshot(
            id: id,
            name: name,
            colorHex: colorHex,
            pinned: pinned.map(\.snapshot),
            today: today.map(\.snapshot),
            selectedTabID: selectedTabID,
            split: split.isEmpty ? nil : split,
            pinnedTree: pinnedItems.map(\.snapshot),
            profileID: profileID
        )
    }
}
