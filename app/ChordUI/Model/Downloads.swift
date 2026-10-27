import AppKit
import Combine

/// The downloads shown in the downloads panel: this session's, as the engine reports
/// them (with their progress), then the most recent files of the Downloads folder, so
/// that the panel is useful from the first launch.
public final class Downloads {
    public struct Item: Equatable {
        public enum State: Equatable {
            case running(Double), done, failed
            /// Held back until the user keeps it: "insecure" (an http address) or
            /// "dangerous" (a file type that can harm the Mac).
            case needsApproval(String)
        }
        /// The engine's id for downloads of this session, nil for files found on disk.
        public let id: String?
        public let url: URL
        public var state: State
        public let date: Date
    }

    public let changes = PassthroughSubject<Void, Never>()
    /// This session's downloads, newest first.
    public private(set) var session: [Item] = []
    public let folder: URL

    public init(folder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        self.folder = folder
    }

    public var hasRunning: Bool {
        session.contains {
            switch $0.state {
            case .running, .needsApproval: return true
            case .done, .failed: return false
            }
        }
    }

    /// This session's downloads first, then the folder's newest files, `limit` in all.
    public func recent(limit: Int = 8) -> [Item] {
        let known = Set(session.map(\.url.standardizedFileURL))
        let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .creationDateKey, .isHiddenKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let onDisk = files
            .filter { !known.contains($0.standardizedFileURL) && !Self.isPartial($0) }
            .map { url -> Item in
                let values = try? url.resourceValues(forKeys: Set(keys))
                let date = values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast
                return Item(id: nil, url: url, state: .done, date: date)
            }
            .sorted { $0.date > $1.date }
        return Array((session + onDisk).prefix(limit))
    }

    /// Unfinished downloads of other browsers.
    private static func isPartial(_ url: URL) -> Bool {
        ["crdownload", "download", "part", "partial"].contains(url.pathExtension.lowercased())
    }

    // MARK: - Engine reports

    func start(id: String, destination: URL) {
        session.insert(Item(id: id, url: destination, state: .running(0), date: Date()), at: 0)
        changes.send()
    }

    func progress(id: String, fraction: Double) {
        guard let index = session.firstIndex(where: { $0.id == id }) else { return }
        if case .needsApproval = session[index].state { return }
        session[index].state = .running(max(0, min(1, fraction)))
        changes.send()
    }

    func needsApproval(id: String, warning: String) {
        guard let index = session.firstIndex(where: { $0.id == id }) else { return }
        session[index].state = .needsApproval(warning)
        changes.send()
    }

    /// The user kept a download held back: it carries on.
    func approve(id: String) {
        guard let index = session.firstIndex(where: { $0.id == id }),
              case .needsApproval = session[index].state else { return }
        session[index].state = .running(0)
        changes.send()
    }

    func finish(id: String, fileURL: URL?) {
        guard let index = session.firstIndex(where: { $0.id == id }) else { return }
        session[index].state = fileURL == nil ? .failed : .done
        changes.send()
    }

    /// A failed download is dropped from the list when dismissed.
    func remove(id: String) {
        session.removeAll { $0.id == id }
        changes.send()
    }
}
