import AppKit

/// Chord's home page, shown when the Space has no tab open (or every tab was closed):
/// a landscape with Chord's mark as its sun or moon, a greeting, a search field that opens the command bar, the Space's
/// favorites and pinned tabs to get back to work, and the shortcuts worth knowing.
final class HomeView: NSView {
    var onSearch: (() -> Void)?
    var onOpen: ((Tab) -> Void)?

    private let landscape = HomeLandscapeView()
    private let column = NSStackView()
    private let greeting = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let search = HomeSearchView()
    private let shortcutsTitle = NSTextField(labelWithString: "")
    private let shortcuts = NSStackView()
    private let quickTitle = NSTextField(labelWithString: "")
    private let quickGrid = NSStackView()

    static let maxQuickTiles = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        landscape.translatesAutoresizingMaskIntoConstraints = false
        addSubview(landscape)

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
        for (keys, label) in [("⌘T", String(localized: "New Tab", bundle: .chordUI)), ("⌘L", String(localized: "Address", bundle: .chordUI)), ("⌃⇧=", String(localized: "Split View", bundle: .chordUI)), ("⌘S", String(localized: "Sidebar", bundle: .chordUI)), ("⌥⌘N", String(localized: "Little Window", bundle: .chordUI))] {
            shortcuts.addArrangedSubview(Self.shortcut(keys, label))
        }
        shortcutsTitle.stringValue = String(localized: "SHORTCUTS", bundle: .chordUI)

        column.setViews([greeting, subtitle, search, quickTitle, quickGrid, shortcutsTitle, shortcuts], in: .center)
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 10
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
            landscape.topAnchor.constraint(equalTo: topAnchor),
            landscape.bottomAnchor.constraint(equalTo: bottomAnchor),
            landscape.leadingAnchor.constraint(equalTo: leadingAnchor),
            landscape.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            lifted,
            column.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 32),
            column.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            search.widthAnchor.constraint(equalToConstant: 480),
            search.heightAnchor.constraint(equalToConstant: 46),
        ])
        setAccessibilityLabel(String(localized: "Chord home", bundle: .chordUI))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        landscape.hazeRect = column.frame
    }

    /// The Space shown: its colour, name, and its favorites then pinned tabs as shortcuts.
    func update(space: Space, favorites: [Tab]) {
        greeting.stringValue = Self.greeting()
        subtitle.stringValue = String(localized: "Space \(space.name) · no open tabs", bundle: .chordUI)

        let quick = Array((favorites + space.pinned).prefix(Self.maxQuickTiles))
        quickGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tab in quick {
            let tile = HomeTileView(tab: tab)
            tile.onClick = { [weak self] in self?.onOpen?(tab) }
            quickGrid.addArrangedSubview(tile)
        }
        quickTitle.stringValue = favorites.isEmpty ? String(localized: "PINNED", bundle: .chordUI) : String(localized: "FAVORITES AND PINNED", bundle: .chordUI)
        quickTitle.isHidden = quick.isEmpty
        quickGrid.isHidden = quick.isEmpty
    }

    /// "Good morning, Kevin", "Good evening, Kevin": the macOS account's first name, when there is one.
    private static func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        switch hour {
        case 5..<12:
            return first.isEmpty ? String(localized: "Good morning", bundle: .chordUI)
                                 : String(localized: "Good morning, \(first)", bundle: .chordUI)
        case 12..<18:
            return first.isEmpty ? String(localized: "Good afternoon", bundle: .chordUI)
                                 : String(localized: "Good afternoon, \(first)", bundle: .chordUI)
        default:
            return first.isEmpty ? String(localized: "Good evening", bundle: .chordUI)
                                 : String(localized: "Good evening, \(first)", bundle: .chordUI)
        }
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
        let placeholder = NSTextField(labelWithString: String(localized: "Search or enter URL", bundle: .chordUI))
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
        setAccessibilityLabel(String(localized: "Search or enter URL", bundle: .chordUI))
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
