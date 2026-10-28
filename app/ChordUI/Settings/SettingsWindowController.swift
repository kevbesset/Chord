import AppKit
import Combine
import SwiftUI

/// The settings window (⌘,). SwiftUI is fine here: it is off the critical path.
final class SettingsWindowController: NSWindowController {
    private let model: SettingsModel

    init(state: BrowserState, settings: ChordSettings, onImportArc: @escaping () -> Void, onImportBrowser: @escaping () -> Void) {
        model = SettingsModel(state: state, settings: settings, onImportArc: onImportArc, onImportBrowser: onImportBrowser)
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Settings", bundle: .chordUI)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.tabbingMode = .disallowed
        window.isRestorable = false
        window.setContentSize(NSSize(width: 620, height: 480))
        window.center()
        super.init(window: window)
        // A shortcut being recorded stops when the window is left: the key monitor
        // must not take keys typed elsewhere.
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak model] _ in
                model?.stopRecording()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Bridges ChordSettings and BrowserState to SwiftUI: any change redraws the panes.
final class SettingsModel: ObservableObject {
    let state: BrowserState
    let settings: ChordSettings
    let onImportArc: () -> Void
    let onImportBrowser: () -> Void
    @Published private(set) var revision = 0
    /// The shortcut being recorded, if any.
    @Published private(set) var recordingID: String?
    fileprivate var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(state: BrowserState, settings: ChordSettings, onImportArc: @escaping () -> Void, onImportBrowser: @escaping () -> Void) {
        self.state = state
        self.settings = settings
        self.onImportArc = onImportArc
        self.onImportBrowser = onImportBrowser
        settings.changes.sink { [weak self] _ in self?.revision += 1 }.store(in: &cancellables)
        state.changes.filter { $0 == .spaces || $0 == .activeSpace }
            .sink { [weak self] _ in self?.revision += 1 }
            .store(in: &cancellables)
    }

