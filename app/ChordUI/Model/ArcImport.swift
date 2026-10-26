import Foundation
import SQLite3

/// Reads Arc's sidebar (`StorableSidebar.json`): Spaces with their colour and profile,
/// pinned tabs with their folders, today's tabs, and each profile's favorites. Site icons
/// come from Arc's own icon cache. History, passwords and cookies come later, with
/// Chromium's own importers.
///
/// The file stores its collections as flat arrays alternating an id and an object.
public enum ArcImport {
    public struct Result {
        public var spaces: [Space]
        /// By Chord profile id: one per Arc profile used by the imported Spaces.
        public var favorites: [String: [Tab]]
        public var folderCount: Int
        public var tabCount: Int {
            favorites.values.reduce(0) { $0 + $1.count } + spaces.reduce(0) { $0 + $1.allTabs.count }
        }
    }

    public enum Failure: Error {
        case notFound, unreadable
    }

    static var arcDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Arc")
    }

    public static var defaultFileURL: URL {
        arcDirectory.appendingPathComponent("StorableSidebar.json")
    }

    public static var isAvailable: Bool {
        FileManager.default.isReadableFile(atPath: defaultFileURL.path)
    }

    public static func load(from url: URL = defaultFileURL) throws -> Result {
        guard FileManager.default.fileExists(atPath: url.path) else { throw Failure.notFound }
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sidebar = root["sidebar"] as? [String: Any],
              let containers = sidebar["containers"] as? [Any],
              let container = containers.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] != nil })
        else { throw Failure.unreadable }

        var itemsByID: [String: [String: Any]] = [:]
        for item in objects(container["items"]) {
            if let id = item["id"] as? String { itemsByID[id] = item }
        }
        var folderCount = 0
        /// Which Arc profile directory each imported tab came from, for its icon.
        var tabsByDirectory: [String: [Tab]] = [:]

        func tab(from item: [String: Any], section: TabSection) -> Tab? {
            guard let data = item["data"] as? [String: Any], let tab = data["tab"] as? [String: Any],
                  let string = tab["savedURL"] as? String, let url = URL(string: string) else { return nil }
            let title = (item["title"] as? String) ?? (tab["savedTitle"] as? String) ?? ""
            return Tab(url: url, title: title, section: section)
        }

        /// The pinned items under a container or folder, folders kept.
        func pinnedItems(under id: String) -> [PinnedItem] {
            let children = itemsByID[id]?["childrenIds"] as? [String] ?? []
            return children.compactMap { childID -> PinnedItem? in
                guard let item = itemsByID[childID] else { return nil }
                if let tab = tab(from: item, section: .pinned) { return .tab(tab) }
                guard let data = item["data"] as? [String: Any], data["list"] != nil else { return nil }
                folderCount += 1
                let name = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Dossier"
                return .folder(Folder(name: name, isExpanded: false, items: pinnedItems(under: childID)))
            }
        }

        /// The tabs under a container, folders flattened (today's tabs have no folders).
        func tabs(under id: String, section: TabSection) -> [Tab] {
            guard let item = itemsByID[id] else { return [] }
            if let tab = tab(from: item, section: section) { return [tab] }
            let children = item["childrenIds"] as? [String] ?? []
            return children.flatMap { tabs(under: $0, section: section) }
        }

        var spaces: [Space] = []
        var profilesUsed: [String: String] = [:]
        for (index, object) in objects(container["spaces"]).enumerated() {
            let ids = containerIDs(object["containerIDs"])
            let pinned = ids["pinned"].map(pinnedItems(under:)) ?? []
            let today = ids["unpinned"].map { tabs(under: $0, section: .today) } ?? []
            let name = (object["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Space \(index + 1)"
            let profile = profile(object["profile"])
            profilesUsed[profile.id] = profile.directory
            let space = Space(name: name, colorHex: color(of: object) ?? Theme.spacePalette[index % Theme.spacePalette.count],
                              profileID: profile.id, pinnedItems: pinned, today: today)
            if let selected = space.pinned.first ?? today.first {
                space.selectedTabID = selected.id
                // The selected tab stays in sight, even inside a folder.
                for folder in space.ancestors(of: selected) { folder.isExpanded = true }
            }
            tabsByDirectory[profile.directory, default: []] += space.allTabs
            spaces.append(space)
        }

        // Favorites ("top apps") belong to an Arc profile, like the Spaces.
        var favorites: [String: [Tab]] = [:]
        let topApps = container["topAppsContainerIDs"] as? [Any] ?? []
        var index = 0
        while index + 1 < topApps.count {
            if let id = topApps[index + 1] as? String {
                let profile = profile(topApps[index])
                if profilesUsed[profile.id] != nil {
                    let tabs = tabs(under: id, section: .favorites)
                    favorites[profile.id] = tabs
                    tabsByDirectory[profile.directory, default: []] += tabs
                }
            }
            index += 2
        }

        for (directory, tabs) in tabsByDirectory {
            importIcons(for: tabs, from: arcDirectory.appendingPathComponent("User Data/\(directory)/Favicons"))
        }
        return Result(spaces: spaces, favorites: favorites, folderCount: folderCount)
    }

    /// Arc's profile reference → a Chord profile id and Arc's profile directory.
    /// `{"default": true}` is "Default"; `{"custom": {"_0": {"directoryBasename": "Profile 1"}}}`.
    /// Arc's default profile is Chord's default one.
    private static func profile(_ value: Any?) -> (id: String, directory: String) {
        let directory = ((value as? [String: Any])?["custom"] as? [String: Any])
            .flatMap { ($0["_0"] as? [String: Any])?["directoryBasename"] as? String } ?? "Default"
        return (directory == "Default" ? Space.defaultProfile : "arc:\(directory)", directory)
    }

    /// `[id, object, id, object…]` → the objects.
    private static func objects(_ value: Any?) -> [[String: Any]] {
        (value as? [Any] ?? []).compactMap { $0 as? [String: Any] }
    }

    /// `["unpinned", id, "pinned", id]` → ["unpinned": id, "pinned": id].
    private static func containerIDs(_ value: Any?) -> [String: String] {
        let list = value as? [Any] ?? []
        var result: [String: String] = [:]
        var index = 0
        while index + 1 < list.count {
            if let key = list[index] as? String, let id = list[index + 1] as? String { result[key] = id }
            index += 2
        }
        return result
    }

    /// The Space's main colour, from its Arc theme.
    private static func color(of space: [String: Any]) -> String? {
        guard let info = space["customInfo"] as? [String: Any],
              let theme = info["windowTheme"] as? [String: Any],
              let palette = theme["primaryColorPalette"] as? [String: Any],
              let tone = palette["midTone"] as? [String: Any],
              let red = (tone["red"] as? NSNumber)?.doubleValue,
              let green = (tone["green"] as? NSNumber)?.doubleValue,
              let blue = (tone["blue"] as? NSNumber)?.doubleValue else { return nil }
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    // MARK: - Icons

    /// Copies the icons Arc already has for these tabs into Chord's cache. Arc keeps them
    /// in Chromium's `Favicons` database: page URL → icon → bitmaps of 16 and 32 px.
    /// The database is read from a copy, since Arc may have it open.
    private static func importIcons(for tabs: [Tab], from database: URL) {
        guard !tabs.isEmpty, FileManager.default.fileExists(atPath: database.path) else { return }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("chord-arc-favicons-\(UUID().uuidString)")
        guard (try? FileManager.default.copyItem(at: database, to: copy)) != nil else { return }
        defer { try? FileManager.default.removeItem(at: copy) }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else { return }
        defer { sqlite3_close(db) }

        // The largest bitmap of each page's icon, by page URL and, as a fallback, by host.
        let sql = """
            SELECT m.page_url, b.image_data FROM icon_mapping m
            JOIN favicon_bitmaps b ON b.icon_id = m.icon_id
            WHERE b.image_data IS NOT NULL
            ORDER BY b.width ASC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        var byPage: [String: Data] = [:]
        var byHost: [String: Data] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0), let blob = sqlite3_column_blob(statement, 1) else { continue }
            let page = String(cString: text)
            let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 1)))
            // Rows come smallest first: later, larger bitmaps win.
            byPage[page] = data
            if let url = URL(string: page), let key = FaviconStore.key(for: url) { byHost[key] = data }
        }
        for tab in tabs {
            guard let url = tab.url else { continue }
            if let data = byPage[url.absoluteString] ?? FaviconStore.key(for: url).flatMap({ byHost[$0] }) {
                FaviconStore.shared.store(data, for: url)
            }
        }
    }
}

extension BrowserState {
    /// Adds Arc's Spaces and favorites to Chord's; Spaces imported before are updated.
    /// Returns how many tabs came in.
    @discardableResult
    public func importFromArc(_ result: ArcImport.Result) -> Int {
        add(spaces: result.spaces, favorites: result.favorites)
        return result.tabCount
    }
}
