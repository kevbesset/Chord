import Foundation
import SQLite3

/// The browsers Chord imports from besides Arc. Browsers built on Chromium (Google
/// Chrome, Brave, Edge, Vivaldi, Chromium) keep profiles like Arc's: each becomes a Space
/// whose pinned tabs are its bookmarks bar, and its logins, passwords, history and
/// extensions come through the engine (`ChordWebEngine.importFromBrowser`). Safari gives
/// its bookmarks bar and its history, once Chord has Full Disk Access.
public enum BrowserImport {
    public struct Source: Equatable {
        /// Short and stable: "chrome", "brave", "safari"… Chord's profiles imported from it
        /// are "<id>:<profile folder>".
        public let id: String
        public let name: String
        /// The browser's user data folder (its profiles), or Safari's folder.
        let folder: URL
        /// The keychain item of its Chromium key; nil for Safari.
        let keychainService: String?
        let keychainAccount: String?

        public var isSafari: Bool { id == "safari" }

        public var isInstalled: Bool {
            isSafari
                ? FileManager.default.fileExists(atPath: folder.path)
                : FileManager.default.fileExists(atPath: folder.appendingPathComponent("Local State").path)
        }
    }

    public enum Failure: Error {
        /// macOS keeps Safari's folder from apps without Full Disk Access.
        case needsFullDiskAccess
        case unreadable
    }

