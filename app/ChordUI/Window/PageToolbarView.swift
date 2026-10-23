import AppKit

/// What the bars above the page ask the window to do.
enum PageBarAction {
    case back, forward, reload, address, split, copyURL, closePane(Tab), activate(Tab)
}

/// The Safari-style bar on top of the page (address bar setting "en haut"): 32 px, same
/// background as the page, a hairline below. Navigation left, address centred, actions right.
final class PageToolbarView: NSView {
    var onAction: ((PageBarAction) -> Void)?
    var moreMenu: (() -> NSMenu)?

    private lazy var backButton = IconButton(symbol: "chevron.left", label: "Page précédente (⌘[)", target: self, action: #selector(backClicked), size: 24, pointSize: 12)
    private lazy var forwardButton = IconButton(symbol: "chevron.right", label: "Page suivante (⌘])", target: self, action: #selector(forwardClicked), size: 24, pointSize: 12)
    private lazy var reloadButton = IconButton(symbol: "arrow.clockwise", label: "Recharger (⌘R)", target: self, action: #selector(reloadClicked), size: 24, pointSize: 12)
    private lazy var splitButton = IconButton(symbol: "rectangle.split.2x1", label: "Split view (⌃⇧=)", target: self, action: #selector(splitClicked), size: 24, pointSize: 12)
    private lazy var copyButton = IconButton(symbol: "link", label: "Copier l'URL (⇧⌘C)", target: self, action: #selector(copyClicked), size: 24, pointSize: 12)
    private lazy var moreButton = IconButton(symbol: "ellipsis", label: "Plus d'actions", target: self, action: #selector(moreClicked), size: 24, pointSize: 12)
    private let address = ToolbarAddressView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        address.onClick = { [weak self] in self?.onAction?(.address) }

        let leading = NSStackView(views: [backButton, forwardButton, reloadButton])
        leading.spacing = 2
        let trailing = NSStackView(views: [splitButton, copyButton, moreButton])
        trailing.spacing = 2
        let rule = HairlineView()
        for view in [leading, address, trailing, rule] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let centered = address.centerXAnchor.constraint(equalTo: centerXAnchor)
        centered.priority = .defaultHigh
        let preferredWidth = address.widthAnchor.constraint(equalToConstant: 520)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            leading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            leading.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
            address.centerYAnchor.constraint(equalTo: centerYAnchor),
            address.heightAnchor.constraint(equalToConstant: 24),
            centered, preferredWidth,
            address.leadingAnchor.constraint(greaterThanOrEqualTo: leading.trailingAnchor, constant: 8),
            address.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -8),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func update(tab: Tab?) {
        backButton.isEnabled = tab?.page?.canGoBack ?? false
        forwardButton.isEnabled = tab?.page?.canGoForward ?? false
        reloadButton.isEnabled = tab != nil
        reloadButton.showsStop(tab?.page?.isLoading ?? false)
        copyButton.isEnabled = tab?.url != nil
        address.update(url: tab?.url)
    }

    @objc private func backClicked() { onAction?(.back) }
    @objc private func forwardClicked() { onAction?(.forward) }
    @objc private func reloadClicked() { onAction?(.reload) }
    @objc private func splitClicked() { onAction?(.split) }
    @objc private func copyClicked() { onAction?(.copyURL) }

    @objc private func moreClicked() {
        guard let menu = moreMenu?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: moreButton.bounds.height + 4), in: moreButton)
    }
}

/// The centred address in the top bar: host in medium weight, then the path.
final class ToolbarAddressView: NSView {
    var onClick: (() -> Void)?
    private let icon = NSImageView()
    private let hostLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        icon.contentTintColor = .secondaryLabelColor
        hostLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hostLabel.lineBreakMode = .byTruncatingTail
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingTail
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [icon, hostLabel, pathLabel])
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(url: URL?) {
        guard let url else {
            icon.image = Theme.symbol("magnifyingglass", size: 10)
            hostLabel.stringValue = "Rechercher ou saisir une adresse"
            hostLabel.textColor = .secondaryLabelColor
            pathLabel.stringValue = ""
            setAccessibilityLabel("Rechercher ou saisir une adresse")
            return
        }
        let host = url.host ?? url.absoluteString
        hostLabel.stringValue = url.port.map { "\(host):\($0)" } ?? host
        hostLabel.textColor = .labelColor
        pathLabel.stringValue = url.path == "/" ? "" : url.path
        icon.image = Theme.symbol(url.scheme == "https" ? "lock.fill" : "globe", size: 10)
        setAccessibilityLabel("Adresse : \(url.absoluteString)")
    }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        layer?.cornerRadius = 7
        layer?.backgroundColor = (isDarkAppearance ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.045)).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

/// A split pane's own address: site tile, URL, and a button that takes the pane out.
/// A click elsewhere on it makes the pane active.
final class PaneHeaderView: NSView {
    var onAction: ((PageBarAction) -> Void)?
    private var tab: Tab?
    private let tile = FaviconTileView(size: 14)
    private let urlLabel = NSTextField(labelWithString: "")
    private lazy var closeButton = IconButton(symbol: "xmark", label: "Fermer ce volet", target: self, action: #selector(closeClicked), size: 22, pointSize: 9)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        urlLabel.font = .systemFont(ofSize: 12, weight: .medium)
        urlLabel.lineBreakMode = .byTruncatingMiddle
        urlLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let rule = HairlineView()
        for view in [tile, urlLabel, closeButton, rule] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            urlLabel.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 8),
            urlLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            urlLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(tab: Tab) {
        self.tab = tab
        tile.configure(url: tab.url, fallback: tab.displayTitle)
        if let url = tab.url {
            let host = url.host.map { h in url.port.map { "\(h):\($0)" } ?? h } ?? url.absoluteString
            urlLabel.stringValue = host + (url.path == "/" ? "" : url.path)
        } else {
            urlLabel.stringValue = tab.displayTitle
        }
        toolTip = tab.url?.absoluteString
    }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        layer?.backgroundColor = (isDarkAppearance ? NSColor(hex: "#2C2C2E") : NSColor(hex: "#FAFAFB")).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if let tab { onAction?(.activate(tab)) }
    }

    @objc private func closeClicked() {
        if let tab { onAction?(.closePane(tab)) }
    }
}

/// A one-pixel line in the separator colour, for the bottom of bars.
final class HairlineView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = (isDarkAppearance ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.06)).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
