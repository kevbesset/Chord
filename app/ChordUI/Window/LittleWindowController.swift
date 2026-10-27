import AppKit

/// The little window (Little Arc): a small glass window for a link opened from another
/// app, or ⌥⌘N. "Open in" (⌘O) moves the page into the main window as a tab of the
/// Space it names: the last Space used, or another one picked from its chevron.
final class LittleWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, ChordWebPageDelegate {
    var onOpenInChord: ((ChordWebPage, Space) -> Void)?
    var onNewTab: ((URL) -> Void)?
    var onClose: ((LittleWindowController) -> Void)?

    private let settings: ChordSettings
    private var page: ChordWebPage?
    private let root = LittleRootView()
    private let frost = GlassFrostView()
    private let tint = NSView()
    private let card = ContentCardView()
    private let toast = ToastView()
    private let addressPill = NSView()
    private let addressField = NSTextField()
    private let openButton = OpenInSpaceButton()
    private lazy var backButton = IconButton(symbol: "arrow.left", label: String(localized: "Back (⌘[)", bundle: .chordUI), target: self, action: #selector(goBack(_:)), size: 26, pointSize: 13)
    private let spaces: () -> [Space]
    private(set) var targetSpace: Space
    private let permissionPrompt = PermissionPromptController()

    /// `space` is where "Open in" sends the page until another one is picked;
    /// `spaces` lists the choices when the picker opens.
    init(engine: ChordWebEngine, settings: ChordSettings, url: URL?, space: Space, spaces: @escaping () -> [Space]) {
        self.settings = settings
        self.spaces = spaces
        targetSpace = space
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
        window.isRestorable = false
        window.minSize = NSSize(width: 420, height: 300)
        // Like the main window: no shadow, so no dark outline around the glass.
        window.hasShadow = false
        window.title = String(localized: "Little Window", bundle: .chordUI)
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
        build()
        setTarget(space)
        card.show(PageHostView.host(for: page))
        if let url {
            page.load(url)
            updateAddress(url: url)
        }
        window.center()
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 120, y: window.frame.minY - 60))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func shows(_ page: ChordWebPage) -> Bool { self.page === page }

    /// A site's question, from the top of the page.
    func presentPermission(_ request: ChordPermissionRequest) {
        guard let page, page.view.window != nil else { return }
        permissionPrompt.present(request, for: page, from: page.view, rect: PermissionPromptController.pageTop(of: page.view))
    }

    func focusAddress() {
        window?.makeFirstResponder(addressField)
        addressField.stringValue = page?.url?.absoluteString ?? ""
        addressField.currentEditor()?.selectAll(nil)
    }

    // MARK: - Layout

    private func build() {
        guard let window else { return }
        root.material = Theme.windowMaterial
        root.blendingMode = .behindWindow
        root.state = .active
        root.onOpenInChord = { [weak self] in self?.openInChord() }
        window.contentView = root
        tint.wantsLayer = true

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
        addressField.placeholderString = String(localized: "Search or enter URL", bundle: .chordUI)
        // One line that scrolls with the caret, however long the address.
        addressField.cell?.wraps = false
        addressField.cell?.isScrollable = true
        addressField.cell?.usesSingleLineMode = true
        addressField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addressField.delegate = self
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressPill.addSubview(addressField)

        openButton.onOpen = { [weak self] in self?.openInChord() }
        openButton.onPickSpace = { [weak self] anchor in self?.showSpaceMenu(from: anchor) }

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
        onOpenInChord?(page, targetSpace)
        window?.close()
    }

    // MARK: - Target Space

    /// The Space "Open in" sends the page to. The window takes its tint and accent,
    /// like Little Arc takes the Space's theme.
    private func setTarget(_ space: Space) {
        targetSpace = space
        openButton.configure(space: space)
        tint.layer?.backgroundColor = space.color.withAlphaComponent(Theme.spaceTintBottom).cgColor
        card.setLoading(page?.isLoading ?? false, accent: space.accent)
    }

