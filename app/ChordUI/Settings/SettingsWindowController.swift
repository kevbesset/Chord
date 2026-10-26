import AppKit
import Combine
import SwiftUI

/// The settings window (⌘,). SwiftUI is fine here: it is off the critical path.
final class SettingsWindowController: NSWindowController {
    private let model: SettingsModel

    init(state: BrowserState, settings: ChordSettings, onImportArc: @escaping () -> Void) {
        model = SettingsModel(state: state, settings: settings, onImportArc: onImportArc)
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Réglages"
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
    @Published private(set) var revision = 0
    /// The shortcut being recorded, if any.
    @Published private(set) var recordingID: String?
    fileprivate var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    init(state: BrowserState, settings: ChordSettings, onImportArc: @escaping () -> Void) {
        self.state = state
        self.settings = settings
        self.onImportArc = onImportArc
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
            GeneralPane(model: model).tabItem { Label("Général", systemImage: "gearshape") }
            AppearancePane(model: model).tabItem { Label("Apparence", systemImage: "paintbrush") }
            SpacesPane(model: model).tabItem { Label("Spaces", systemImage: "square.stack") }
            ShortcutsPane(model: model).tabItem { Label("Raccourcis", systemImage: "command") }
        }
        .padding(20)
        .frame(width: 620, height: 480)
    }
}

// MARK: - Général

private struct GeneralPane: View {
    @ObservedObject var model: SettingsModel

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
            Picker("Moteur de recherche", selection: model.binding(\.searchTemplate)) {
                ForEach(Self.engines, id: \.1) { engine in Text(engine.0).tag(engine.1) }
                if !Self.engines.contains(where: { $0.1 == model.settings.searchTemplate }) {
                    Text("Personnalisé").tag(model.settings.searchTemplate)
                }
            }
            Toggle(isOn: model.binding(\.autoPictureInPicture)) {
                Text("Picture-in-picture automatique")
                Text("Une vidéo en lecture continue dans une fenêtre flottante quand vous changez d'onglet ou de Space, et revient dans sa page à votre retour.")
            }
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Importer depuis Arc")
                        Text("Spaces, favoris et onglets épinglés, tels quels.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Importer…") { model.onImportArc() }
                        .disabled(!ArcImport.isAvailable)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Apparence

private struct AppearancePane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Picker("Mode", selection: model.binding(\.appearance)) {
                Text("Automatique").tag(ChordSettings.Appearance.automatic)
                Text("Clair").tag(ChordSettings.Appearance.light)
                Text("Sombre").tag(ChordSettings.Appearance.dark)
            }
            .pickerStyle(.segmented)
            Picker("Barre d'adresse", selection: model.binding(\.addressBarOnTop)) {
                Text("Dans la barre latérale").tag(false)
                Text("En haut de la page").tag(true)
            }
            Toggle("Edgeless : la page touche les bords de la fenêtre", isOn: model.binding(\.edgeless))
            LabeledContent("Largeur de la barre latérale") {
                Slider(value: Binding(get: { Double(model.settings.sidebarWidth) },
                                      set: { model.settings.sidebarWidth = CGFloat($0).rounded() }),
                       in: Double(ChordSettings.sidebarWidthRange.lowerBound)...Double(ChordSettings.sidebarWidthRange.upperBound))
                    .frame(width: 220)
            }
            Picker("Barre de commande", selection: model.binding(\.commandBarGlass)) {
                Text("Verre").tag(true)
                Text("Opaque").tag(false)
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
                Button("Nouveau Space") { model.state.addSpace() }
                Spacer()
                Text("Les Spaces d'un même profil partagent leurs favoris et leur session.")
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
            TextField("Nom", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.state.rename(space, to: name) }
                .onAppear { name = space.name }
            // Like Arc's profiles: Spaces in the same profile share their favorites and
            // their session (logins, cookies, extensions).
            Picker("Profil", selection: Binding(
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
                Text("Nouveau profil").tag(Self.separate)
            }
            .labelsHidden()
            .frame(width: 150)
            .help("Les Spaces d'un même profil partagent leurs favoris et leur session (connexions, cookies, extensions), comme les profils d'Arc.")
            Button(role: .destructive) {
                if model.state.isLastSpace(ofItsProfile: space) || !space.allTabs.isEmpty {
                    confirmingDelete = true
                } else {
                    model.state.delete(space)
                }
            } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(model.state.spaces.count < 2)
                .help("Supprimer le Space et ses onglets")
        }
        .padding(.vertical, 4)
        .alert("Changer le profil de « \(space.name) » ?", isPresented: Binding(
            get: { pendingProfile != nil },
            set: { if !$0 { pendingProfile = nil } }
        )) {
            Button("Changer et supprimer l'ancien profil", role: .destructive) {
                if let profile = pendingProfile { model.state.setProfile(space, to: profile) }
                pendingProfile = nil
            }
            Button("Annuler", role: .cancel) { pendingProfile = nil }
        } message: {
            Text("Aucun autre Space n'utilise son profil actuel : il sera supprimé, avec ses connexions, cookies, historique, extensions et favoris.")
        }
        .alert(model.state.isLastSpace(ofItsProfile: space)
               ? "Supprimer le Space « \(space.name) » et son profil ?"
               : "Supprimer le Space « \(space.name) » ?", isPresented: $confirmingDelete) {
            Button("Supprimer", role: .destructive) { model.state.delete(space) }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(deleteDetails)
        }
    }

