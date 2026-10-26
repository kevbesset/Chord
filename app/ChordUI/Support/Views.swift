import AppKit

/// Borderless SF Symbol button used across the window chrome. Like Arc's, it shows a
/// rounded square under the pointer, a little darker while pressed.
final class IconButton: NSButton {
    private let pointSize: CGFloat
    private var stopShown = false
    private var isHovered = false
    private var confirmationWork: DispatchWorkItem?
    private var restingImage: NSImage?
    private var restingTint: NSColor?

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
        wantsLayer = true
        layer?.cornerRadius = (size * 0.25).rounded()
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refreshBackground()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshBackground()
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        refreshBackground()
    }

    override var isEnabled: Bool {
        didSet { refreshBackground() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBackground()
    }

    private func refreshBackground() {
        guard isEnabled, isHovered || isHighlighted else {
            layer?.backgroundColor = nil
            return
        }
        let strength: CGFloat = isHighlighted ? 1.6 : 1
        let color = isDarkAppearance ? NSColor.white.withAlphaComponent(0.1 * strength) : NSColor.black.withAlphaComponent(0.06 * strength)
        layer?.backgroundColor = color.cgColor
    }

    /// Confirms an action on the button itself (an address copied): its icon becomes a
    /// check for a moment, with a small bounce, then comes back.
    func flashConfirmation(tint: NSColor = .controlAccentColor) {
        if confirmationWork == nil {
            restingImage = image
            restingTint = contentTintColor
        }
        confirmationWork?.cancel()
        crossfade(to: Theme.symbol("checkmark", size: pointSize, weight: .semibold), tint: tint)
        bounce()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.confirmationWork = nil
            self.crossfade(to: self.restingImage, tint: self.restingTint)
        }
        confirmationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func crossfade(to newImage: NSImage?, tint: NSColor?) {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.15
        layer?.add(fade, forKey: "confirmation")
        image = newImage
        contentTintColor = tint
    }

    /// From a little smaller back to full size, on a spring, around the centre.
    private func bounce() {
        guard let layer else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var shrunk = CATransform3DMakeTranslation(center.x, center.y, 0)
        shrunk = CATransform3DScale(shrunk, 0.78, 0.78, 1)
        shrunk = CATransform3DTranslate(shrunk, -center.x, -center.y, 0)
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = shrunk
        spring.toValue = CATransform3DIdentity
        spring.mass = 1
        spring.stiffness = 320
        spring.damping = 14
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "bounce")
    }

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
        if let builtIn = url?.builtInPageSymbol {
            currentKey = nil
            showSymbol(builtIn.name, tint: builtIn.isBrowserPage ? .systemBlue : .secondaryLabelColor)
            return
        }
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

    /// A browser page's symbol, drawn like an icon: no tile behind it.
    private func showSymbol(_ name: String, tint: NSColor) {
        imageView.image = Theme.symbol(name, size: (size * 0.82).rounded(), weight: .semibold)
        imageView.contentTintColor = tint
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = false
        letter.isHidden = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func show(_ image: NSImage?, tileColor: NSColor) {
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = nil
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
    /// A second, wide and soft shadow under the first, for views that float high
    /// above the window (the command bar), as Arc's do.
    private var ambient: CALayer?

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

    func configureAmbientShadow(opacity: Float, radius: CGFloat, offsetY: CGFloat) {
        let ambient = self.ambient ?? CALayer()
        if self.ambient == nil {
            layer?.insertSublayer(ambient, at: 0)
            self.ambient = ambient
        }
        ambient.shadowColor = NSColor.black.cgColor
        ambient.shadowOpacity = opacity
        ambient.shadowRadius = radius
        ambient.shadowOffset = CGSize(width: 0, height: offsetY)
        needsLayout = true
    }

    private func applyShadow() {
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = showsShadow ? opacity : 0
        layer?.shadowRadius = radius
        layer?.shadowOffset = CGSize(width: 0, height: offsetY)
        ambient?.isHidden = !showsShadow
    }

    override func layout() {
        super.layout()
        let r = min(cornerRadius, bounds.width / 2, bounds.height / 2)
        let path = CGPath(roundedRect: bounds, cornerWidth: r, cornerHeight: r, transform: nil)
        layer?.shadowPath = path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ambient?.frame = bounds
        ambient?.shadowPath = path
        CATransaction.commit()
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
    /// Darkens what is behind; when false it only catches the clicks outside.
    var dims = true {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        layer?.backgroundColor = dims ? NSColor.black.withAlphaComponent(isDarkAppearance ? 0.35 : 0.14).cgColor : NSColor.clear.cgColor
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
