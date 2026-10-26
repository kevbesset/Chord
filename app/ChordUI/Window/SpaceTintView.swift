import AppKit

/// The active Space's colour over the window glass, where the sidebar sits: a light
/// gradient, stronger at the top, like Arc's sidebar. The page card covers the rest.
final class SpaceTintView: NSView {
    private let gradient = CAGradientLayer()
    private var color = NSColor.clear

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(gradient)
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }

    /// Changes the colour, gliding over `duration` (instantly for 0, as during a swipe).
    func setColor(_ color: NSColor, duration: TimeInterval = 0) {
        self.color = color
        let colors = Self.colors(for: color, dark: isDarkAppearance)
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: "colors")
            animation.fromValue = gradient.presentation()?.colors ?? gradient.colors
            animation.toValue = colors
            animation.duration = duration
            animation.timingFunction = Theme.motionCurve
            gradient.add(animation, forKey: "colors")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = colors
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        setColor(color)
    }

    /// Dark glass needs a little more colour to show it.
    private static func colors(for color: NSColor, dark: Bool) -> [CGColor] {
        let (top, bottom) = dark ? (Theme.spaceTintTopDark, Theme.spaceTintBottomDark) : (Theme.spaceTintTop, Theme.spaceTintBottom)
        return [color.withAlphaComponent(top).cgColor, color.withAlphaComponent(bottom).cgColor]
    }
}