    func binding<Value>(_ keyPath: ReferenceWritableKeyPath<ChordSettings, Value>) -> Binding<Value> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { self.settings[keyPath: keyPath] = $0 })
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            GeneralPane(model: model).tabItem { Label(String(localized: "General", bundle: .chordUI), systemImage: "gearshape") }
            AppearancePane(model: model).tabItem { Label(String(localized: "Appearance", bundle: .chordUI), systemImage: "paintbrush") }
            SpacesPane(model: model).tabItem { Label(String(localized: "Spaces", bundle: .chordUI), systemImage: "square.stack") }
            ShortcutsPane(model: model).tabItem { Label(String(localized: "Shortcuts", bundle: .chordUI), systemImage: "command") }
        }
        .padding(20)
        .frame(width: 620, height: 480)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmingReset = false
    @State private var isDefaultBrowser = DefaultBrowser.isChord
    @State private var otherBrowser = DefaultBrowser.currentName
    @State private var askingDefault = false

    static let engines: [(String, String)] = [
        ("DuckDuckGo", "https://duckduckgo.com/?q=%s"),
        ("Google", "https://www.google.com/search?q=%s"),
        ("Bing", "https://www.bing.com/search?q=%s"),
        ("Ecosia", "https://www.ecosia.org/search?q=%s"),
        ("Qwant", "https://www.qwant.com/?q=%s"),
        ("Startpage", "https://www.startpage.com/sp/search?query=%s"),
        ("Brave Search", "https://search.brave.com/search?q=%s"),
        ("Kagi", "https://kagi.com/search?q=%s"),
    ]

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Default browser", bundle: .chordUI))
                        Text(isDefaultBrowser
                             ? String(localized: "Links opened from other apps open in Chord.", bundle: .chordUI)
                             : otherBrowser.map { String(localized: "Links opened from other apps open in \($0).", bundle: .chordUI) }
                                ?? String(localized: "Links opened from other apps open in another browser.", bundle: .chordUI))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isDefaultBrowser {
                        Label(String(localized: "Chord is your default browser", bundle: .chordUI), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button(String(localized: "Make Default", bundle: .chordUI)) {
                            askingDefault = true
                            DefaultBrowser.makeChord { _ in
                                askingDefault = false
                                refreshDefaultBrowser()
                            }
                        }
                        .disabled(askingDefault)
                    }
                }
            }
            Picker(String(localized: "Search engine", bundle: .chordUI), selection: model.binding(\.searchTemplate)) {
                ForEach(Self.engines, id: \.1) { engine in Text(engine.0).tag(engine.1) }
                if !Self.engines.contains(where: { $0.1 == model.settings.searchTemplate }) {
                    Text(String(localized: "Custom", bundle: .chordUI)).tag(model.settings.searchTemplate)
                }
            }
            Picker(selection: model.binding(\.archiveAfter)) {
                ForEach(ChordSettings.ArchiveDelay.allCases, id: \.self) { delay in Text(delay.title).tag(delay) }
            } label: {
                Text(String(localized: "Archive today's tabs", bundle: .chordUI))
                Text(String(localized: "Tabs left unused this long go to the archive (⌥⌘A), like Arc. Pinned tabs and favorites stay.", bundle: .chordUI))
            }
            Toggle(isOn: model.binding(\.autoPictureInPicture)) {
                Text(String(localized: "Automatic picture in picture", bundle: .chordUI))
                Text(String(localized: "A playing video carries on in a floating window when you switch tabs or Spaces, and goes back to its page when you return.", bundle: .chordUI))
            }
            Toggle(isOn: model.binding(\.confirmQuit)) {
                Text(String(localized: "Ask before quitting", bundle: .chordUI))
                Text(String(localized: "⌘Q asks first, like Arc.", bundle: .chordUI))
            }
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Import from Arc", bundle: .chordUI))
                        Text(String(localized: "Spaces, favorites and pinned tabs, as they are.", bundle: .chordUI))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "Import…", bundle: .chordUI)) { model.onImportArc() }
                        .disabled(!ArcImport.isAvailable)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Import from another browser", bundle: .chordUI))
                        Text(String(localized: "Google Chrome, Brave, Edge, Vivaldi or Safari: bookmarks, logins, passwords and history.", bundle: .chordUI))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "Import…", bundle: .chordUI)) { model.onImportBrowser() }
                        .disabled(BrowserImport.installed.isEmpty)
                }
            }
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Reset Chord", bundle: .chordUI))
                        Text(String(localized: "Deletes everything Chord keeps on this Mac and starts it again as new.", bundle: .chordUI))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "Reset…", bundle: .chordUI), role: .destructive) { confirmingReset = true }
                        .disabled(model.state.engine.resetAllDataAndRelaunch == nil)
                }
            }
        }
        .formStyle(.grouped)
        // The default can change in System Settings or another browser while this is open.
        .onAppear(perform: refreshDefaultBrowser)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshDefaultBrowser()
        }
        .confirmationDialog(String(localized: "Reset Chord?", bundle: .chordUI), isPresented: $confirmingReset) {
            Button(String(localized: "Reset and Restart", bundle: .chordUI), role: .destructive) {
                model.state.engine.resetAllDataAndRelaunch?()
            }
            Button(String(localized: "Cancel", bundle: .chordUI), role: .cancel) {}
        } message: {
            Text(String(localized: "Spaces, tabs, favorites, logins, passwords, history, extensions and settings are deleted, and Chord restarts as on its first launch. Your downloaded files stay. This cannot be undone.", bundle: .chordUI))
        }
    }

    private func refreshDefaultBrowser() {
        isDefaultBrowser = DefaultBrowser.isChord
        otherBrowser = DefaultBrowser.currentName
    }
}

// MARK: - Apparence