    private var deleteDetails: String {
        var details: [String] = []
        let count = space.allTabs.count
        if count > 0 { details.append(count == 1 ? "Son onglet sera fermé." : "Ses \(count) onglets seront fermés.") }
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
            TextField("Rechercher une commande ou un raccourci (⌘T, cmd maj c…)", text: $search)
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
                                        .help("Modifié")
                                }
                                Spacer()
                                ShortcutField(model: model, id: entry.id, title: entry.title)
                                Button {
                                    model.setShortcut(nil, for: entry.id)
                                } label: { Image(systemName: "arrow.uturn.backward") }
                                    .buttonStyle(.borderless)
                                    .help("Rétablir \(MainMenu.defaultShortcut(for: entry.id)?.display ?? "—")")
                                    .disabled(!modified)
                            }
                        }
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Cliquez sur un raccourci puis tapez la nouvelle combinaison. ⌫ le retire, esc annule.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Réinitialiser tous les raccourcis…") { confirmingReset = true }
                    .disabled(overrides.isEmpty)
            }
        }
        .onDisappear { model.stopRecording() }
        .confirmationDialog("Réinitialiser tous les raccourcis ?", isPresented: $confirmingReset) {
            Button("Réinitialiser", role: .destructive) { model.settings.shortcutOverrides = [:] }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Chaque commande retrouve son raccourci d'origine. Vos \(overrides.count) modification\(overrides.count > 1 ? "s" : "") seront perdue\(overrides.count > 1 ? "s" : "").")
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
            alert.messageText = "\(shortcut.display) est réservé à « \(owner.title) »"
            alert.informativeText = "Ce raccourci est commun à toutes les apps du Mac. Choisissez-en un autre pour « \(title) »."
            alert.addButton(withTitle: "OK")
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        alert.messageText = "\(shortcut.display) est déjà utilisé par « \(owner.title) »"
        alert.informativeText = "Le donner à « \(title) » ? « \(owner.title) » n'aura plus de raccourci."
        alert.addButton(withTitle: "Remplacer")
        alert.addButton(withTitle: "Annuler")
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
            Text(recording ? "Tapez…" : (shortcut?.display ?? "—"))
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
        .help(recording ? "Tapez la combinaison, ⌫ pour la retirer, esc pour annuler" : "Changer le raccourci")
    }
}

/// Searching the shortcuts by command, by menu, or by the keys themselves: "⌘T",
/// "cmd t", "maj cmd c", "ctrl tab".
enum ShortcutSearch {
    private static let words: [String: String] = [
        "cmd": "⌘", "command": "⌘", "commande": "⌘",
        "shift": "⇧", "maj": "⇧", "majuscule": "⇧",
        "opt": "⌥", "option": "⌥", "alt": "⌥",
        "ctrl": "⌃", "control": "⌃", "contrôle": "⌃",
        "tab": "⇥", "return": "↩", "enter": "↩", "esc": "⎋", "space": "Espace", "espace": "Espace",
        "left": "←", "gauche": "←", "right": "→", "droite": "→", "up": "↑", "haut": "↑", "down": "↓", "bas": "↓",
    ]

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

    /// "⇧⌘C" → ["⇧", "⌘", "C"]; "⌃Espace" → ["⌃", "ESPACE"].
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
