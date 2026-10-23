import AppKit

/// The command bar: ⌘T opens it for a new tab, ⌘L for the current one.
///
/// Its views are built once and then only shown and hidden, so that opening it
/// stays well under its 50 ms budget.
final class CommandBarController: NSObject, NSTextFieldDelegate {
    enum Mode {
        /// The result opens in a new tab.
        case newTab
        /// The result replaces the current page (⌘↩ still opens a new tab).
        case currentTab
        /// The result opens beside the current page, in a split view (⇧⌘D).
        case split
    }

    var actionsProvider: (() -> [CommandItem])?
    var onDismiss: (() -> Void)?
    private(set) var isVisible = false
    /// Translucent glass, or an opaque panel (the command bar theme setting).
    var isGlass = true {
        didSet { applyMaterial() }
    }

    private let state: BrowserState
    private let settings: ChordSettings
    private weak var host: NSView?
    private let scrim = ScrimView()
    private let panelHost = ShadowHostView()
    private let panel = NSVisualEffectView()
    private let field = NSTextField()
    private let results = NSStackView()
    private var items: [CommandItem] = []
    private var rows: [CommandRowView] = []
    private var selectedIndex = -1
    private var mode = Mode.newTab
    private var accent = NSColor.controlAccentColor

    private static let maxTabs = 6

    init(state: BrowserState, settings: ChordSettings) {
        self.state = state
        self.settings = settings
        super.init()
    }

    func present(in host: NSView, mode: Mode, text: String, accent: NSColor) {
        let interval = Perf.begin("commandbar.open")
        install(in: host)
        self.mode = mode
        self.accent = accent
        field.placeholderString = mode == .split ? "Page à afficher à côté" : "Rechercher ou saisir une adresse"
        field.stringValue = text
        scrim.isHidden = false
        panelHost.isHidden = false
        isVisible = true
        refresh()
        host.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        DispatchQueue.main.async { interval.end() }
    }

    func dismiss() {
        guard isVisible else { return }
        isVisible = false
        scrim.isHidden = true
        panelHost.isHidden = true
        onDismiss?()
    }

    // MARK: - Building (once)

    private func install(in host: NSView) {
        guard self.host !== host else { return }
        self.host = host

        scrim.onClick = { [weak self] in self?.dismiss() }

        panelHost.cornerRadius = 16
        panelHost.configureShadow(opacity: 0.22, radius: 30, offsetY: -12)

        applyMaterial()
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 16
        panel.layer?.masksToBounds = true
        panel.layer?.borderWidth = 0.5
        panel.layer?.borderColor = NSColor.separatorColor.cgColor

        let searchIcon = NSImageView(image: Theme.symbol("magnifyingglass", size: 17) ?? NSImage())
        searchIcon.contentTintColor = .secondaryLabelColor
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20)
        field.placeholderString = "Rechercher ou saisir une adresse"
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.delegate = self

        let header = NSStackView(views: [searchIcon, field])
        header.orientation = .horizontal
        header.spacing = 12
        header.edgeInsets = NSEdgeInsets(top: 0, left: 22, bottom: 0, right: 22)