private struct AppearancePane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Picker(String(localized: "Mode", bundle: .chordUI), selection: model.binding(\.appearance)) {
                Text(String(localized: "Automatic", bundle: .chordUI)).tag(ChordSettings.Appearance.automatic)
                Text(String(localized: "Light", bundle: .chordUI)).tag(ChordSettings.Appearance.light)
                Text(String(localized: "Dark", bundle: .chordUI)).tag(ChordSettings.Appearance.dark)
            }
            .pickerStyle(.segmented)
            // Each profile can choose its own place (⇧⌘D in a Space); this is the rest's.
            Picker(selection: model.binding(\.addressBarOnTop)) {
                Text(String(localized: "In the sidebar", bundle: .chordUI)).tag(false)
                Text(String(localized: "Above the page", bundle: .chordUI)).tag(true)
            } label: {
                Text(String(localized: "Default address bar", bundle: .chordUI))
                Text(String(localized: "For Spaces whose profile has not chosen its own.", bundle: .chordUI))
            }
            Toggle(String(localized: "Edgeless: the page touches the window's edges", bundle: .chordUI), isOn: model.binding(\.edgeless))
            LabeledContent(String(localized: "Sidebar width", bundle: .chordUI)) {
                Slider(value: Binding(get: { Double(model.settings.sidebarWidth) },
                                      set: { model.settings.sidebarWidth = CGFloat($0).rounded() }),
                       in: Double(ChordSettings.sidebarWidthRange.lowerBound)...Double(ChordSettings.sidebarWidthRange.upperBound))
                    .frame(width: 220)
            }
            Picker(String(localized: "Command bar", bundle: .chordUI), selection: model.binding(\.commandBarGlass)) {
                Text(String(localized: "Glass", bundle: .chordUI)).tag(true)
                Text(String(localized: "Opaque", bundle: .chordUI)).tag(false)
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Spaces

private struct SpacesPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let _ = model.revision
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach(model.state.spaces, id: \.id) { space in
                    SpaceRow(model: model, space: space)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: false))
            HStack {
                Button(String(localized: "New Space", bundle: .chordUI)) { model.state.addSpace() }
                Spacer()
                Text(String(localized: "Spaces on the same profile share their favorites and their session.", bundle: .chordUI))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SpaceRow: View {
    private static let separate = "separate"
    @ObservedObject var model: SettingsModel
    let space: Space
    @State private var name = ""
    /// A profile change that would delete the Space's current profile, waiting for a yes.
    @State private var pendingProfile: String?
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                // An imported Arc colour outside the palette stays visible and selected.
                ForEach(Theme.spacePalette.contains(space.colorHex) ? Theme.spacePalette : [space.colorHex] + Theme.spacePalette, id: \.self) { hex in
                    Circle()
                        .fill(Color(nsColor: NSColor(hex: hex)))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.primary.opacity(hex == space.colorHex ? 0.8 : 0), lineWidth: 2).padding(-3))
                        .onTapGesture { model.state.setColor(space, hex: hex) }
                        .accessibilityLabel(Theme.colorName(hex))
                        .accessibilityAddTraits(.isButton)
                }
            }
            Menu(space.icon ?? "∅") {
                ForEach(Space.suggestedIcons, id: \.self) { icon in
                    Button(icon) { model.state.setIcon(space, icon: icon) }
                }
                Divider()
                Button(String(localized: "No Icon", bundle: .chordUI)) { model.state.setIcon(space, icon: nil) }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(String(localized: "Space Icon", bundle: .chordUI))
            TextField(String(localized: "Name", bundle: .chordUI), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.state.rename(space, to: name) }
                .onAppear { name = space.name }
            // Like Arc's profiles: Spaces in the same profile share their favorites and
            // their session (logins, cookies, extensions).
            Picker(String(localized: "Profile", bundle: .chordUI), selection: Binding(
                get: { space.profileID },
                set: { choice in
                    let profile = choice == Self.separate ? UUID().uuidString : choice
                    if model.state.isLastSpace(ofItsProfile: space) {
                        pendingProfile = profile
                    } else {
                        model.state.setProfile(space, to: profile)
                    }
                }
            )) {
                ForEach(model.state.profiles, id: \.id) { profile in
                    Text(profile.spaces.map(\.name).joined(separator: ", ")).tag(profile.id)
                }
                Divider()
                Text(String(localized: "New profile", bundle: .chordUI)).tag(Self.separate)
            }
            .labelsHidden()
            .frame(width: 150)
            .help(String(localized: "Spaces on the same profile share their favorites and their session (logins, cookies, extensions), like Arc's profiles.", bundle: .chordUI))
            Button(role: .destructive) {
                if model.state.isLastSpace(ofItsProfile: space) || !space.allTabs.isEmpty {
                    confirmingDelete = true
                } else {
                    model.state.delete(space)
                }
            } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(model.state.spaces.count < 2)
                .help(String(localized: "Delete the Space and its tabs", bundle: .chordUI))
        }
        .padding(.vertical, 4)
        .alert(String(localized: "Change the profile of “\(space.name)”?", bundle: .chordUI), isPresented: Binding(
            get: { pendingProfile != nil },
            set: { if !$0 { pendingProfile = nil } }
        )) {
            Button(String(localized: "Change and Delete the Old Profile", bundle: .chordUI), role: .destructive) {
                if let profile = pendingProfile { model.state.setProfile(space, to: profile) }
                pendingProfile = nil
            }
            Button(String(localized: "Cancel", bundle: .chordUI), role: .cancel) { pendingProfile = nil }
        } message: {
            Text(String(localized: "No other Space uses its current profile: it will be deleted, with its logins, cookies, history, extensions and favorites.", bundle: .chordUI))
        }
        .alert(model.state.isLastSpace(ofItsProfile: space)
               ? String(localized: "Delete the Space “\(space.name)” and its profile?", bundle: .chordUI)
               : String(localized: "Delete the Space “\(space.name)”?", bundle: .chordUI), isPresented: $confirmingDelete) {
            Button(String(localized: "Delete", bundle: .chordUI), role: .destructive) { model.state.delete(space) }
            Button(String(localized: "Cancel", bundle: .chordUI), role: .cancel) {}
        } message: {
            Text(deleteDetails)
        }
    }

    private var deleteDetails: String {
        var details: [String] = []
        let count = space.allTabs.count
        if count > 0 { details.append(count == 1 ? String(localized: "Its tab will be closed.", bundle: .chordUI) : String(localized: "Its \(count) tabs will be closed.", bundle: .chordUI)) }
        if model.state.isLastSpace(ofItsProfile: space) { details.append(BrowserState.profileDeletionWarning) }
        return details.joined(separator: " ")
    }
}

