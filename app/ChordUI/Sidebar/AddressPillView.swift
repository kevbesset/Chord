import AppKit

/// The address shown in the sidebar. A click opens the command bar on the current URL;
/// the buttons on the right, shown while the pointer is in the sidebar, open the site's
/// controls (like Arc's) and copy the address.
final class AddressPillView: NSView {
    var onClick: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSiteControls: ((NSView) -> Void)?

    /// Set by the sidebar on hover; the buttons only show when there is an address.
    var showsButtons = false {
        didSet { refreshButtons() }
    }

    private let icon = NSImageView()
    private let hostLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let environmentLabel = NSTextField(labelWithString: "")
    private lazy var copyButton = IconButton(symbol: "link", label: "Copier l'URL (⇧⌘C)", target: self, action: #selector(copyClicked), size: 24, pointSize: 12)
    private lazy var siteControlsButton = IconButton(symbol: "switch.2", label: "Réglages du site", target: self, action: #selector(siteControlsClicked), size: 24, pointSize: 12)
    private lazy var buttons = NSStackView(views: [siteControlsButton, copyButton])
    private var hasURL = false
    private var environmentToEdge: NSLayoutConstraint!
    private var environmentToButton: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9

        icon.contentTintColor = .secondaryLabelColor
        hostLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hostLabel.lineBreakMode = .byTruncatingTail
        hostLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingTail
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        environmentLabel.font = .systemFont(ofSize: 11)
        environmentLabel.textColor = .secondaryLabelColor
        environmentLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        environmentLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(environmentLabel)
        buttons.spacing = 0
        buttons.isHidden = true
        buttons.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttons)
        environmentToEdge = environmentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        environmentToButton = environmentLabel.trailingAnchor.constraint(equalTo: buttons.leadingAnchor, constant: -4)

        let stack = NSStackView(views: [icon, hostLabel, pathLabel])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: environmentLabel.leadingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            environmentToEdge,
            environmentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        update(url: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(url: URL?) {
        guard let url else {
            icon.image = Theme.symbol("magnifyingglass", size: 11)
            hostLabel.stringValue = "Rechercher ou saisir une adresse"
            hostLabel.textColor = .secondaryLabelColor
            pathLabel.stringValue = ""
            environmentLabel.stringValue = ""
            setAccessibilityLabel("Rechercher ou saisir une adresse")
            hasURL = false
            refreshButtons()
            return
        }
        hostLabel.stringValue = url.displayHost
        hostLabel.textColor = .labelColor
        pathLabel.stringValue = url.path == "/" ? "" : url.path
        icon.image = Theme.symbol(url.addressSymbol, size: 11)
        environmentLabel.stringValue = Self.environment(of: url) ?? ""
        setAccessibilityLabel("Adresse : \(url.absoluteString)")
        hasURL = true
        refreshButtons()
    }

    private func refreshButtons() {
        let shown = showsButtons && hasURL
        guard buttons.isHidden == shown else { return }
        buttons.isHidden = !shown
        // The environment badge makes room for the buttons rather than sliding under them.
        environmentToEdge.isActive = !shown
        environmentToButton.isActive = shown
    }

    @objc private func copyClicked() { onCopy?() }
    @objc private func siteControlsClicked() { onSiteControls?(siteControlsButton) }

    /// Developers jump between environments all day: name the one this page is on.
    static func environment(of url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let labels = host.split(separator: ".").map(String.init)
        let local: Set<String> = ["localhost", "local", "test", "internal", "lan"]
        let isIPv4 = labels.count == 4 && labels.allSatisfy { Int($0) != nil }
        if host == "localhost" || isIPv4 || local.contains(labels.last ?? "") { return "dev" }
        for name in ["staging", "preprod", "preview", "qa", "dev"] where labels.dropLast().contains(where: { $0 == name || $0.hasPrefix(name + "-") }) {
            return name
        }
        return nil
    }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(isDarkAppearance ? 0.08 : 0.72).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.black.withAlphaComponent(isDarkAppearance ? 0.3 : 0.05).cgColor
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