        results.orientation = .vertical
        results.alignment = .width
        results.spacing = 0
        results.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        // Mockup: navigation hints on the left, "esc fermer" on the right.
        let hints = NSTextField(labelWithString: "↑ ↓ naviguer      ↩ ouvrir      ⌘↩ nouvel onglet")
        let escape = NSTextField(labelWithString: "esc fermer")
        let footer = NSView()
        for label in [hints, escape] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(label)
        }
        NSLayoutConstraint.activate([
            hints.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 22),
            hints.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            escape.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -22),
            escape.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])

        let column = NSStackView(views: [header, makeRule(), results, makeRule(), footer])
        column.orientation = .vertical
        column.alignment = .width
        column.spacing = 0

        for view in [scrim, panelHost] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(view)
        }
        panel.translatesAutoresizingMaskIntoConstraints = false
        column.translatesAutoresizingMaskIntoConstraints = false
        panelHost.addSubview(panel)
        panel.addSubview(column)

        NSLayoutConstraint.activate([
            scrim.topAnchor.constraint(equalTo: host.topAnchor),
            scrim.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: host.bottomAnchor),

            panelHost.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            panelHost.topAnchor.constraint(equalTo: host.topAnchor, constant: 140),
            panelHost.widthAnchor.constraint(equalToConstant: 680),

            panel.topAnchor.constraint(equalTo: panelHost.topAnchor),
            panel.leadingAnchor.constraint(equalTo: panelHost.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: panelHost.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: panelHost.bottomAnchor),

            column.topAnchor.constraint(equalTo: panel.topAnchor),
            column.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: panel.bottomAnchor),

            // Every row of the column spans the panel: a nested stack view would otherwise
            // shrink to its content and drift to one side.
            header.widthAnchor.constraint(equalTo: column.widthAnchor),
            results.widthAnchor.constraint(equalTo: column.widthAnchor),
            footer.widthAnchor.constraint(equalTo: column.widthAnchor),
            header.heightAnchor.constraint(equalToConstant: 60),
            footer.heightAnchor.constraint(equalToConstant: 36),
        ])

        scrim.isHidden = true
        panelHost.isHidden = true
    }

    private func applyMaterial() {
        panel.material = isGlass ? .popover : .windowBackground
    }

    // MARK: - Results

    private func refresh() {
        items = buildItems(query: field.stringValue)
        selectedIndex = items.isEmpty ? -1 : 0
        rebuildRows()
    }

    private func buildItems(query raw: String) -> [CommandItem] {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [CommandItem] = []

        let typedURL = URLInput.url(from: query)
        if let url = typedURL {
            result.append(CommandItem(section: "Aller à", title: url.absoluteString, tileURL: url, shortcut: "↩", action: .open(url)))
        }

        let tabs = state.allTabs.filter { entry in
            // A split takes pages of the active Space, other than the one already shown.
            if mode == .split, entry.space !== state.activeSpace || entry.tab === state.selectedTab { return false }
            guard !query.isEmpty else { return entry.space === state.activeSpace }
            return entry.tab.displayTitle.localizedStandardContains(query)
                || (entry.tab.url?.absoluteString.localizedStandardContains(query) ?? false)
        }
        let activeSpace = state.activeSpace
        for entry in tabs.prefix(Self.maxTabs) {
            let host = entry.tab.url?.host ?? ""
            let subtitle = entry.space === activeSpace ? host : "\(host) · \(entry.space.name)"
            result.append(CommandItem(section: "Onglets ouverts", title: entry.tab.displayTitle, subtitle: subtitle,
                                      tileURL: entry.tab.url, action: .switchTab(entry.tab)))
        }

        // Picking a page for a split: only pages, no actions.
        if mode != .split {
            let actions = (actionsProvider?() ?? []).filter { query.isEmpty || $0.title.localizedStandardContains(query) }
            result += actions.prefix(query.isEmpty ? 3 : 4)
        }

        if !query.isEmpty {
            result.append(CommandItem(section: "Rechercher", title: "« \(query) » sur le web", symbol: "magnifyingglass",
                                      action: .search(query)))
        }
        return result
    }

    private func rebuildRows() {
        results.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rows = []
        var currentSection: String?
        for (index, item) in items.enumerated() {
            if item.section != currentSection {
                currentSection = item.section
                addFullWidth(sectionLabel(item.section))
            }
            let row = CommandRowView(item: item)
            row.accent = accent
            row.onHover = { [weak self] in self?.select(index) }
            row.onClick = { [weak self] in self?.execute(index, forceNewTab: false) }
            addFullWidth(row)
            rows.append(row)
        }
        if items.isEmpty {
            addFullWidth(sectionLabel("Aucun résultat"))
        }
        updateSelection()
    }

    /// A stack view's .width alignment alone leaves rows at their fitting size, pushed
    /// to one side: pin each row to the list's width instead.
    private func addFullWidth(_ view: NSView) {
        results.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: results.widthAnchor, constant: -16).isActive = true
    }

    private func sectionLabel(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
        ])
        return container
    }

    private func select(_ index: Int) {
        guard items.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        updateSelection()
    }

    private func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = ((selectedIndex + delta) % items.count + items.count) % items.count
        updateSelection()
    }

    private func updateSelection() {
        for (index, row) in rows.enumerated() {
            row.isSelected = index == selectedIndex
        }
    }

    private func execute(_ index: Int, forceNewTab: Bool) {
        guard items.indices.contains(index) else { return }
        let item = items[index]
        dismiss()
        switch item.action {
        case .switchTab(let tab):
            if mode == .split { state.addToSplit(tab) } else { state.select(tab) }
        case .open(let url):
            open(url, forceNewTab: forceNewTab)
        case .search(let query):
            if let url = settings.searchURL(for: query) { open(url, forceNewTab: forceNewTab) }
        case .run(let block):
            block()
        }
    }

    private func open(_ url: URL, forceNewTab: Bool) {
        if mode == .split {
            state.addToSplit(state.openTab(url: url, select: false))
        } else if mode == .newTab || forceNewTab || state.selectedTab == nil {
            state.openTab(url: url)
        } else {
            state.navigateSelected(to: url)
        }
    }

    // MARK: - Keyboard

    func controlTextDidChange(_ obj: Notification) {
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(-1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            execute(selectedIndex, forceNewTab: NSApp.currentEvent?.modifierFlags.contains(.command) ?? false)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
            return true
        default:
            // ⌘↩ may arrive as `noop:` rather than `insertNewline:`.
            if commandSelector == NSSelectorFromString("noop:"), NSApp.currentEvent?.keyCode == 36 {
                execute(selectedIndex, forceNewTab: true)
                return true
            }
            return false
        }
    }
}