// MARK: - Raccourcis

private struct ShortcutsPane: View {
    @ObservedObject var model: SettingsModel
    @State private var search = ""
    @State private var confirmingReset = false

    var body: some View {
        let _ = model.revision
        let overrides = model.settings.shortcutOverrides
        let items = MainMenu.remappableItems(in: NSApp.mainMenu).filter { entry in
            ShortcutSearch.matches(search, title: entry.title, menu: entry.menu,
                                   shortcut: MainMenu.currentShortcut(for: entry.id, in: NSApp.mainMenu))
        }
        let menus = items.reduce(into: [String]()) { if !$0.contains($1.menu) { $0.append($1.menu) } }
        VStack(alignment: .leading, spacing: 10) {
            TextField(String(localized: "Search a command or a shortcut (⌘T, cmd shift c…)", bundle: .chordUI), text: $search)
                .textFieldStyle(.roundedBorder)
            List {
                ForEach(menus, id: \.self) { menu in
                    Section(menu) {
                        ForEach(items.filter { $0.menu == menu }, id: \.id) { entry in
                            let modified = overrides[entry.id] != nil
                            HStack {
                                Text(entry.title)
                                if modified {
                                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                        .help(String(localized: "Changed", bundle: .chordUI))
                                }
                                Spacer()
                                ShortcutField(model: model, id: entry.id, title: entry.title)
                                Button {
                                    model.setShortcut(nil, for: entry.id)
                                } label: { Image(systemName: "arrow.uturn.backward") }
                                    .buttonStyle(.borderless)
                                    .help(String(localized: "Restore \(MainMenu.defaultShortcut(for: entry.id)?.display ?? "—")", bundle: .chordUI))
                                    .disabled(!modified)
                            }
                        }
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Click a shortcut, then type the new combination. ⌫ removes it, esc cancels.", bundle: .chordUI))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Reset All Shortcuts…", bundle: .chordUI)) { confirmingReset = true }
                    .disabled(overrides.isEmpty)
            }
        }
        .onDisappear { model.stopRecording() }
        .confirmationDialog(String(localized: "Reset all shortcuts?", bundle: .chordUI), isPresented: $confirmingReset) {
            Button(String(localized: "Reset", bundle: .chordUI), role: .destructive) { model.settings.shortcutOverrides = [:] }
            Button(String(localized: "Cancel", bundle: .chordUI), role: .cancel) {}
        } message: {
            Text(overrides.count == 1
                 ? String(localized: "Every command gets its original shortcut back. Your change will be lost.", bundle: .chordUI)
                 : String(localized: "Every command gets its original shortcut back. Your \(overrides.count) changes will be lost.", bundle: .chordUI))
        }
    }
}

