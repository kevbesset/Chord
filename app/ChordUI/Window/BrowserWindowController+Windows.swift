import AppKit
import Combine

// Little windows, the Arc import and Spaces.
extension BrowserWindowController {
    // MARK: - Little windows

    /// Opens a little window (Little Arc), on `url` or empty with the address focused.
    /// The host calls this for links opened from other apps.
    public func openLittleWindow(url: URL?) {
        let interval = Perf.begin("littlewindow.open")
        // Like Little Arc: the page goes to the last Space used, unless another is picked.
        let little = LittleWindowController(engine: state.engine(for: state.activeSpace), settings: settings, url: url,
                                            space: state.activeSpace, spaces: { [weak self] in self?.state.spaces ?? [] })
        little.onOpenInChord = { [weak self] page, space in
            guard let self else { return }
            let target = self.state.spaces.contains { $0 === space } ? space : self.state.activeSpace
            self.state.openTab(url: page.url ?? URL(string: "about:blank")!, adopting: page, in: target)
            self.window?.makeKeyAndOrderFront(nil)
        }
        little.onNewTab = { [weak self] url in self?.state.openTab(url: url) }
        little.onClose = { [weak self] closed in self?.littleWindows.removeAll { $0 === closed } }
        littleWindows.append(little)
        little.showWindow(nil)
        if url == nil { little.focusAddress() }
        DispatchQueue.main.async { interval.end() }
    }

    // MARK: - Arc import

    func offerArcImport() {
        guard let window else { return }
        settings.arcImportOffered = true
        let alert = NSAlert()
        alert.messageText = String(localized: "Bring over your Arc sidebar?", bundle: .chordUI)
        alert.informativeText = String(localized: "Chord found Arc on this Mac. Your Spaces, favorites and pinned tabs can come over as they are. Arc is left unchanged.", bundle: .chordUI)
        alert.addButton(withTitle: String(localized: "Import", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Later", bundle: .chordUI))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                self.importFromArc(nil)
            } else {
                self.newTab(nil)
            }
        }
    }

    // MARK: - Spaces

    func promptRename(_ space: Space) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Space", bundle: .chordUI)
        alert.addButton(withTitle: String(localized: "Rename", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
        let field = NSTextField(string: space.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.state.rename(space, to: field.stringValue)
        }
    }

    /// Any emoji for the Space, typed or picked from the Mac's emoji palette.
    func promptIcon(for space: Space) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Space Icon", bundle: .chordUI)
        alert.informativeText = String(localized: "Type an emoji, or press fn E (🌐 E) to pick one.", bundle: .chordUI)
        alert.addButton(withTitle: String(localized: "Choose", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
        let field = NSTextField(string: space.icon ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 80, height: 28)
        field.font = .systemFont(ofSize: 18)
        field.alignment = .center
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let text = field.stringValue
            self?.state.setIcon(space, icon: text.isEmpty ? nil : text)
        }
        DispatchQueue.main.async { NSApp.orderFrontCharacterPalette(field) }
    }

    func promptRename(_ folder: Folder) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Folder", bundle: .chordUI)
        alert.addButton(withTitle: String(localized: "Rename", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
        let field = NSTextField(string: folder.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.state.rename(folder, to: field.stringValue)
        }
    }

    func confirmDelete(_ folder: Folder) {
        guard let window else { return }
        let count = folder.tabs.count
        guard count > 0 else {
            state.delete(folder)
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete the folder “\(folder.name)”?", bundle: .chordUI)
        alert.informativeText = count == 1 ? String(localized: "Its tab will be closed.", bundle: .chordUI) : String(localized: "Its \(count) tabs will be closed. “Ungroup” keeps the tabs.", bundle: .chordUI)
        alert.addButton(withTitle: String(localized: "Delete", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.state.delete(folder)
        }
    }

    /// Asks first when tabs would close, or when the Space takes its profile with it.
    func confirmDelete(_ space: Space) {
        guard let window else { return }
        let count = space.allTabs.count
        let deletesProfile = state.isLastSpace(ofItsProfile: space)
        guard count > 0 || deletesProfile else {
            state.delete(space)
            return
        }
        var details: [String] = []
        if count > 0 { details.append(count == 1 ? String(localized: "Its tab will be closed.", bundle: .chordUI) : String(localized: "Its \(count) tabs will be closed.", bundle: .chordUI)) }
        if deletesProfile { details.append(BrowserState.profileDeletionWarning) }
        let alert = NSAlert()
        alert.messageText = deletesProfile
            ? String(localized: "Delete the Space “\(space.name)” and its profile?", bundle: .chordUI)
            : String(localized: "Delete the Space “\(space.name)”?", bundle: .chordUI)
        alert.informativeText = details.joined(separator: " ")
        alert.addButton(withTitle: String(localized: "Delete", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.state.delete(space)
        }
    }
}
