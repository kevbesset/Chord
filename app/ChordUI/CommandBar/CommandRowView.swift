import AppKit

/// One result row: tile or symbol, title, subtitle and shortcut.
final class CommandRowView: NSView {
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?
    var isSelected = false {
        didSet { if oldValue != isSelected { needsDisplay = true } }
    }
    var accent = NSColor.controlAccentColor {
        didSet { needsDisplay = true }
    }

    init(item: CommandItem) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        let icon: NSView
        if let url = item.tileURL {
            let tile = FaviconTileView(size: 18)
            tile.configure(url: url, fallback: item.title)
            icon = tile
        } else {
            let image = NSImageView(image: Theme.symbol(item.symbol ?? "circle", size: 14) ?? NSImage())
            image.contentTintColor = .labelColor
            image.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                image.widthAnchor.constraint(equalToConstant: 18),
                image.heightAnchor.constraint(equalToConstant: 18),
            ])
            icon = image
        }

        let title = NSTextField(labelWithString: item.title)
        title.font = .systemFont(ofSize: 14)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let subtitle = NSTextField(labelWithString: item.subtitle ?? "")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.isHidden = (item.subtitle ?? "").isEmpty
        subtitle.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let shortcut = NSTextField(labelWithString: item.shortcut ?? "")
        shortcut.font = .systemFont(ofSize: 12)
        shortcut.textColor = .secondaryLabelColor
        shortcut.isHidden = item.shortcut == nil

        shortcut.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        // The title takes the free space, so subtitle and shortcut sit at the right edge.
        let stack = NSStackView(views: [icon, title, subtitle, shortcut])
        stack.orientation = .horizontal
        stack.distribution = .fill
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        layer?.cornerRadius = 10
        layer?.backgroundColor = isSelected ? accent.withAlphaComponent(0.14).cgColor : NSColor.clear.cgColor
        layer?.borderWidth = isSelected ? 1 : 0
        layer?.borderColor = accent.withAlphaComponent(0.3).cgColor
    }

    // Hover selects only when the mouse actually moves, so that rows rebuilt
    // under a still cursor while typing do not steal the selection.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick?() }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