extension SettingsModel {
    /// Starts listening for the next key combination, for the item `id`. A key monitor
    /// sees it before the menu does, so that recording ⌘T does not open a tab.
    func startRecording(_ id: String, title: String) {
        stopRecording()
        recordingID = id
        let window = NSApp.keyWindow
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            // Only what happens in the settings window.
            guard event.window === window else {
                self.stopRecording()
                return event
            }
            if event.type == .leftMouseDown {
                // A click elsewhere ends the recording (a click on another shortcut starts its own).
                self.stopRecording()
                return event
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            switch event.keyCode {
            case 53: // esc
                self.stopRecording()
            case 51 where modifiers.isEmpty: // backspace: no shortcut
                self.stopRecording()
                self.setShortcut(MainMenu.Shortcut(key: "", modifiers: []), for: id)
            default:
                guard !modifiers.subtracting(.shift).isEmpty,
                      let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else {
                    NSSound.beep()
                    return nil
                }
                self.stopRecording()
                self.record(MainMenu.Shortcut(key: key, modifiers: modifiers), for: id, title: title, in: window)
            }
            return nil
        }
    }

    func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if recordingID != nil { recordingID = nil }
    }

    /// Sets the shortcut of the item `id`; nil goes back to its default. A default is
    /// stored as no override, so that resetting and re-recording it look the same.
    func setShortcut(_ shortcut: MainMenu.Shortcut?, for id: String) {
        var overrides = settings.shortcutOverrides
        if let shortcut, shortcut != MainMenu.defaultShortcut(for: id) {
            overrides[id] = shortcut.stored
        } else {
            overrides[id] = nil
        }
        settings.shortcutOverrides = overrides
    }

    /// Records `shortcut` for `id`. If another command has it, offers to take it from
    /// that command, which is left without one; a reserved shortcut (⌘C, ⌘Q…) stays put.
    func record(_ shortcut: MainMenu.Shortcut, for id: String, title: String, in window: NSWindow?) {
        guard let owner = MainMenu.owner(of: shortcut, besides: id, in: NSApp.mainMenu) else {
            setShortcut(shortcut, for: id)
            return
        }
        let alert = NSAlert()
        if owner.reserved {
            alert.messageText = String(localized: "\(shortcut.display) is reserved for “\(owner.title)”", bundle: .chordUI)
            alert.informativeText = String(localized: "Every Mac app shares this shortcut. Choose another one for “\(title)”.", bundle: .chordUI)
            alert.addButton(withTitle: "OK")
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        alert.messageText = String(localized: "\(shortcut.display) is already used by “\(owner.title)”", bundle: .chordUI)
        alert.informativeText = String(localized: "Give it to “\(title)”? “\(owner.title)” will no longer have a shortcut.", bundle: .chordUI)
        alert.addButton(withTitle: String(localized: "Replace", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
        let apply: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            var overrides = self.settings.shortcutOverrides
            overrides[owner.id] = MainMenu.Shortcut(key: "", modifiers: []).stored
            if shortcut != MainMenu.defaultShortcut(for: id) { overrides[id] = shortcut.stored } else { overrides[id] = nil }
            self.settings.shortcutOverrides = overrides
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: apply) } else { apply(alert.runModal()) }
    }
}

