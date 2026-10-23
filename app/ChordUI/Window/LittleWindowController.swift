import AppKit

/// The little window (Little Arc): a small glass window for a link opened from another
/// app, or ⌥⌘N. "Ouvrir dans Chord" (⌘O) moves the page into the main window as a tab.
final class LittleWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, ChordWebPageDelegate {
    var onOpenInChord: ((ChordWebPage) -> Void)?
    var onNewTab: ((URL) -> Void)?
    var onClose: ((LittleWindowController) -> Void)?

    private let settings: ChordSettings
    private var page: ChordWebPage?
    private let root = LittleRootView()
    private let frost = GlassFrostView()
    private let tint = NSView()
    private let card = ContentCardView()
    private let addressPill = NSView()
    private let addressField = NSTextField()
    private let openButton = AccentPillButton(title: "Ouvrir dans Chord", shortcut: "⌘ O")
    private lazy var backButton = IconButton(symbol: "chevron.left", label: "Page précédente (⌘[)", target: self, action: #selector(goBack(_:)), size: 24, pointSize: 12)

    init(engine: ChordWebEngine, settings: ChordSettings, url: URL?, accent: NSColor) {
        self.settings = settings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 420, height: 300)
        // Like the main window: no shadow, so no dark outline around the glass.
        window.hasShadow = false
        window.title = "Petite fenêtre"
        // A compact toolbar makes the title bar 46 px tall, so the traffic lights sit
        // centred in the same row as the address.
        let toolbar = NSToolbar(identifier: "app.chord.little")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
        window.appearance = settings.appearance.nsAppearance
        super.init(window: window)
        window.delegate = self

        let page = engine.makePage()
        page.delegate = self
        self.page = page
        build(accent: accent)
        card.show(page.view)
        if let url {
            page.load(url)
            updateAddress(url: url)
        }
        window.center()
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 120, y: window.frame.minY - 60))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func focusAddress() {
        window?.makeFirstResponder(addressField)
        addressField.stringValue = page?.url?.absoluteString ?? ""
        addressField.currentEditor()?.selectAll(nil)
    }

    // MARK: - Layout

    private func build(accent: NSColor) {
        guard let window else { return }
        root.material = Theme.windowMaterial
        root.blendingMode = .behindWindow
        root.state = .active
        root.onOpenInChord = { [weak self] in self?.openInChord() }
        window.contentView = root
        tint.wantsLayer = true
        tint.layer?.backgroundColor = accent.withAlphaComponent(Theme.spaceTintAlpha).cgColor

        addressPill.wantsLayer = true
        addressPill.layer?.cornerRadius = 9
        addressPill.layer?.backgroundColor = NSColor.white.withAlphaComponent(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0.08 : 0.55).cgColor
        addressPill.layer?.borderWidth = 1
        addressPill.layer?.borderColor = NSColor.black.withAlphaComponent(0.05).cgColor
        addressField.isBordered = false
        addressField.isBezeled = false
        addressField.drawsBackground = false
        addressField.focusRingType = .none
        addressField.font = .systemFont(ofSize: 13)
        addressField.placeholderString = "Rechercher ou saisir une adresse"
        addressField.lineBreakMode = .byTruncatingTail
        addressField.cell?.usesSingleLineMode = true
        addressField.delegate = self
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressPill.addSubview(addressField)

        openButton.accent = accent
        openButton.onClick = { [weak self] in self?.openInChord() }

        for view in [frost, tint, backButton, addressPill, openButton, card] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        // The row fills the title bar, whose height the toolbar style decides.
        let rowBottom = (window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? root.topAnchor
        let row = NSLayoutGuide()
        root.addLayoutGuide(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: root.topAnchor),
            row.bottomAnchor.constraint(equalTo: rowBottom),
            frost.topAnchor.constraint(equalTo: root.topAnchor),
            frost.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            frost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            frost.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            tint.topAnchor.constraint(equalTo: root.topAnchor),
            tint.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            backButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 78),
            backButton.centerYAnchor.constraint(equalTo: addressPill.centerYAnchor),

            addressPill.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 6),
            addressPill.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -8),
            addressPill.heightAnchor.constraint(equalToConstant: 30),
            addressPill.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            addressField.leadingAnchor.constraint(equalTo: addressPill.leadingAnchor, constant: 12),
            addressField.trailingAnchor.constraint(equalTo: addressPill.trailingAnchor, constant: -12),
            addressField.centerYAnchor.constraint(equalTo: addressPill.centerYAnchor),

            openButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            openButton.centerYAnchor.constraint(equalTo: addressPill.centerYAnchor),

            card.topAnchor.constraint(equalTo: rowBottom),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
        ])
    }

    private func updateAddress(url: URL?) {
        guard window?.firstResponder !== addressField.currentEditor() else { return }
        guard let url else {
            addressField.stringValue = ""
            return
        }
        let host = url.host.map { h in url.port.map { "\(h):\($0)" } ?? h } ?? url.absoluteString
        let text = NSMutableAttributedString(string: host, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.labelColor,
        ])
        if url.path != "/" && !url.path.isEmpty {
            text.append(NSAttributedString(string: url.path, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        addressField.attributedStringValue = text
        backButton.isEnabled = page?.canGoBack ?? false
    }

    // MARK: - Actions

    private func openInChord() {
        guard let page else { return }
        card.show(nil)
        self.page = nil
        onOpenInChord?(page)
        window?.close()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            let text = addressField.stringValue
            if let url = URLInput.url(from: text) ?? settings.searchURL(for: text) {
                page?.load(url)
            }
            if let view = page?.view { window?.makeFirstResponder(view) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if let view = page?.view { window?.makeFirstResponder(view) }
            updateAddress(url: page?.url)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        updateAddress(url: page?.url)
    }

    // Menu actions reached through the responder chain while this window is key.
    @objc func goBack(_ sender: Any?) { page?.goBack() }
    @objc func goForward(_ sender: Any?) { page?.goForward() }
    @objc func reloadPage(_ sender: Any?) { page?.reload() }
    @objc func openLocation(_ sender: Any?) { focusAddress() }
    @objc func newTab(_ sender: Any?) { focusAddress() }
    @objc func closeTab(_ sender: Any?) { window?.close() }

    @objc func copyURL(_ sender: Any?) {
        guard let url = page?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    // MARK: - Delegates

    func windowWillClose(_ notification: Notification) {
        page = nil
        onClose?(self)
    }

    func pageDidUpdate(_ page: ChordWebPage) {
        guard page === self.page else { return }
        updateAddress(url: page.url)
        card.setLoading(page.isLoading, accent: openButton.accent)
        window?.title = page.title ?? "Petite fenêtre"
    }

    func page(_ page: ChordWebPage, wantsNewTabWith url: URL) {
        page.load(url)
    }
}

/// The little window's glass. Catches ⌘O for "Ouvrir dans Chord".
final class LittleRootView: NSVisualEffectView {
    var onOpenInChord: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "o" {
            onOpenInChord?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
