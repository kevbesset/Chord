import AppKit

/// After a crash, the next launch turns macOS's report into a short, readable one in
/// ~/Library/Logs/Chord (the latest also as latest-crash.md), and offers to copy it:
/// enough to debug the crash without digging through the system's reports.
enum CrashReports {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Chord", isDirectory: true)
    private static let systemReports = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    private static let lastCheckKey = "lastCrashReportCheck"

    /// Looks for a crash of the browser since the last launch, writes its summary and
    /// asks the user, over `window`, what to do with it.
    static func checkForCrash(appName: String, over window: NSWindow?) {
        let defaults = UserDefaults.standard
        let lastCheck = defaults.object(forKey: lastCheckKey) as? Date ?? .distantPast
        defaults.set(Date(), forKey: lastCheckKey)
        DispatchQueue.global(qos: .utility).async {
            guard let report = newestReport(of: appName, since: lastCheck),
                  let summary = summary(of: report) else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let file = directory.appendingPathComponent("crash-\(stamp).md")
            try? summary.text.write(to: file, atomically: true, encoding: .utf8)
            try? summary.text.write(to: directory.appendingPathComponent("latest-crash.md"), atomically: true, encoding: .utf8)
            DispatchQueue.main.async { offer(summary, file: file, over: window) }
        }
    }

    private static func newestReport(of appName: String, since date: Date) -> URL? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: systemReports, includingPropertiesForKeys: keys)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("\(appName)-") && $0.pathExtension == "ips" }
            .compactMap { url -> (URL, Date)? in
                guard let modified = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate, modified > date else { return nil }
                return (url, modified)
            }
            .max { $0.1 < $1.1 }?.0
    }

    struct Summary {
        let text: String
        /// One line for the alert: the exception and the first frames of the crashed thread.
        let headline: String
    }

    /// The .ips report is a JSON header line, then the JSON report.
    static func summary(of report: URL) -> Summary? {
        guard let content = try? String(contentsOf: report, encoding: .utf8),
              let newline = content.firstIndex(of: "\n"),
              let header = try? JSONSerialization.jsonObject(with: Data(content[..<newline].utf8)) as? [String: Any],
              let body = try? JSONSerialization.jsonObject(with: Data(content[content.index(after: newline)...].utf8)) as? [String: Any]
        else { return nil }

        let exception = body["exception"] as? [String: Any] ?? [:]
        let exceptionText = [exception["type"], exception["signal"], exception["subtype"]]
            .compactMap { $0 as? String }.joined(separator: " · ")
        let images = body["usedImages"] as? [[String: Any]] ?? []
        let threads = body["threads"] as? [[String: Any]] ?? []
        let faulting = body["faultingThread"] as? Int ?? 0
        let frames = (threads.indices.contains(faulting) ? threads[faulting]["frames"] as? [[String: Any]] : nil) ?? []
        let lines = frames.prefix(40).enumerated().map { index, frame -> String in
            let image = (frame["imageIndex"] as? Int).flatMap { images.indices.contains($0) ? images[$0]["name"] as? String : nil } ?? "?"
            let symbol = frame["symbol"] as? String ?? String(format: "0x%llx", frame["imageOffset"] as? UInt64 ?? 0)
            return String(format: "%2d  %@  %@", index, image, symbol)
        }

        var text = "# \(header["app_name"] as? String ?? "Chord") crash\n\n"
        text += "- Date: \(header["timestamp"] as? String ?? "?")\n"
        text += "- Version: \(header["app_version"] as? String ?? "?") (\(header["bundleID"] as? String ?? "?"))\n"
        text += "- System: \(header["os_version"] as? String ?? "?")\n"
        text += "- Exception: \(exceptionText.isEmpty ? "?" : exceptionText)\n"
        text += "- macOS report: \(report.path)\n"
        if let fatal = fatalMessage(near: report) {
            text += "\n## Chromium's error message\n\n```\n\(fatal)\n```\n"
        }
        text += "\n## Crashed thread (\(faulting))\n\n```\n\(lines.joined(separator: "\n"))\n```\n"

        let firstChordFrame = frames.lazy
            .compactMap { $0["symbol"] as? String }
            .first { !$0.hasPrefix("logging::") && !$0.hasPrefix("<") && !$0.contains("pthread") && !$0.contains("abort") }
        let headline = [exceptionText, firstChordFrame].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        return Summary(text: text, headline: headline)
    }

    /// The fatal error Chromium logged just before the crash, if any (//chord writes it).
    private static func fatalMessage(near report: URL) -> String? {
        let file = directory.appendingPathComponent("last-fatal.txt")
        guard let content = try? String(contentsOf: file, encoding: .utf8),
              let firstLine = content.split(separator: "\n", maxSplits: 1).first,
              let seconds = Double(firstLine),
              let reportDate = try? report.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              abs(reportDate.timeIntervalSince1970 - seconds) < 120
        else { return nil }
        return content.split(separator: "\n", maxSplits: 1).dropFirst().first.map(String.init)
    }

    private static func offer(_ summary: Summary, file: URL, over window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = "Chord quit unexpectedly"
        alert.informativeText = "A report was saved in \(file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).\n\n\(summary.headline)"
        alert.addButton(withTitle: "Copy Report")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Close")
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            switch response {
            case .alertFirstButtonReturn:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(summary.text, forType: .string)
            case .alertSecondButtonReturn:
                NSWorkspace.shared.activateFileViewerSelecting([file])
            default:
                break
            }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
    }
}
