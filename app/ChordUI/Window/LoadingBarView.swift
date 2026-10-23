import AppKit

/// Arc-style loading indicator: a thin line across the top of the page in the Space
/// colour, with a light sweeping left to right while the page loads. It fades in and
/// out, so quick loads barely show. Clicks go through to the page.
final class LoadingBarView: NSView {
    private let track = CALayer()
    private let sweep = CAGradientLayer()
    private var accent = NSColor.controlAccentColor
    private(set) var isLoading = false

    static let height: CGFloat = 2.5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(track)
        layer?.addSublayer(sweep)
        sweep.startPoint = CGPoint(x: 0, y: 0.5)
        sweep.endPoint = CGPoint(x: 1, y: 0.5)
        alphaValue = 0
        setAccessibilityElement(false)
        // Web views composite their own layers above their siblings: stay in front.
        layer?.zPosition = 100
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setLoading(_ loading: Bool, accent: NSColor) {
        if accent != self.accent {
            self.accent = accent
            applyColors()
        }
        guard loading != isLoading else { return }
        isLoading = loading
        if loading {
            startSweep()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                self.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                self.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, !self.isLoading else { return }
                self.sweep.removeAnimation(forKey: "sweep")
            })
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = bounds
        sweep.frame = NSRect(x: 0, y: 0, width: max(80, bounds.width * 0.35), height: bounds.height)
        CATransaction.commit()
        applyColors()
        if isLoading { startSweep() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        track.backgroundColor = accent.withAlphaComponent(isDarkAppearance ? 0.28 : 0.2).cgColor
        sweep.colors = [accent.withAlphaComponent(0).cgColor, accent.cgColor, accent.withAlphaComponent(0).cgColor]
    }

    /// The light runs from beyond the left edge to beyond the right one, again and again.
    private func startSweep() {
        let width = sweep.bounds.width
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = -width / 2
        animation.toValue = bounds.width + width / 2
        animation.duration = 1.1
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.repeatCount = .infinity
        sweep.add(animation, forKey: "sweep")
    }
}
