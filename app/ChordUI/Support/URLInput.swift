import Foundation

/// Turns what was typed in the command bar into a URL, or nil when it is a search.
///
/// Developer-friendly: `localhost:3000`, `127.0.0.1:8080/api`, `app.test` and
/// `printer.local` open over plain HTTP.
enum URLInput {
    /// Typed with their scheme, these always open rather than search, Chromium's internal
    /// pages (`chrome://extensions`) included.
    private static let schemes: Set<String> = [
        "http", "https", "file", "about", "data", "view-source",
        "chrome", "chrome-extension", "chrome-untrusted", "devtools",
    ]
    /// Chord's name for Chromium's internal pages, like Arc's `arc://`: `chord://settings`.
    static let internalScheme = "chord"
    private static let localTLDs: Set<String> = ["localhost", "local", "test", "internal", "lan", "home"]

    static func url(from input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }

        if text.lowercased().hasPrefix(internalScheme + "://") {
            return URL(string: "chrome" + text.dropFirst(internalScheme.count))
        }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           schemes.contains(scheme), text.lowercased().hasPrefix(scheme + ":") {
            return url
        }

        let hostAndPort = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? text
        let host = (hostAndPort.split(separator: ":", maxSplits: 1).first.map(String.init) ?? hostAndPort).lowercased()
        guard !host.isEmpty else { return nil }

        let labels = host.split(separator: ".").map(String.init)
        let isIPv4 = labels.count == 4 && labels.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
        let tld = labels.last ?? host

        if host == "localhost" || isIPv4 || localTLDs.contains(tld) {
            return URL(string: "http://" + text)
        }
        if labels.count >= 2, tld.count >= 2, tld.allSatisfy({ $0.isLetter }) {
            return URL(string: "https://" + text)
        }
        return nil
    }
}

extension URL {
    /// The address's first part as the address bars show it: the host and port for the
    /// web, the scheme too for anything else (`chrome://extensions`, `file://`).
    var displayHost: String {
        let host = self.host ?? ""
        let hostAndPort = port.map { "\(host):\($0)" } ?? host
        guard let scheme, scheme != "http", scheme != "https" else { return hostAndPort.isEmpty ? absoluteString : hostAndPort }
        let shownScheme = scheme == "chrome" ? URLInput.internalScheme : scheme
        return hostAndPort.isEmpty ? absoluteString : "\(shownScheme)://\(hostAndPort)"
    }

    /// The address as the command bar shows it for editing: Chromium's internal pages
    /// under Chord's name (`chord://settings`).
    var editableString: String {
        scheme == "chrome" ? URLInput.internalScheme + absoluteString.dropFirst("chrome".count) : absoluteString
    }

    /// The address bars' icon: a lock for HTTPS, a gear for the browser's own pages.
    var addressSymbol: String {
        switch scheme {
        case "https": return "lock.fill"
        case "http": return "globe"
        case "chrome", "chrome-extension", "chrome-untrusted", "devtools", "about": return "gearshape"
        default: return "doc"
        }
    }
}
