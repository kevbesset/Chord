import AppKit

/// The address shown in the sidebar. A click opens the command bar on the current URL;
/// the buttons on the right, shown while the pointer is in the sidebar, copy the address
/// and open the site's controls, like Arc's.
final class AddressPillView: NSView {
    var onClick: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSiteControls: ((NSView) -> Void)?

    /// Set by the sidebar on hover; the buttons only show when there is an address.
    var showsButtons = false {
        didSet { refreshButtons() }
    }

    /// Keeps the buttons shown while something hangs from them (a site's question).
    var pinsButtons = false {
        didSet { refreshButtons() }
    }

    /// The site controls button, which a site's question hangs from.
    var siteControlsAnchor: NSView { siteControlsButton }

    /// What the pinned extensions' buttons do.
    var extensionActions: ExtensionActions?
    private var extensionButtons: [ExtensionButton] = []

    private let icon = NSImageView()
    /// Shown only for a site without encryption that is not local.
    private let insecureLabel = NSTextField(labelWithString: String(localized: "Not Secure", bundle: .chordUI))
    private let addressLabel = NSTextField(labelWithString: "")
    private lazy var copyButton = IconButton(symbol: "link", label: String(localized: "Copy URL (⇧⌘C)", bundle: .chordUI), target: self, action: #selector(copyClicked), size: 24, pointSize: 12)
    private lazy var siteControlsButton = IconButton(symbol: "slider.horizontal.2.square", label: String(localized: "Site Settings", bundle: .chordUI), target: self, action: #selector(siteControlsClicked), size: 24, pointSize: 14)
    private lazy var buttons = NSStackView(views: [copyButton, siteControlsButton])
    private var hasURL = false
    private var addressToEdge: NSLayoutConstraint!
    private var addressToButtons: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9

        icon.contentTintColor = .secondaryLabelColor
        insecureLabel.font = .systemFont(ofSize: 12)
        insecureLabel.textColor = .secondaryLabelColor
        insecureLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addressLabel.font = .systemFont(ofSize: 13, weight: .medium)
        addressLabel.lineBreakMode = .byTruncatingTail
        addressLabel.maximumNumberOfLines = 1
        addressLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        buttons.spacing = 0
        buttons.isHidden = true
        buttons.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttons)

        let stack = NSStackView(views: [icon, insecureLabel, addressLabel])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.setCustomSpacing(8, after: insecureLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // The address makes room for the buttons rather than sliding under them.
        addressToEdge = stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        addressToButtons = stack.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -4)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            addressToEdge,
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
            icon.isHidden = false
            insecureLabel.isHidden = true
            addressLabel.stringValue = String(localized: "Search or enter URL", bundle: .chordUI)
            addressLabel.textColor = .secondaryLabelColor
            setAccessibilityLabel(String(localized: "Search or enter URL", bundle: .chordUI))
            hasURL = false
            refreshButtons()
            return
        }
        addressLabel.attributedStringValue = url.addressText(size: 13)
        icon.image = Theme.symbol("lock.slash", size: 11)
        icon.isHidden = !url.isInsecure
        insecureLabel.isHidden = !url.isInsecure
        setAccessibilityLabel((url.isInsecure ? String(localized: "Not secure. ", bundle: .chordUI) : "") + String(localized: "Address: \(url.absoluteString)", bundle: .chordUI))
        hasURL = true
        refreshButtons()
    }

    /// The pinned extensions, before the copy button, like Arc's.
    func setExtensions(_ items: [PageExtension]) {
        guard let extensionActions else { return }
        for button in extensionButtons {
            buttons.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        extensionButtons = items.map { ExtensionButton(item: $0, actions: extensionActions, size: 24, iconSize: 15) }
        for (index, button) in extensionButtons.enumerated() {
            buttons.insertArrangedSubview(button, at: index)
        }
    }

    private func refreshButtons() {
        let shown = (showsButtons || pinsButtons) && hasURL
        guard buttons.isHidden == shown else { return }
        buttons.isHidden = !shown
        addressToEdge.isActive = !shown
        addressToButtons.isActive = shown
    }

    @objc private func copyClicked() {
        onCopy?()
        copyButton.flashConfirmation()
    }
    @objc private func siteControlsClicked() { onSiteControls?(siteControlsButton) }

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
