import AppKit

/// Peek: a link previewed over the page without leaving it (⇧-click, or a link that
/// leaves a favorite or pinned tab). Esc closes it, ⌘↩ keeps it as a tab.
///
/// Like the command bar, its views are built once and then only shown and hidden.
final class PeekController: NSObject, ChordWebPageDelegate {
    /// Keep the page as a tab; the page is handed over as it is, without reloading.
    var onOpenInTab: ((ChordWebPage) -> Void)?
    /// Show the page in a split with the current tab.
    var onSplit: ((ChordWebPage) -> Void)?
    var onNewTab: ((URL) -> Void)?
    var onDismiss: (() -> Void)?
    private(set) var isVisible = false

    private let engine: ChordWebEngine
    private weak var host: NSView?
    private let scrim = ScrimView()
    private let panelHost = ShadowHostView()
    private let panel = PeekPanelView()
    private let contentGuide = NSLayoutGuide()
    private var contentLeading: NSLayoutConstraint!
    private var page: ChordWebPage?
    private var keyMonitor: Any?

    init(engine: ChordWebEngine) {
        self.engine = engine
        super.init()
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    /// Opens `url` in a Peek centred over the page area, which starts at `contentInset`.
    func present(url: URL, in host: NSView, contentInset: CGFloat, accent: NSColor) {
        let interval = Perf.begin("peek.open")
        install(in: host)
        contentLeading.constant = contentInset

        let page = engine.makePage()
        page.delegate = self
        self.page = page
        panel.show(page: page, accent: accent)
        page.load(url)
        panel.updateHeader(url: url, title: nil)

        scrim.isHidden = false
        panelHost.isHidden = false
        isVisible = true
        host.layoutSubtreeIfNeeded()
        animateIn()
        host.window?.makeFirstResponder(page.view)
        installKeyMonitor()
        DispatchQueue.main.async { interval.end() }
    }

    func dismiss() {
        guard isVisible else { return }
        isVisible = false
        removeKeyMonitor()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            self.scrim.animator().alphaValue = 0
            self.panelHost.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isVisible else { return }
            self.scrim.isHidden = true
            self.panelHost.isHidden = true
            self.panel.show(page: nil, accent: nil)
            self.page = nil
        })
        onDismiss?()
    }

    /// Hands the page over (to a tab or a split) and closes the Peek without destroying it.
    private func handOver(_ action: ((ChordWebPage) -> Void)?) {
        guard let page else { return }
        panel.show(page: nil, accent: nil)
        self.page = nil
        dismiss()
        action?(page)
    }

    func openInTab() { handOver(onOpenInTab) }
    func openInSplit() { handOver(onSplit) }

    // MARK: - Building (once)

    private func install(in host: NSView) {
        guard self.host !== host else { return }
        self.host = host
        scrim.onClick = { [weak self] in self?.dismiss() }
        panelHost.cornerRadius = 16
        panelHost.configureShadow(opacity: 0.3, radius: 40, offsetY: -16)
        panel.onOpenInTab = { [weak self] in self?.openInTab() }
        panel.onSplit = { [weak self] in self?.openInSplit() }
        panel.onClose = { [weak self] in self?.dismiss() }

        host.addLayoutGuide(contentGuide)
        for view in [scrim, panelHost] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(view)
        }
        panel.translatesAutoresizingMaskIntoConstraints = false
        panelHost.addSubview(panel)

        contentLeading = contentGuide.leadingAnchor.constraint(equalTo: host.leadingAnchor)
        let preferredWidth = panelHost.widthAnchor.constraint(equalToConstant: 1040)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            contentLeading,
            contentGuide.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            scrim.topAnchor.constraint(equalTo: host.topAnchor),
            scrim.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: host.bottomAnchor),

            panelHost.centerXAnchor.constraint(equalTo: contentGuide.centerXAnchor),
            panelHost.topAnchor.constraint(equalTo: host.topAnchor, constant: 46),
            panelHost.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -46),
            panelHost.widthAnchor.constraint(lessThanOrEqualTo: contentGuide.widthAnchor, constant: -88),
            preferredWidth,

            panel.topAnchor.constraint(equalTo: panelHost.topAnchor),
            panel.leadingAnchor.constraint(equalTo: panelHost.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: panelHost.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: panelHost.bottomAnchor),
        ])
        scrim.isHidden = true
        panelHost.isHidden = true
    }

    /// A short spring from slightly smaller, so the Peek grows out of the page.
    private func animateIn() {
        scrim.alphaValue = 0
        panelHost.alphaValue = 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            self.scrim.animator().alphaValue = 1
        }
        guard let layer = panelHost.layer else { return }
        let center = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
        var from = CATransform3DMakeTranslation(center.x, center.y, 0)
        from = CATransform3DScale(from, 0.94, 0.94, 1)
        from = CATransform3DTranslate(from, -center.x, -center.y, 0)
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = from
        spring.toValue = CATransform3DIdentity
        spring.damping = 22
        spring.stiffness = 260
        spring.mass = 1
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "peekIn")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.14
        layer.add(fade, forKey: "peekFade")
    }

    // MARK: - Keyboard: esc closes, ⌘↩ opens in a tab

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, event.window === self.host?.window else { return event }
            if event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            if event.keyCode == 36, event.modifierFlags.contains(.command) {
                self.openInTab()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: - ChordWebPageDelegate

    func pageDidUpdate(_ page: ChordWebPage) {
        guard page === self.page else { return }
        panel.updateHeader(url: page.url, title: page.title)
        panel.setLoading(page.isLoading)
    }

    func page(_ page: ChordWebPage, wantsNewTabWith url: URL) {
        onNewTab?(url)
    }
}

