import AppKit

/// The address shown in the sidebar. A click opens the command bar on the current URL.
final class AddressPillView: NSView {
    var onClick: (() -> Void)?

    private let icon = NSImageView()
    private let hostLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let environmentLabel = NSTextField(labelWithString: "")

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
            environmentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            environmentLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
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
            return
        }
        let host = url.host ?? url.absoluteString
        hostLabel.stringValue = url.port.map { "\(host):\($0)" } ?? host
        hostLabel.textColor = .labelColor
        pathLabel.stringValue = url.path == "/" ? "" : url.path
        icon.image = Theme.symbol(url.scheme == "https" ? "lock.fill" : "globe", size: 11)
        environmentLabel.stringValue = Self.environment(of: url) ?? ""
        setAccessibilityLabel("Adresse : \(url.absoluteString)")
    }

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
