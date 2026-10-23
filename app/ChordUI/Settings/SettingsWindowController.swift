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
        window.setContentSize(NSSize(width: 620, height: 480))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Bridges ChordSettings and BrowserState to SwiftUI: any change redraws the panes.
final class SettingsModel: ObservableObject {
    let state: BrowserState
    let settings: ChordSettings
    let onImportArc: () -> Void
    @Published private(set) var revision = 0
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
                Text("Les Spaces d'un même groupe de favoris les partagent.")
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
            // Like Arc's profiles: Spaces in the same group share their favorites.
            Picker("Favoris", selection: Binding(
                get: { space.profileID },
                set: { model.state.setProfile(space, to: $0 == Self.separate ? UUID().uuidString : $0) }
            )) {
                ForEach(model.state.profiles, id: \.id) { profile in
                    Text(profile.spaces.map(\.name).joined(separator: ", ")).tag(profile.id)
                }
                Divider()
                Text("Favoris à part").tag(Self.separate)
            }
            .labelsHidden()
            .frame(width: 150)
            .help("Les Spaces d'un même groupe partagent leurs favoris, comme les profils d'Arc.")
            Button(role: .destructive) { model.state.delete(space) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(model.state.spaces.count < 2)
                .help("Supprimer le Space et ses onglets")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Raccourcis

private struct ShortcutsPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let _ = model.revision
        let items = MainMenu.remappableItems(in: NSApp.mainMenu)
        VStack(alignment: .leading, spacing: 10) {
            List {
                ForEach(Array(Dictionary(grouping: items, by: \.menu).sorted { lhs, rhs in
                    (items.firstIndex { $0.menu == lhs.key } ?? 0) < (items.firstIndex { $0.menu == rhs.key } ?? 0)
                }), id: \.key) { group in
                    Section(group.key) {
                        ForEach(group.value, id: \.id) { entry in
                            HStack {
                                Text(entry.title)
                                Spacer()
                                ShortcutRecorder(model: model, id: entry.id)
                                    .frame(width: 120, height: 22)
                                Button {
                                    var overrides = model.settings.shortcutOverrides
                                    overrides[entry.id] = nil
                                    model.settings.shortcutOverrides = overrides
                                } label: { Image(systemName: "arrow.uturn.backward") }
                                    .buttonStyle(.borderless)
                                    .help("Rétablir le raccourci par défaut")
                                    .disabled(model.settings.shortcutOverrides[entry.id] == nil)
                            }
                        }
                    }
                }
            }
            Text("Cliquez sur un raccourci puis tapez la nouvelle combinaison. ⌫ le retire, esc annule.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Click, then type a key combination. Backspace removes the shortcut, Escape cancels.
private struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var model: SettingsModel
    let id: String

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.onRecord = { shortcut in
            var overrides = model.settings.shortcutOverrides
            overrides[id] = shortcut.stored
            model.settings.shortcutOverrides = overrides
        }
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        _ = model.revision
        view.shortcut = MainMenu.currentShortcut(for: id, in: NSApp.mainMenu)
    }
}

final class ShortcutRecorderView: NSView {
    var onRecord: ((MainMenu.Shortcut) -> Void)?
    var shortcut: MainMenu.Shortcut? { didSet { label.stringValue = shortcut?.display ?? "—" } }
    private let label = NSTextField(labelWithString: "—")
    private var isRecording = false { didSet { refresh() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 53 { // esc
            isRecording = false
            return
        }
        if event.keyCode == 51, modifiers.isEmpty { // backspace
            onRecord?(MainMenu.Shortcut(key: "", modifiers: []))
            isRecording = false
            return
        }
        guard !modifiers.subtracting(.shift).isEmpty, let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else {
            NSSound.beep()
            return
        }
        onRecord?(MainMenu.Shortcut(key: key, modifiers: modifiers))
        isRecording = false
    }

    private func refresh() {
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).cgColor
        label.stringValue = isRecording ? "Tapez…" : (shortcut?.display ?? "—")
        label.textColor = isRecording ? .controlAccentColor : .labelColor
    }
}
