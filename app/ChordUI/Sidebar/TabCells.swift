import AppKit

/// Base row of the sidebar list: rounded background on hover, white card when active.
class SidebarRowCellView: NSTableCellView {
    var isActive = false { didSet { refreshState() } }
    /// The other panes of the split on screen: a light background, not the white card.
    var isSoftHighlighted = false { didSet { refreshState() } }
    private(set) var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func refreshState() {
        needsDisplay = true
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.cornerRadius = 8
        let dark = isDarkAppearance
        if isActive {
            layer.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.white).cgColor
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = dark ? 0 : 0.08
            layer.shadowRadius = 2
            layer.shadowOffset = CGSize(width: 0, height: -1)
        } else {
            let soft = isSoftHighlighted
                ? (dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.white.withAlphaComponent(0.5))
                : NSColor.clear
            layer.backgroundColor = isHovered
                ? (dark ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.04)).cgColor
                : soft.cgColor
            layer.shadowOpacity = 0
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

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refreshState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshState()
    }
}

final class TabCellView: SidebarRowCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("TabCell")

    var onClose: (() -> Void)?
    private let tile = FaviconTileView(size: 16)
    private let titleLabel = NSTextField(labelWithString: "")
    private let splitIcon = NSImageView(image: Theme.symbol("rectangle.split.2x1", size: 10) ?? NSImage())
    private lazy var closeButton = IconButton(symbol: "xmark", label: "Fermer l'onglet (⌘W)", target: self, action: #selector(closeClicked), size: 20, pointSize: 9)

    init() {
        super.init(frame: .zero)
        identifier = Self.reuseID
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        splitIcon.contentTintColor = .tertiaryLabelColor
        splitIcon.toolTip = "Split view"
        for view in [tile, titleLabel, splitIcon, closeButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: splitIcon.leadingAnchor, constant: -4),
            splitIcon.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),
            splitIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(tab: Tab, selected: Bool, inSplit: Bool) {
        tile.configure(url: tab.url, fallback: tab.displayTitle)
        titleLabel.stringValue = tab.displayTitle
        titleLabel.font = .systemFont(ofSize: 13, weight: selected ? .medium : .regular)
        titleLabel.textColor = selected ? .labelColor : .secondaryLabelColor
        toolTip = tab.url?.absoluteString
        setAccessibilityLabel(tab.displayTitle)
        splitIcon.isHidden = !inSplit
        isSoftHighlighted = inSplit && !selected
        isActive = selected
    }

    override func refreshState() {
        super.refreshState()
        closeButton.isHidden = !(isHovered || isActive)
    }

    @objc private func closeClicked() { onClose?() }
}

final class NewTabCellView: SidebarRowCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("NewTabCell")

    init() {
        super.init(frame: .zero)
        identifier = Self.reuseID
        let icon = NSImageView(image: Theme.symbol("plus", size: 12, weight: .semibold) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: "Nouvel onglet")
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        let shortcut = NSTextField(labelWithString: "⌘T")
        shortcut.font = .systemFont(ofSize: 11)
        shortcut.textColor = .tertiaryLabelColor
        for view in [icon, label, shortcut] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcut.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            shortcut.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityLabel("Nouvel onglet")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

final class HeaderCellView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("HeaderCell")
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.reuseID
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .tertiaryLabelColor
        for view in [titleLabel, countLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            countLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title: String, count: Int) {
        titleLabel.stringValue = title.uppercased()
        countLabel.stringValue = count > 0 ? "\(count)" : ""
    }
}

final class SeparatorCellView: NSTableCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("SeparatorCell")

    init() {
        super.init(frame: .zero)
        identifier = Self.reuseID
        let rule = makeRule()
        addSubview(rule)
        NSLayoutConstraint.activate([
            rule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rule.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A folder of pinned tabs: icon and name aligned with the tabs, and a chevron showing
/// whether it is open. A click opens or closes it.
final class FolderCellView: SidebarRowCellView {
    static let reuseID = NSUserInterfaceItemIdentifier("FolderCell")

    private let icon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView(image: Theme.symbol("chevron.right", size: 9, weight: .semibold) ?? NSImage())

    init() {
        super.init(frame: .zero)
        identifier = Self.reuseID
        icon.contentTintColor = .secondaryLabelColor
        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        chevron.contentTintColor = .tertiaryLabelColor
        for view in [icon, nameLabel, chevron] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -6),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(folder: Folder, expanded: Bool) {
        nameLabel.stringValue = folder.name
        toolTip = folder.name
        setAccessibilityLabel("Dossier \(folder.name)")
        setExpanded(expanded)
    }

    func setExpanded(_ expanded: Bool) {
        icon.image = Theme.symbol(expanded ? "folder" : "folder.fill", size: 12)
        chevron.image = Theme.symbol(expanded ? "chevron.down" : "chevron.right", size: 9, weight: .semibold)
    }
}
