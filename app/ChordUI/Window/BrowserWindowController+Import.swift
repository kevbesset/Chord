import AppKit

// Importing from another browser: Google Chrome, Brave, Edge, Vivaldi, Chromium or Safari.
extension BrowserWindowController {
    /// Asks which browser to import from, among those on this Mac.
    @objc public func importFromBrowser(_ sender: Any?) {
        guard let window else { return }
        let sources = BrowserImport.installed
        let alert = NSAlert()
        guard !sources.isEmpty else {
            alert.messageText = String(localized: "No other browser found", bundle: .chordUI)
            alert.informativeText = String(localized: "Chord imports from Google Chrome, Brave, Microsoft Edge, Vivaldi, Chromium and Safari.", bundle: .chordUI)
            alert.beginSheetModal(for: window)
            return
        }
        alert.messageText = String(localized: "Import from another browser", bundle: .chordUI)
        alert.informativeText = String(localized: "Each profile of the browser becomes a Space, with its bookmarks bar as pinned tabs. Logins, passwords, history and extensions come into that Space's profile. The browser is left unchanged.", bundle: .chordUI)
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 240, height: 26), pullsDown: false)
        popup.addItems(withTitles: sources.map(\.name))
        alert.accessoryView = popup
        alert.addButton(withTitle: String(localized: "Import", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, sources.indices.contains(popup.indexOfSelectedItem) else { return }
            // After this sheet has gone, for the next one.
            DispatchQueue.main.async { self?.importBrowser(sources[popup.indexOfSelectedItem]) }
        }
    }

    func importBrowser(_ source: BrowserImport.Source) {
        guard let window else { return }
        let result: BrowserImport.Result
        do {
            result = try BrowserImport.load(source)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Couldn't import from \(source.name)", bundle: .chordUI)
            if (error as? BrowserImport.Failure) == .needsFullDiskAccess {
                alert.informativeText = String(localized: "macOS keeps Safari's bookmarks and history from other apps. Give Chord Full Disk Access in System Settings › Privacy & Security, then import again.", bundle: .chordUI)
                alert.addButton(withTitle: String(localized: "Open System Settings", bundle: .chordUI))
                alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
            } else {
                alert.informativeText = String(localized: "Its profiles couldn't be read.", bundle: .chordUI)
            }
            alert.beginSheetModal(for: window) { response in
                guard (error as? BrowserImport.Failure) == .needsFullDiskAccess, response == .alertFirstButtonReturn,
                      let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
                NSWorkspace.shared.open(url)
            }
            return
        }
        state.importBrowser(source, result: result) { [weak self] data in
            self?.showBrowserImport(source, data: data)
        }
    }

    private func showBrowserImport(_ source: BrowserImport.Source, data: BrowserState.BrowserDataImport) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "\(source.name) imported", bundle: .chordUI)
        var lines = [
            data.spaces == 1
                ? String(localized: "1 Space with \(data.tabs) bookmarks as pinned tabs. A Space imported before is updated rather than duplicated.", bundle: .chordUI)
                : String(localized: "\(data.spaces) Spaces with \(data.tabs) bookmarks as pinned tabs. A Space imported before is updated rather than duplicated.", bundle: .chordUI),
        ]
        if source.isSafari {
            lines.append(String(localized: "\(data.pages) history pages imported. Safari's passwords stay in iCloud Keychain, where Chord can't read them.", bundle: .chordUI))
        } else if data.keyDenied {
            alert.alertStyle = .warning
            lines.append(String(localized: "macOS didn't give access to \(source.name)'s key: logins and passwords stayed in \(source.name). \(data.pages) history pages imported.", bundle: .chordUI))
        } else {
            lines.append(String(localized: "\(data.cookies) login cookies, \(data.passwords) passwords and \(data.pages) history pages imported, each into the profile of its Space. What was already in Chord is kept.", bundle: .chordUI))
        }
        if data.extensions > 0 {
            lines.append(data.extensions == 1 ? String(localized: "1 extension installed from the Chrome Web Store.", bundle: .chordUI) : String(localized: "\(data.extensions) extensions installed from the Chrome Web Store.", bundle: .chordUI))
        }
        if data.siteStorage || data.extensions > 0 {
            lines.append(String(localized: "Site and extension data arrive at Chord's next launch.", bundle: .chordUI))
        }
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.beginSheetModal(for: window)
    }
}
