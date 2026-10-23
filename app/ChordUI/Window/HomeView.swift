import AppKit

/// Chord's home page, shown when the Space has no tab open (or every tab was closed):
/// the mark, a greeting, a search field that opens the command bar, the Space's
/// favorites and pinned tabs to get back to work, and the shortcuts worth knowing.
final class HomeView: NSView {
    var onSearch: (() -> Void)?
    var onOpen: ((Tab) -> Void)?

    private let glow = CAGradientLayer()
    private let mark = ChordMarkView()
    private let greeting = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let search = HomeSearchView()
    private let shortcutsTitle = NSTextField(labelWithString: "")
    private let shortcuts = NSStackView()
    private let quickTitle = NSTextField(labelWithString: "")
    private let quickGrid = NSStackView()
    private var accent = NSColor(hex: Theme.spacePalette[0])

    static let maxQuickTiles = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(glow)
        glow.type = .radial

        greeting.font = .systemFont(ofSize: 28, weight: .semibold)
        greeting.alignment = .center
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        search.onClick = { [weak self] in self?.onSearch?() }

        for label in [quickTitle, shortcutsTitle] {
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
        }
        quickGrid.orientation = .horizontal
        quickGrid.spacing = 12
        quickGrid.alignment = .top
        shortcuts.orientation = .horizontal
        shortcuts.spacing = 22
        for (keys, label) in [("⌘T", "Nouvel onglet"), ("⌘L", "Adresse"), ("⇧⌘D", "Split view"), ("⌘S", "Barre latérale"), ("⌥⌘N", "Petite fenêtre")] {
            shortcuts.addArrangedSubview(Self.shortcut(keys, label))
        }
        shortcutsTitle.stringValue = "RACCOURCIS"

        let column = NSStackView(views: [mark, greeting, subtitle, search, quickTitle, quickGrid, shortcutsTitle, shortcuts])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 10
        column.setCustomSpacing(22, after: mark)
        column.setCustomSpacing(4, after: greeting)
        column.setCustomSpacing(28, after: subtitle)
        column.setCustomSpacing(40, after: search)
        column.setCustomSpacing(14, after: quickTitle)
        column.setCustomSpacing(40, after: quickGrid)
        column.setCustomSpacing(12, after: shortcutsTitle)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        let lifted = column.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -30)
        lifted.priority = .defaultHigh
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            lifted,
            column.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 32),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            mark.widthAnchor.constraint(equalToConstant: 52),
            mark.heightAnchor.constraint(equalToConstant: 52),
            search.widthAnchor.constraint(equalToConstant: 480),
            search.heightAnchor.constraint(equalToConstant: 46),
        ])
        setAccessibilityLabel("Accueil de Chord")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        // A soft wash of the Space colour from the top, like light through the glass.
        glow.colors = [accent.withAlphaComponent(isDarkAppearance ? 0.16 : 0.10).cgColor, accent.withAlphaComponent(0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 1.15)
        glow.endPoint = CGPoint(x: 1.1, y: 0.1)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// The Space shown: its colour, name, and its favorites then pinned tabs as shortcuts.
    func update(space: Space, favorites: [Tab]) {
        accent = space.accent
        greeting.stringValue = Self.greeting()
        subtitle.stringValue = "Space \(space.name) · aucun onglet ouvert"
        needsDisplay = true

        let quick = Array((favorites + space.pinned).prefix(Self.maxQuickTiles))
        quickGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tab in quick {
            let tile = HomeTileView(tab: tab)
            tile.onClick = { [weak self] in self?.onOpen?(tab) }
            quickGrid.addArrangedSubview(tile)
        }
        quickTitle.stringValue = favorites.isEmpty ? "ÉPINGLÉS" : "FAVORIS ET ÉPINGLÉS"
        quickTitle.isHidden = quick.isEmpty
        quickGrid.isHidden = quick.isEmpty
    }

    /// "Bonjour Kevin", "Bonsoir Kevin": the macOS account's first name, when there is one.
    private static func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let hello = hour >= 18 || hour < 5 ? "Bonsoir" : "Bonjour"
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? hello : "\(hello) \(first)"
    }

    private static func shortcut(_ keys: String, _ label: String) -> NSView {
        let key = NSTextField(labelWithString: keys)
        key.font = .systemFont(ofSize: 11, weight: .medium)
        key.textColor = .secondaryLabelColor
        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 11)
        text.textColor = .tertiaryLabelColor
        let stack = NSStackView(views: [key, text])
        stack.spacing = 6
        return stack
    }
}

