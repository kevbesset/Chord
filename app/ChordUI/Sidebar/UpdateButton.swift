import AppKit

/// The sidebar's update button, above the Spaces, like Arc's: shown once a new version
/// of Chord is downloaded. A click restarts Chord on it.
final class UpdateButton: NSView {
    var onClick: (() -> Void)?

    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: String(localized: "Update Chord", bundle: .chordUI))
    private let version = NSTextField(labelWithString: "")
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    static let height: CGFloat = 34

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        icon.image = Theme.symbol("arrow.down.circle.fill", size: 14)
        icon.contentTintColor = .controlAccentColor
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        version.font = .systemFont(ofSize: 11)
        version.textColor = .secondaryLabelColor
        version.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        for view in [icon, title, version] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            version.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 6),
            version.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            version.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
        ])
        toolTip = String(localized: "Restart Chord on the new version", bundle: .chordUI)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title.stringValue)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The version waiting to be installed ("0.4.0").
    func update(version: String) {
        self.version.stringValue = version
        setAccessibilityValue(version)
    }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        layer?.cornerRadius = 10
        let base: CGFloat = isDarkAppearance ? 0.08 : 0.55
        let alpha = isPressed ? base + 0.12 : (isHovered ? base + 0.06 : base)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(min(alpha, 1)).cgColor
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
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