    private static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }

    public static let sources: [Source] = [
        Source(id: "chrome", name: "Google Chrome", folder: support.appendingPathComponent("Google/Chrome"),
               keychainService: "Chrome Safe Storage", keychainAccount: "Chrome"),
        Source(id: "brave", name: "Brave", folder: support.appendingPathComponent("BraveSoftware/Brave-Browser"),
               keychainService: "Brave Safe Storage", keychainAccount: "Brave"),
        Source(id: "edge", name: "Microsoft Edge", folder: support.appendingPathComponent("Microsoft Edge"),
               keychainService: "Microsoft Edge Safe Storage", keychainAccount: "Microsoft Edge"),
        Source(id: "vivaldi", name: "Vivaldi", folder: support.appendingPathComponent("Vivaldi"),
               keychainService: "Vivaldi Safe Storage", keychainAccount: "Vivaldi"),
        Source(id: "chromium", name: "Chromium", folder: support.appendingPathComponent("Chromium"),
               keychainService: "Chromium Safe Storage", keychainAccount: "Chromium"),
        Source(id: "safari", name: "Safari",
               folder: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari"),
               keychainService: nil, keychainAccount: nil),
    ]

    /// The browsers found on this Mac.
    public static var installed: [Source] { sources.filter(\.isInstalled) }

    /// What a source brings: its Spaces (one per profile), and for each Chord profile the
    /// browser's profile folder whose data the engine imports.
    public struct Result {
        public var spaces: [Space]
        var profileFolders: [String: URL]
        public var tabCount: Int { spaces.reduce(0) { $0 + $1.allTabs.count } }
        /// Safari's history, for the engine.
        var history: [[String: Any]] = []
    }

    /// Like Arc's: the browser's default profile is Chord's default one.
    static func chordProfile(for source: Source, folder: String) -> String {
        folder == "Default" ? Space.defaultProfile : "\(source.id):\(folder)"
    }

    public static func load(_ source: Source) throws -> Result {
        source.isSafari ? try loadSafari(source) : try loadChromium(source)
    }

    // MARK: - Browsers built on Chromium

    private static func loadChromium(_ source: Source) throws -> Result {
        guard let data = try? Data(contentsOf: source.folder.appendingPathComponent("Local State")),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.unreadable }
        // Profiles by folder, with the names the browser shows, in its own order.
        let profiles = (state["profile"] as? [String: Any])?["info_cache"] as? [String: Any] ?? ["Default": [:]]
        let order = ((state["profile"] as? [String: Any])?["profiles_order"] as? [String]) ?? profiles.keys.sorted()
        var spaces: [Space] = []
        var folders: [String: URL] = [:]
        for (index, folder) in order.enumerated() where profiles[folder] != nil {
            let directory = source.folder.appendingPathComponent(folder)
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("Preferences").path) else { continue }
            let profileName = ((profiles[folder] as? [String: Any])?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let name = folder == "Default" || order.count == 1 ? source.name : "\(source.name) · \(profileName ?? folder)"
            let chordProfile = chordProfile(for: source, folder: folder)
            let space = Space(name: name, colorHex: Theme.spacePalette[(index + 2) % Theme.spacePalette.count],
                              profileID: chordProfile, pinnedItems: chromiumBookmarks(in: directory))
            importIcons(for: space.allTabs, from: directory.appendingPathComponent("Favicons"))
            spaces.append(space)
            folders[chordProfile] = directory
        }
        guard !spaces.isEmpty else { throw Failure.unreadable }
        return Result(spaces: spaces, profileFolders: folders)
    }

    /// The bookmarks bar, folders kept, then the other bookmarks in a folder of their own.
    private static func chromiumBookmarks(in profile: URL) -> [PinnedItem] {
        guard let data = try? Data(contentsOf: profile.appendingPathComponent("Bookmarks")),
              let root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["roots"] as? [String: Any]
        else { return [] }
        func items(_ node: Any?) -> [PinnedItem] {
            ((node as? [String: Any])?["children"] as? [[String: Any]] ?? []).compactMap { child in
                let title = child["name"] as? String ?? ""
                if child["type"] as? String == "url" {
                    guard let url = (child["url"] as? String).flatMap(URL.init(string:)), url.scheme == "http" || url.scheme == "https" else { return nil }
                    return .tab(Tab(url: url, title: title, section: .pinned))
                }
                let inner = items(child)
                return inner.isEmpty ? nil : .folder(Folder(name: title.isEmpty ? String(localized: "Folder", bundle: .chordUI) : title, isExpanded: false, items: inner))
            }
        }
        var pinned = items(root["bookmark_bar"])
        let others = items(root["other"])
        if !others.isEmpty {
            pinned.append(.folder(Folder(name: String(localized: "Other Bookmarks", bundle: .chordUI), isExpanded: false, items: others)))
        }
        return pinned
    }

    /// The icons the browser already has for these tabs, like the Arc import's.
    private static func importIcons(for tabs: [Tab], from database: URL) {
        ArcImport.importIcons(for: tabs, from: database)
    }

    // MARK: - Safari

    private static func loadSafari(_ source: Source) throws -> Result {
        let bookmarksFile = source.folder.appendingPathComponent("Bookmarks.plist")
        guard FileManager.default.isReadableFile(atPath: bookmarksFile.path),
              let data = try? Data(contentsOf: bookmarksFile) else { throw Failure.needsFullDiskAccess }
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw Failure.unreadable
        }
        func items(_ node: [String: Any]) -> [PinnedItem] {
            (node["Children"] as? [[String: Any]] ?? []).compactMap { child in
                switch child["WebBookmarkType"] as? String {
                case "WebBookmarkTypeLeaf":
                    guard let url = (child["URLString"] as? String).flatMap(URL.init(string:)), url.scheme == "http" || url.scheme == "https" else { return nil }
                    let title = (child["URIDictionary"] as? [String: Any])?["title"] as? String ?? ""
                    return .tab(Tab(url: url, title: title, section: .pinned))
                case "WebBookmarkTypeList":
                    let inner = items(child)
                    let title = child["Title"] as? String ?? ""
                    return inner.isEmpty ? nil : .folder(Folder(name: title.isEmpty ? String(localized: "Folder", bundle: .chordUI) : title, isExpanded: false, items: inner))
                default:
                    return nil
                }
            }
        }
        let lists = root["Children"] as? [[String: Any]] ?? []
        // The favourites bar as pinned tabs, the bookmarks menu in a folder; the reading
        // list stays in Safari.
        var pinned = lists.first { $0["Title"] as? String == "BookmarksBar" }.map(items) ?? []
        if let menu = lists.first(where: { $0["Title"] as? String == "BookmarksMenu" }).map(items), !menu.isEmpty {
            pinned.append(.folder(Folder(name: String(localized: "Bookmarks Menu", bundle: .chordUI), isExpanded: false, items: menu)))
        }
        let space = Space(name: source.name, colorHex: Theme.spacePalette[3 % Theme.spacePalette.count],
                          profileID: Space.defaultProfile, pinnedItems: pinned)
        return Result(spaces: [space], profileFolders: [:], history: safariHistory(in: source.folder))
    }

    /// The last 90 days of Safari's history, as the engine takes it.
    private static func safariHistory(in folder: URL) -> [[String: Any]] {
        let database = folder.appendingPathComponent("History.db")
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("chord-safari-history-\(UUID().uuidString)")
        guard (try? FileManager.default.copyItem(at: database, to: copy)) != nil else { return [] }
        defer {
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: copy.path + suffix) }
        }
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.copyItem(atPath: database.path + suffix, toPath: copy.path + suffix)
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else { return [] }
        defer { sqlite3_close(db) }
        // Visit times count from 2001, like NSDate's reference date.
        let since = Date().addingTimeInterval(-90 * 24 * 3600).timeIntervalSinceReferenceDate
        let sql = """
            SELECT i.url, i.visit_count, MAX(v.visit_time), v.title FROM history_items i
            JOIN history_visits v ON v.history_item = i.id
            WHERE v.visit_time > ? GROUP BY i.id
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, since)
        var pages: [[String: Any]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0), let url = URL(string: String(cString: text)),
                  url.scheme == "http" || url.scheme == "https" else { continue }
            var page: [String: Any] = [
                "url": url,
                "visits": Int(sqlite3_column_int(statement, 1)),
                "lastVisit": Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 2)),
            ]
            if let title = sqlite3_column_text(statement, 3) { page["title"] = String(cString: title) }
            pages.append(page)
        }
        return pages
    }
}

extension BrowserState {
    /// What came over from another browser.
    public struct BrowserDataImport {
        public var spaces = 0
        public var tabs = 0
        public var cookies = 0
        public var passwords = 0
        public var pages = 0
        public var extensions = 0
        public var siteStorage = false
        /// macOS did not give the browser's key: logins and passwords stayed behind.
        public var keyDenied = false
    }

    /// Adds the browser's Spaces (updated in place when imported before), then brings its
    /// logins, passwords, history and extensions into the profile of each Space.
    public func importBrowser(_ source: BrowserImport.Source, result: BrowserImport.Result,
                              completion: @escaping (BrowserDataImport) -> Void) {
        add(spaces: result.spaces, favorites: [:])
        var total = BrowserDataImport(spaces: result.spaces.count, tabs: result.tabCount)
        if !result.history.isEmpty {
            engine(forProfile: Space.defaultProfile).addHistory?(result.history)
            total.pages = result.history.count
        }
        guard !isPrivate, let service = source.keychainService, let account = source.keychainAccount,
              !result.profileFolders.isEmpty else {
            completion(total)
            return
        }
        let group = DispatchGroup()
        for (profile, folder) in result.profileFolders {
            guard let importer = engine(forProfile: profile).importFromBrowser else { continue }
            group.enter()
            importer(source.name, service, account, folder.path) { counts in
                DispatchQueue.main.async {
                    total.cookies += counts["cookies"] ?? 0
                    total.passwords += counts["passwords"] ?? 0
                    total.pages += counts["pages"] ?? 0
                    total.extensions += counts["extensions"] ?? 0
                    total.siteStorage = total.siteStorage || counts["siteStorage"] == 1
                    total.keyDenied = total.keyDenied || counts["keyDenied"] == 1
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { completion(total) }
    }
}