/// The search field of the home page. It only looks like a field: a click opens the
/// command bar, where typing happens.
final class HomeSearchView: NSView {
    var onClick: (() -> Void)?
    private var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: Theme.symbol("magnifyingglass", size: 15) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        let placeholder = NSTextField(labelWithString: "Rechercher ou saisir une adresse")
        placeholder.font = .systemFont(ofSize: 15)
        placeholder.textColor = .secondaryLabelColor
        let key = NSTextField(labelWithString: "⌘T")
        key.font = .systemFont(ofSize: 12, weight: .medium)
        key.textColor = .tertiaryLabelColor
        for view in [icon, placeholder, key] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholder.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
            key.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            key.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Rechercher ou saisir une adresse")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        guard let layer else { return }
        let dark = isDarkAppearance
        layer.cornerRadius = 12
        layer.backgroundColor = (dark ? NSColor.white.withAlphaComponent(isHovered ? 0.1 : 0.07)
                                      : NSColor.black.withAlphaComponent(isHovered ? 0.06 : 0.04)).cgColor
        layer.borderWidth = 1
        layer.borderColor = (dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.05)).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

/// A favorite or pinned tab on the home page: its icon on a frosted tile, its name below.
final class HomeTileView: NSView {
    var onClick: (() -> Void)?
    private let tileBackground = NSView()
    private var isHovered = false

    init(tab: Tab) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        tileBackground.wantsLayer = true
        let icon = FaviconTileView(size: 24)
        icon.configure(url: tab.url, fallback: tab.displayTitle)
        let name = NSTextField(labelWithString: tab.displayTitle)
        name.font = .systemFont(ofSize: 11)
        name.textColor = .secondaryLabelColor
        name.alignment = .center
        name.lineBreakMode = .byTruncatingTail
        for view in [tileBackground, icon, name] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 72),
            tileBackground.topAnchor.constraint(equalTo: topAnchor),
            tileBackground.centerXAnchor.constraint(equalTo: centerXAnchor),
            tileBackground.widthAnchor.constraint(equalToConstant: 56),
            tileBackground.heightAnchor.constraint(equalToConstant: 56),
            icon.centerXAnchor.constraint(equalTo: tileBackground.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: tileBackground.centerYAnchor),
            name.topAnchor.constraint(equalTo: tileBackground.bottomAnchor, constant: 7),
            name.leadingAnchor.constraint(equalTo: leadingAnchor),
            name.trailingAnchor.constraint(equalTo: trailingAnchor),
            name.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        toolTip = tab.url?.absoluteString
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tab.displayTitle)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }

    private func refresh() {
        let dark = isDarkAppearance
        tileBackground.layer?.cornerRadius = 14
        tileBackground.layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(isHovered ? 0.12 : 0.07)
                                                      : NSColor.black.withAlphaComponent(isHovered ? 0.07 : 0.04)).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func mouseDown(with event: NSEvent) {}

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

/// The mark, as in the brand guide (design/brand/chord-mark.svg): the arc in the text
/// colour, the chord in Chord's indigo, whatever the Space.
final class ChordMarkView: NSView {
    private let accent = NSColor(hex: Theme.spacePalette[0])

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // The SVG's geometry: radius 100, stroke 30, in a 240 unit box centred on 0.
        let scale = min(bounds.width, bounds.height) / 240
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: center.x + x * scale, y: center.y + y * scale) }

        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: 100 * scale, startAngle: -45, endAngle: 45, clockwise: true)
        arc.lineWidth = 30 * scale
        arc.lineCapStyle = .round
        NSColor.labelColor.setStroke()
        arc.stroke()

        let chord = NSBezierPath()
        chord.move(to: point(70.7, 70.7))
        chord.line(to: point(70.7, -70.7))
        chord.lineWidth = 30 * scale
        chord.lineCapStyle = .round
        accent.setStroke()
        chord.stroke()
    }
}
