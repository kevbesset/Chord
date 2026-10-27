import AppKit

/// Site icons, like Arc: the icon a page declares, or for a sleeping tab the one found on
/// its site (`<link rel="icon">`, then `/favicon.ico`). Cached in memory and on disk by
/// host, so that the sidebar shows them instantly, and imported from Arc's own cache.
///
/// Lookups never block: a missing icon is fetched in the background, and the caller
/// gets it later through its completion, on the main thread.
public final class FaviconStore {
    public static let shared = FaviconStore()

    private let directory: URL
    private let session: URLSession
    private var memory: [String: NSImage] = [:]
    private var waiting: [String: [(NSImage) -> Void]] = [:]
    /// Hosts without an icon, not asked again until the next launch.
    private var failed: Set<String> = []
    /// Icons live pages show, by page (Figma gives each file its own emoji), for this
    /// launch. On disk, the site keeps the last one seen.
    private var pageIcons: [String: NSImage] = [:]
    private var pageIconData: [String: Data] = [:]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "app.chord", isDirectory: true)
            .appendingPathComponent("Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 8
        configuration.httpMaximumConnectionsPerHost = 2
        // Some sites refuse requests without a browser user agent.
        configuration.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"]
        session = URLSession(configuration: configuration)
    }

    /// One icon per site: the host, with its port for local servers (localhost:3000).
    static func key(for url: URL) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return url.port.map { "\(host):\($0)" } ?? host
    }

    /// One icon per page: the site and the path, without the query (Figma's selection).
    static func pageKey(for url: URL) -> String? {
        key(for: url).map { $0 + url.path }
    }

    /// The icon for a page, or nil when it is not known yet. In that case it is fetched,
    /// and `completion` receives it if one is found.
    func icon(for url: URL?, completion: @escaping (NSImage) -> Void) -> NSImage? {
        guard let url, let key = Self.key(for: url) else { return nil }
        if let pageKey = Self.pageKey(for: url), let image = pageIcons[pageKey] { return image }
        if let image = memory[key] { return image }
        if let data = try? Data(contentsOf: file(for: key)), let image = NSImage(data: data) {
            memory[key] = image
            return image
        }
        guard !failed.contains(key), url.scheme == "http" || url.scheme == "https" else { return nil }
        if waiting[key] != nil {
            waiting[key]?.append(completion)
            return nil
        }
        waiting[key] = [completion]
        let session = session
        Task {
            let data = await Self.discoverIcon(near: url, session: session)
            await MainActor.run { self.finish(key, data: data) }
        }
        return nil
    }

    /// Uses the icon a live page shows, already downloaded and rendered by the engine.
    func useIcon(_ data: Data, for pageURL: URL) {
        guard let key = Self.key(for: pageURL), let pageKey = Self.pageKey(for: pageURL),
              pageIconData[pageKey] != data, let image = NSImage(data: data), image.isValid else { return }
        pageIconData[pageKey] = data
        pageIcons[pageKey] = image
        store(data, key: key)
    }

    /// Icon data from elsewhere (Arc's cache), for a page. It replaces a guessed icon.
    func store(_ data: Data, for pageURL: URL) {
        guard let key = Self.key(for: pageURL) else { return }
        store(data, key: key)
    }

    // MARK: - Storage

    private func file(for key: String) -> URL {
        directory.appendingPathComponent(key.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_"))
    }

    private func store(_ data: Data, key: String) {
        guard let image = NSImage(data: data), image.isValid else { return }
        memory[key] = image
        failed.remove(key)
        try? data.write(to: file(for: key), options: .atomic)
        let callbacks = waiting.removeValue(forKey: key) ?? []
        callbacks.forEach { $0(image) }
    }

    private func finish(_ key: String, data: Data?) {
        if let data, NSImage(data: data)?.isValid == true {
            store(data, key: key)
        } else {
            failed.insert(key)
            waiting[key] = nil
        }
    }

    // MARK: - Discovery

    /// The site's declared icons, best first, then /favicon.ico.
    private static func discoverIcon(near url: URL, session: URLSession) async -> Data? {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = "/"
        guard let root = components.url else { return nil }

        var candidates: [URL] = []
        if let (data, response) = try? await session.data(from: root) {
            let html = String(decoding: data.prefix(400_000), as: UTF8.self)
            candidates = iconLinks(in: html, base: response.url ?? root)
        }
        if let fallback = URL(string: "/favicon.ico", relativeTo: root)?.absoluteURL {
            candidates.append(fallback)
        }
        for candidate in candidates {
            if let data = await download(candidate, session: session) { return data }
        }
        return nil
    }

    private static func download(_ url: URL, session: URLSession) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
              let image = NSImage(data: data), image.isValid, image.size.width > 0 else { return nil }
        return data
    }

    /// `<link rel="icon">` and friends, ranked for a 16 to 20 pt icon on a Retina screen:
    /// sized icons of 32 px and up first (smallest first), then unsized ones, then
    /// apple-touch icons (app-icon look), then tiny ones. Mask icons are monochrome: skipped.
    static func iconLinks(in html: String, base: URL) -> [URL] {
        guard let tagPattern = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive) else { return [] }
        var ranked: [(score: Int, url: URL)] = []
        let range = NSRange(html.startIndex..., in: html)
        for match in tagPattern.matches(in: html, range: range) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard let rel = attribute("rel", in: tag)?.lowercased(), rel.contains("icon"), !rel.contains("mask"),
                  let href = attribute("href", in: tag), let url = URL(string: href, relativeTo: base)?.absoluteURL else { continue }
            let size = attribute("sizes", in: tag)
                .flatMap { $0.lowercased().split(separator: " ").compactMap { Int($0.split(separator: "x").first ?? "") }.max() }
            let score: Int
            if rel.contains("apple-touch") {
                score = 2000 + (size ?? 180)
            } else if let size {
                score = size >= 32 ? size : 3000 + size
            } else {
                score = 1000
            }
            ranked.append((score, url))
        }
        return ranked.sorted { $0.score < $1.score }.map(\.url)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in 1...3 {
            if let range = Range(match.range(at: group), in: tag) { return String(tag[range]) }
        }
        return nil
    }
}