    private func showSpaceMenu(from anchor: NSView) {
        let menu = NSMenu()
        let header = NSMenuItem(title: String(localized: "Open in Space", bundle: .chordUI), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for space in spaces() {
            let item = closureItem(space.name) { [weak self] in self?.setTarget(space) }
            item.image = Theme.dot(color: space.color, size: 12)
            item.state = space === targetSpace ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -6), in: anchor)
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
    @objc func toggleDevTools(_ sender: Any?) { page?.toggleDevTools?() }
    @objc func openLocation(_ sender: Any?) { focusAddress() }
    @objc func newTab(_ sender: Any?) { focusAddress() }
    @objc func closeTab(_ sender: Any?) { window?.close() }

    @objc func copyURL(_ sender: Any?) {
        guard let url = page?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        if let root = window?.contentView {
            toast.show(String(localized: "URL copied", bundle: .chordUI), detail: url.displayHost, symbol: "checkmark.circle.fill", in: root, over: card, accent: targetSpace.accent)
        }
    }

    // MARK: - Delegates

    func windowWillClose(_ notification: Notification) {
        page = nil
        onClose?(self)
    }

    func pageDidUpdate(_ page: ChordWebPage) {
        PageHostView.pageDidUpdate(page)
        guard page === self.page else { return }
        updateAddress(url: page.url)
        card.setLoading(page.isLoading, accent: targetSpace.accent)
        window?.title = page.title ?? String(localized: "Little Window", bundle: .chordUI)
    }

    func page(_ page: ChordWebPage, wantsNewTabWith url: URL) {
        page.load(url)
    }
}

/// The little window's glass. Catches ⌘O for "Open in Chord".
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

/// "Open in ● Personal ⌘O ⌄", tinted with the Space's colour. The main part opens the
/// page in that Space; the chevron, past a thin divider, picks another Space.
final class OpenInSpaceButton: NSView {
    var onOpen: (() -> Void)?
    /// Called with the view the Space menu should open from.
    var onPickSpace: ((NSView) -> Void)?

    private let dot = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let divider = NSView()
    private let chevronArea = NSView()
    private var accent = NSColor.controlAccentColor
    private var isPressed = false

    static let chevronWidth: CGFloat = 24

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: String(localized: "Open in", bundle: .chordUI))
        label.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let hint = NSTextField(labelWithString: "⌘ O")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        let chevron = NSImageView(image: Theme.symbol("chevron.down", size: 9, weight: .semibold) ?? NSImage())
        chevron.contentTintColor = .secondaryLabelColor
        divider.wantsLayer = true

        let stack = NSStackView(views: [label, dot, nameLabel, hint])
        stack.spacing = 6
        stack.setCustomSpacing(4, after: dot)
        stack.setCustomSpacing(8, after: nameLabel)
        for view in [stack, divider, chevronArea, chevron] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(equalTo: divider.leadingAnchor, constant: -8),
            nameLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 120),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            divider.trailingAnchor.constraint(equalTo: chevronArea.leadingAnchor),
            chevronArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            chevronArea.topAnchor.constraint(equalTo: topAnchor),
            chevronArea.bottomAnchor.constraint(equalTo: bottomAnchor),
            chevronArea.widthAnchor.constraint(equalToConstant: Self.chevronWidth),
            chevron.centerXAnchor.constraint(equalTo: chevronArea.centerXAnchor),
            chevron.centerYAnchor.constraint(equalTo: chevronArea.centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(space: Space) {
        accent = space.accent
        nameLabel.stringValue = space.name
        dot.layer?.backgroundColor = space.color.cgColor
        toolTip = String(localized: "Open the page in Space \(space.name) (⌘O)", bundle: .chordUI)
        setAccessibilityLabel(String(localized: "Open in Space \(space.name)", bundle: .chordUI))
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        let base = isDarkAppearance ? NSColor(hex: "#3A3A3C") : NSColor.white
        layer?.cornerRadius = 8
        layer?.backgroundColor = (base.blended(withFraction: isPressed ? 0.24 : 0.14, of: accent) ?? base).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = accent.withAlphaComponent(0.3).cgColor
        divider.layer?.backgroundColor = accent.withAlphaComponent(0.3).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func inChevron(_ event: NSEvent) -> Bool {
        convert(event.locationInWindow, from: nil).x >= bounds.width - Self.chevronWidth
    }

    /// The Space menu opens on mouse down, like any pop-up button.
    override func mouseDown(with event: NSEvent) {
        if inChevron(event) {
            onPickSpace?(chevronArea)
            return
        }
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)), !inChevron(event) { onOpen?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onOpen?()
        return true
    }
}