/// The Peek card: a 44 px header over the page.
final class PeekPanelView: NSView {
    var onOpenInTab: (() -> Void)?
    var onSplit: (() -> Void)?
    var onClose: (() -> Void)?

    private let header = PeekHeaderView()
    private let card = ContentCardView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        card.setAccessory(header)
        card.setEdgeless(true)
        header.openButton.onClick = { [weak self] in self?.onOpenInTab?() }
        header.onSplit = { [weak self] in self?.onSplit?() }
        header.onClose = { [weak self] in self?.onClose?() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.borderWidth = 1
        layer?.borderColor = (isDarkAppearance ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.1)).cgColor
    }

    func show(page: ChordWebPage?, accent: NSColor?) {
        card.show(page?.view)
        if let accent { header.openButton.accent = accent }
    }

    func updateHeader(url: URL?, title: String?) {
        header.update(url: url, title: title)
    }

    func setLoading(_ loading: Bool) {
        card.setLoading(loading, accent: header.openButton.accent)
    }
}

final class PeekHeaderView: NSView {
    var onSplit: (() -> Void)?
    var onClose: (() -> Void)?
    let openButton = AccentPillButton(title: "Ouvrir dans un onglet", shortcut: "⌘ ↩")
    private let tile = FaviconTileView(size: 16)
    private let titleLabel = NSTextField(labelWithString: "")
    private let urlLabel = NSTextField(labelWithString: "")
    private lazy var splitButton = IconButton(symbol: "rectangle.split.2x1", label: "Split view avec la page courante (⇧⌘D)", target: self, action: #selector(splitClicked), size: 28, pointSize: 13)
    private lazy var closeButton = IconButton(symbol: "xmark", label: "Fermer (esc)", target: self, action: #selector(closeClicked), size: 28, pointSize: 12)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow + 1, for: .horizontal)
        urlLabel.font = .systemFont(ofSize: 12)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.lineBreakMode = .byTruncatingMiddle
        urlLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        closeButton.contentTintColor = .labelColor
        splitButton.contentTintColor = .labelColor

        let leading = NSStackView(views: [tile, titleLabel, urlLabel])
        leading.spacing = 10
        let trailing = NSStackView(views: [openButton, splitButton, closeButton])
        trailing.spacing = 4
        let rule = HairlineView()
        for view in [leading, trailing, rule] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            leading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            leading.centerYAnchor.constraint(equalTo: centerYAnchor),
            leading.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -12),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        layer?.backgroundColor = (isDarkAppearance ? NSColor(hex: "#2C2C2E") : NSColor(hex: "#FAFAFB")).withAlphaComponent(0.95).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func update(url: URL?, title: String?) {
        tile.configure(url: url, fallback: title ?? "")
        titleLabel.stringValue = (title?.isEmpty ?? true) ? (url?.host ?? "") : title!
        if let url {
            urlLabel.stringValue = (url.host ?? "") + (url.path == "/" ? "" : url.path)
        } else {
            urlLabel.stringValue = ""
        }
    }

    @objc private func splitClicked() { onSplit?() }
    @objc private func closeClicked() { onClose?() }
}

/// A pill tinted with the Space colour, with a shortcut hint: "Ouvrir dans un onglet ⌘ ↩".
final class AccentPillButton: NSView {
    var onClick: (() -> Void)?
    var accent = NSColor.controlAccentColor { didSet { needsDisplay = true } }
    private var isPressed = false

    init(title: String, shortcut: String) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let hint = NSTextField(labelWithString: shortcut)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label, hint])
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        let base = isDarkAppearance ? NSColor(hex: "#3A3A3C") : NSColor.white
        layer?.cornerRadius = 8
        layer?.backgroundColor = (base.blended(withFraction: isPressed ? 0.22 : 0.12, of: accent) ?? base).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = accent.withAlphaComponent(0.28).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
