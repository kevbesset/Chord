import Foundation

/// Turns what was typed in the command bar into a URL, or nil when it is a search.
///
/// Developer-friendly: `localhost:3000`, `127.0.0.1:8080/api`, `app.test` and
/// `printer.local` open over plain HTTP.
enum URLInput {
    private static let schemes: Set<String> = ["http", "https", "file", "about", "data", "view-source"]
    private static let localTLDs: Set<String> = ["localhost", "local", "test", "internal", "lan", "home"]

    static func url(from input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }

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