/// A command's shortcut: click it, then type the new combination.
private struct ShortcutField: View {
    @ObservedObject var model: SettingsModel
    let id: String
    let title: String

    var body: some View {
        let _ = model.revision
        let recording = model.recordingID == id
        let shortcut = MainMenu.currentShortcut(for: id, in: NSApp.mainMenu)
        Button {
            if recording { model.stopRecording() } else { model.startRecording(id, title: title) }
        } label: {
            Text(recording ? String(localized: "Type…", bundle: .chordUI) : (shortcut?.display ?? "—"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(recording ? Color.accentColor : Color.primary)
                .frame(width: 104, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(recording ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(recording ? Color.accentColor : Color(nsColor: .separatorColor))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(recording ? String(localized: "Type the combination, ⌫ to remove it, esc to cancel", bundle: .chordUI) : String(localized: "Change shortcut", bundle: .chordUI))
    }
}

/// Searching the shortcuts by command, by menu, or by the keys themselves: "⌘T",
/// "cmd t", "shift cmd c", "ctrl tab", and the key names of the interface's languages
/// ("maj cmd c", "mayús cmd c").
enum ShortcutSearch {
    private static let words: [String: String] = {
        let space = MainMenu.spaceKeyName.uppercased()
        return [
            "cmd": "⌘", "command": "⌘", "commande": "⌘", "comando": "⌘",
            "shift": "⇧", "maj": "⇧", "majuscule": "⇧", "mayús": "⇧", "mayúsculas": "⇧",
            "opt": "⌥", "option": "⌥", "opción": "⌥", "alt": "⌥",
            "ctrl": "⌃", "control": "⌃", "contrôle": "⌃",
            "tab": "⇥", "return": "↩", "enter": "↩", "entrée": "↩", "intro": "↩", "esc": "⎋",
            "space": space, "espace": space, "espacio": space,
            "left": "←", "gauche": "←", "izquierda": "←", "right": "→", "droite": "→", "derecha": "→",
            "up": "↑", "haut": "↑", "arriba": "↑", "down": "↓", "bas": "↓", "abajo": "↓",
        ]
    }()

    static func matches(_ query: String, title: String, menu: String, shortcut: MainMenu.Shortcut?) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        if title.localizedCaseInsensitiveContains(query) || menu.localizedCaseInsensitiveContains(query) { return true }
        guard let display = shortcut?.display, display != "—" else { return false }
        // Every part of the query names a key of the shortcut: "⇧⌘C" splits into ⇧, ⌘, C.
        let keys = parts(of: display)
        let wanted = query.lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "+" || $0 == "-" })
            .flatMap { token -> [String] in
                if let symbol = words[String(token)] { return [symbol] }
                return parts(of: String(token).uppercased())
            }
        return !wanted.isEmpty && wanted.allSatisfy { keys.contains($0) }
    }

    /// "⇧⌘C" → ["⇧", "⌘", "C"]; "⌃Space" → ["⌃", "SPACE"].
    private static func parts(of display: String) -> [String] {
        var result: [String] = []
        var rest = Substring(display)
        while let first = rest.first, "⌃⌥⇧⌘".contains(first) {
            result.append(String(first))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty { result.append(rest.uppercased()) }
        return result
    }
}
