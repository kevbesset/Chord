import AppKit

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

    /// The browser's own pages, and those that are not on a web site, have no icon to
    /// fetch: like Arc, a symbol stands in for each (Chromium's settings, extensions,
    /// history…, a local file, a blank page). Nil for web pages.
    var builtInPageSymbol: (name: String, isBrowserPage: Bool)? {
        switch scheme {
        case "chrome", URLInput.internalScheme:
            let symbols = [
                "settings": "gearshape.fill",
                "extensions": "puzzlepiece.extension.fill",
                "history": "clock.fill",
                "downloads": "arrow.down.circle.fill",
                "bookmarks": "star.fill",
                "password-manager": "key.fill",
                "flags": "flag.fill",
                "version": "info.circle.fill",
                "about": "info.circle.fill",
                "chrome-urls": "list.bullet",
                "newtab": "plus.square.fill",
                "new-tab-page": "plus.square.fill",
                "apps": "square.grid.2x2.fill",
                "inspect": "hammer.fill",
                "gpu": "cpu.fill",
                "net-internals": "network",
                "net-export": "network",
                "components": "shippingbox.fill",
                "policy": "building.columns.fill",
                "management": "building.columns.fill",
                "crashes": "exclamationmark.triangle.fill",
                "print": "printer.fill",
                "sandbox": "lock.shield.fill",
                "media-internals": "play.rectangle.fill",
                "webrtc-internals": "video.fill",
                "accessibility": "accessibility",
            ]
            return (symbols[host ?? ""] ?? "doc.text.fill", true)
        case "chrome-extension":
            return ("puzzlepiece.extension.fill", true)
        case "devtools":
            return ("hammer.fill", true)
        case "view-source":
            return ("chevron.left.forwardslash.chevron.right", true)
        case "file", "data", "blob":
            return ("doc.fill", false)
        case "about":
            return ("doc", false)
        default:
            return nil
        }
    }

    /// The address as the address bars show it: the host, then the path in a quieter
    /// colour, in one run, like Arc's.
    func addressText(size: CGFloat) -> NSAttributedString {
        let text = NSMutableAttributedString(string: displayHost, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ])
        if path != "/" && !path.isEmpty {
            text.append(NSAttributedString(string: path, attributes: [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        return text
    }

    /// A site reached without encryption, away from this machine and its network: the
    /// only case the address bars point out. HTTPS is the norm, and a local dev server
    /// on HTTP is expected.
    var isInsecure: Bool {
        scheme == "http" && !isLocal
    }

    /// This Mac, the local network, or a development name (.local, .test, .localhost).
    var isLocal: Bool {
        guard let host = host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")) else { return false }
        if host == "localhost" || host == "::1" { return true }
        let labels = host.split(separator: ".")
        if let last = labels.last, ["localhost", "local", "test", "internal", "lan", "home"].contains(String(last)) { return true }
        let octets = labels.compactMap { Int($0) }
        guard labels.count == 4, octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (127, _), (10, _), (192, 168), (169, 254): return true
        case (172, let second): return (16...31).contains(second)
        default: return false
        }
    }
}
