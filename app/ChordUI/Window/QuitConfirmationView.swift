import AppKit

/// ⌘Q's question, like Arc's: one glass card over the window, with the app icon, and
/// three answers. Return quits, Escape cancels, ⌘Q again quits.
final class QuitConfirmationView: NSView {
    enum Answer { case quit, quitAndStopAsking, cancel }

    var onAnswer: ((Answer) -> Void)?

    private let scrim = ScrimView()
    private let host = ShadowHostView()
    private let panel = NSVisualEffectView()
    private let accent: NSColor

    /// `accent` colours the Quit button: the active Space's colour, like the chord of
    /// the logo.
    init(accent: NSColor) {
        self.accent = accent
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    private func build() {
        scrim.dims = true
        scrim.onClick = { [weak self] in self?.answer(.cancel) }
        host.cornerRadius = 22
        host.configureShadow(opacity: 0.2, radius: 10, offsetY: -4)
        host.configureAmbientShadow(opacity: 0.35, radius: 70, offsetY: -30)
        panel.material = .popover
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 22
        panel.layer?.masksToBounds = true
        panel.layer?.borderWidth = 0.5
        panel.layer?.borderColor = NSColor.separatorColor.cgColor

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        // Decorative: the title says it.
        icon.setAccessibilityRole(.unknown)
        let title = NSTextField(labelWithString: String(localized: "Quit Chord?", bundle: .chordUI))
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: String(localized: "Your Spaces and tabs will be here when you come back.", bundle: .chordUI))
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        let stopAsking = QuitButton(title: String(localized: "Quit and Don't Ask Again", bundle: .chordUI), key: nil, style: .secondary) { [weak self] in
            self?.answer(.quitAndStopAsking)
        }
        let cancel = QuitButton(title: String(localized: "Cancel", bundle: .chordUI), key: String(localized: "key.escape", defaultValue: "esc", bundle: .chordUI, comment: "The Escape key, on a key cap"), style: .secondary) { [weak self] in
            self?.answer(.cancel)
        }
        let quit = QuitButton(title: String(localized: "Quit", bundle: .chordUI), key: "↩", style: .primary(accent)) { [weak self] in
            self?.answer(.quit)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttons = NSStackView(views: [stopAsking, spacer, cancel, quit])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let texts = NSStackView(views: [title, subtitle])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 6
        let column = NSStackView(views: [icon, texts, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 20
        column.setCustomSpacing(34, after: texts)
        column.edgeInsets = NSEdgeInsets(top: 34, left: 28, bottom: 28, right: 28)
        column.translatesAutoresizingMaskIntoConstraints = false

        for view in [scrim, host] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        panel.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(panel)
        panel.addSubview(column)
        NSLayoutConstraint.activate([
            scrim.topAnchor.constraint(equalTo: topAnchor),
            scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: bottomAnchor),
            host.centerXAnchor.constraint(equalTo: centerXAnchor),
            host.centerYAnchor.constraint(equalTo: centerYAnchor),
            host.widthAnchor.constraint(greaterThanOrEqualToConstant: 500),
            host.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
            panel.topAnchor.constraint(equalTo: host.topAnchor),
            panel.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            column.topAnchor.constraint(equalTo: panel.topAnchor),
            column.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            buttons.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 28),
            buttons.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -28),
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            subtitle.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title.stringValue)
    }

    /// Fades in, the card rising slightly into place.
    func appear() {
        alphaValue = 0
        host.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.96, y: 0.96))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = Theme.motionCurve
            context.allowsImplicitAnimation = true
            animator().alphaValue = 1
            host.layer?.setAffineTransform(.identity)
        }
    }

    private func answer(_ answer: Answer) {
        onAnswer?(answer)
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: answer(.quit) // Return, Enter
        case 53: answer(.cancel) // Escape
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { answer(.cancel) }
}

/// One of the card's answers, with the key that gives it on a key cap.
private final class QuitButton: NSView {
    enum Style { case primary(NSColor), secondary }

    private let style: Style
    private let action: () -> Void
    private let label: NSTextField
    private let keyCap: NSTextField?
    private let keyCapBackground = NSView()
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    init(title: String, key: String?, style: Style, action: @escaping () -> Void) {
        self.style = style
        self.action = action
        label = NSTextField(labelWithString: title)
        keyCap = key.map { NSTextField(labelWithString: $0) }
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        var views: [NSView] = [label]
        if let keyCap {
            keyCap.font = .systemFont(ofSize: 11, weight: .semibold)
            keyCap.alignment = .center
            keyCap.translatesAutoresizingMaskIntoConstraints = false
            keyCapBackground.wantsLayer = true
            keyCapBackground.layer?.cornerRadius = 5
            keyCapBackground.addSubview(keyCap)
            NSLayoutConstraint.activate([
                keyCap.centerYAnchor.constraint(equalTo: keyCapBackground.centerYAnchor),
                keyCap.leadingAnchor.constraint(equalTo: keyCapBackground.leadingAnchor, constant: 6),
                keyCap.trailingAnchor.constraint(equalTo: keyCapBackground.trailingAnchor, constant: -6),
                keyCapBackground.heightAnchor.constraint(equalToConstant: 20),
                keyCapBackground.widthAnchor.constraint(greaterThanOrEqualToConstant: 26),
            ])
            views.append(keyCapBackground)
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: key == nil ? -16 : -9),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        guard let layer else { return }
        let dark = isDarkAppearance
        layer.cornerRadius = 10
        switch style {
        case .primary(let color):
            let shade: CGFloat = isPressed ? 0.18 : isHovered ? 0.08 : 0
            layer.backgroundColor = (color.blended(withFraction: shade, of: .black) ?? color).cgColor
            layer.borderWidth = 0
            label.textColor = .white
            keyCap?.textColor = .white
            keyCapBackground.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
            keyCapBackground.layer?.borderWidth = 0
            layer.shadowColor = color.cgColor
            layer.shadowOpacity = dark ? 0 : 0.3
            layer.shadowRadius = 6
            layer.shadowOffset = CGSize(width: 0, height: -2)
        case .secondary:
            let base: CGFloat = dark ? 0.1 : 0.75
            let alpha = base + (isPressed ? 0.1 : isHovered ? 0.06 : 0)
            layer.backgroundColor = (dark ? NSColor.white.withAlphaComponent(alpha) : NSColor.white.withAlphaComponent(min(alpha, 1))).cgColor
            layer.borderWidth = 0.5
            layer.borderColor = NSColor.black.withAlphaComponent(dark ? 0.3 : 0.12).cgColor
            label.textColor = .labelColor
            keyCap?.textColor = .secondaryLabelColor
            keyCapBackground.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(dark ? 0.12 : 0.07).cgColor
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = dark ? 0 : 0.06
            layer.shadowRadius = 1
            layer.shadowOffset = CGSize(width: 0, height: -1)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
}
