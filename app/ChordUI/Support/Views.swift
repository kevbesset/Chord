import AppKit

/// Borderless SF Symbol button used across the window chrome.
final class IconButton: NSButton {
    private let pointSize: CGFloat
    private var stopShown = false

    init(symbol: String, label: String, target: AnyObject?, action: Selector?, size: CGFloat = 26, pointSize: CGFloat = 13) {
        self.pointSize = pointSize
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        image = Theme.symbol(symbol, size: pointSize)
        imagePosition = .imageOnly
        title = ""
        isBordered = false
        toolTip = label
        setAccessibilityLabel(label)
        self.target = target
        self.action = action
        contentTintColor = .secondaryLabelColor
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }

    /// Turns a reload button into a stop button while the page loads, and back.
    func showsStop(_ stop: Bool) {
        guard stop != stopShown else { return }
        stopShown = stop
        image = Theme.symbol(stop ? "xmark" : "arrow.clockwise", size: stop ? pointSize - 1 : pointSize)
        toolTip = stop ? "Arrêter (⌘.)" : "Recharger (⌘R)"
        setAccessibilityLabel(stop ? "Arrêter le chargement" : "Recharger")
    }
}

/// A site's icon. Until the real one is known (or when the site has none), a coloured
/// square with the site's initial stands in for it.
final class FaviconTileView: NSView {
    private let letter = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private let size: CGFloat
    /// The site shown, so that an icon arriving for a recycled cell is ignored.
    private var currentKey: String?

    init(size: CGFloat = 16) {
        self.size = size
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.cornerRadius = (size * 0.25).rounded()
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        letter.font = .systemFont(ofSize: (size * 0.56).rounded(), weight: .bold)
        letter.textColor = .white
        letter.alignment = .center
        letter.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        addSubview(letter)
        addSubview(imageView)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            letter.centerXAnchor.constraint(equalTo: centerXAnchor),
            letter.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(url: URL?, fallback: String) {
        var key = url?.host ?? fallback
        if key.hasPrefix("www.") { key.removeFirst(4) }
        letter.stringValue = key.first.map { String($0).uppercased() } ?? "·"
        let tileColor = Theme.tileColor(for: key)

        let iconKey = url.flatMap(FaviconStore.key(for:))
        currentKey = iconKey
        let icon = FaviconStore.shared.icon(for: url) { [weak self] image in
            guard let self, self.currentKey == iconKey else { return }
            self.show(image, tileColor: tileColor)
        }
        show(icon, tileColor: tileColor)
    }

    private func show(_ image: NSImage?, tileColor: NSColor) {
        imageView.image = image
        imageView.isHidden = image == nil
        letter.isHidden = image != nil
        // Real icons draw their own shape; only the stand-in gets the coloured square.
        layer?.backgroundColor = image == nil ? tileColor.cgColor : NSColor.clear.cgColor
        layer?.cornerRadius = image == nil ? (size * 0.25).rounded() : (size * 0.18).rounded()
    }
}

/// Draws a soft shadow under rounded content without an offscreen pass:
/// the shadow path is set explicitly on every layout.
final class ShadowHostView: NSView {
    var cornerRadius: CGFloat = Theme.cardRadius { didSet { needsLayout = true } }
    var showsShadow = true { didSet { applyShadow() } }
    private var opacity: Float = 0.08
    private var radius: CGFloat = 3
    private var offsetY: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        applyShadow()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configureShadow(opacity: Float, radius: CGFloat, offsetY: CGFloat) {
        self.opacity = opacity
        self.radius = radius
        self.offsetY = offsetY
        applyShadow()
    }

    private func applyShadow() {
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = showsShadow ? opacity : 0
        layer?.shadowRadius = radius
        layer?.shadowOffset = CGSize(width: 0, height: offsetY)
    }

    override func layout() {
        super.layout()
        let r = min(cornerRadius, bounds.width / 2, bounds.height / 2)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: r, cornerHeight: r, transform: nil)
    }
}

/// A light veil over the window glass: white in light mode, black in dark mode.
final class GlassFrostView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = (isDarkAppearance ? Theme.glassFrostDark : Theme.glassFrostLight).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

extension NSWindow {
    /// Treats a click on empty chrome like a click on a title bar: dragging moves the
    /// window, a double-click does what the system setting says (zoom by default).
    func handleChromeMouseDown(_ event: NSEvent) {
        guard event.clickCount == 2 else {
            performDrag(with: event)
            return
        }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": performMiniaturize(nil)
        case "None": break
        default: performZoom(nil)
        }
    }
}

/// An invisible strip on the window's left edge. Hovering it reveals the hidden sidebar.
/// Clicks pass through to the page underneath.
final class EdgeHoverView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

/// Dims what is behind a modal overlay. A click dismisses it.
final class ScrimView: NSView {
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.black.withAlphaComponent(isDarkAppearance ? 0.35 : 0.14).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// A one-pixel horizontal separator.
func makeRule() -> NSView {
    let rule = NSBox()
    rule.boxType = .separator
    rule.translatesAutoresizingMaskIntoConstraints = false
    return rule
}
