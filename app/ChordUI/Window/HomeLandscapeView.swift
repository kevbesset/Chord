import AppKit

/// The landscape behind the home page, the same as the presentation page's: misty blue
/// ridges, and Chord's mark in the sky, the sun by day and the moon by night (the arc
/// lit, the chord its edge). Built once from Core Animation layers; a resize only moves
/// them, and a change of appearance glides the mark from one side of the sky to the other.
final class HomeLandscapeView: NSView {
    /// Where the home page's words sit (in this view's coordinates): a bank of mist
    /// behind them keeps them readable over the ridges.
    var hazeRect: NSRect = .zero { didSet { if hazeRect != oldValue { needsLayout = true } } }

    private let scene = CALayer()
    private let sky = CAGradientLayer()
    private let stars = CALayer()
    private let orb = CALayer()
    private let glow = CAGradientLayer()
    private let darkSide = CAShapeLayer()
    private let face = CAGradientLayer()
    private let faceShape = CAShapeLayer()
    private let chord = CAShapeLayer()
    private let land = CALayer()
    private var ridges: [(fill: CAGradientLayer, mist: CAGradientLayer)] = []
    private let haze = CAGradientLayer()

    /// The landscape is drawn in a 1600 × 1000 box, scaled to cover the view and kept
    /// on its bottom edge (SVG's `xMidYMax slice`).
    private static let box = CGSize(width: 1600, height: 1000)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        // Everything below reads top to bottom, like the SVG it comes from.
        scene.isGeometryFlipped = true
        layer?.addSublayer(scene)

        sky.locations = [0, 0.55]
        sky.startPoint = CGPoint(x: 0.5, y: 0)
        sky.endPoint = CGPoint(x: 0.5, y: 1)
        scene.addSublayer(sky)

        stars.bounds = CGRect(origin: .zero, size: Self.box)
        stars.anchorPoint = .zero
        for (index, dots) in Self.starDots().enumerated() {
            let group = CAShapeLayer()
            group.path = dots
            group.fillColor = NSColor.white.cgColor
            group.opacity = [0.45, 0.7, 1][index]
            stars.addSublayer(group)
        }
        scene.addSublayer(stars)

        glow.type = .radial
        glow.locations = [0, 0.62, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        face.startPoint = .zero
        face.endPoint = CGPoint(x: 0.8, y: 1)
        face.mask = faceShape
        chord.lineCap = .round
        chord.fillColor = nil
        for sublayer in [glow, darkSide, face, chord] { orb.addSublayer(sublayer) }
        scene.addSublayer(orb)

        land.bounds = CGRect(origin: .zero, size: Self.box)
        land.anchorPoint = .zero
        for ridge in Self.ridges {
            let path = Self.ridgePath(ridge)
            let frame = path.boundingBoxOfPath
            let container = CALayer()
            container.frame = frame
            let mask = CAShapeLayer()
            var offset = CGAffineTransform(translationX: -frame.minX, y: -frame.minY)
            mask.path = path.copy(using: &offset)
            container.mask = mask
            let fill = CAGradientLayer()
            fill.frame = container.bounds
            fill.startPoint = CGPoint(x: 0, y: 0.5)
            fill.endPoint = CGPoint(x: 1, y: 0.5)
            // Mist gathers at the foot of each ridge.
            let mist = CAGradientLayer()
            mist.frame = container.bounds
            mist.locations = [0, 0.55, 1]
            container.addSublayer(fill)
            container.addSublayer(mist)
            land.addSublayer(container)
            ridges.append((fill, mist))
        }
        scene.addSublayer(land)

        haze.type = .radial
        haze.locations = [0, 0.6, 1]
        haze.startPoint = CGPoint(x: 0.5, y: 0.5)
        haze.endPoint = CGPoint(x: 1, y: 1)
        scene.addSublayer(haze)

        applyAppearance(animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        scene.frame = bounds
        sky.frame = bounds
        let scale = max(bounds.width / Self.box.width, bounds.height / Self.box.height)
        let origin = CGPoint(x: (bounds.width - Self.box.width * scale) / 2, y: bounds.height - Self.box.height * scale)
        for layer in [stars, land] {
            layer.position = origin
            layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
        placeOrb()
        // The mist, wider than the words, in the scene's top-down coordinates.
        let words = hazeRect.insetBy(dx: -200, dy: -150)
        haze.frame = CGRect(x: words.minX, y: bounds.height - words.maxY, width: words.width, height: words.height)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance(animated: window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    // MARK: - The mark: sun or moon

    /// Sets the mark's size and place: on the left, low in the sky by day; on the right,
    /// higher, by night.
    private func placeOrb() {
        let night = isDarkAppearance
        let size = min(max(bounds.width * 0.25, 160), 400)
        let x = bounds.width * 0.03 + (bounds.width * 0.94 - size) * (night ? 1 : 0)
        let y = bounds.height * (night ? 0.22 : 0.35) - size / 2
        orb.frame = CGRect(x: x, y: y, width: size, height: size)

        // The SVG's geometry: radius 100 in a 320 unit box centred on 0.
        let unit = size / 320
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = 100 * unit
        let edge = 70.7 * unit
        glow.frame = orb.bounds
        darkSide.path = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), transform: nil)
        face.frame = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let shape = CGMutablePath()
        shape.addArc(center: CGPoint(x: radius, y: radius), radius: radius, startAngle: -.pi / 4, endAngle: .pi / 4, clockwise: true)
        shape.closeSubpath()
        faceShape.path = shape
        let line = CGMutablePath()
        line.move(to: CGPoint(x: center.x + edge, y: center.y + edge))
        line.addLine(to: CGPoint(x: center.x + edge, y: center.y - edge))
        chord.path = line
        chord.lineWidth = 7 * unit
    }

    private func applyAppearance(animated: Bool) {
        let palette = isDarkAppearance ? Palette.night : Palette.day
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(1.8)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.45, 0, 0.2, 1))
        } else {
            CATransaction.setDisableActions(true)
        }
        sky.colors = [palette.skyTop.cgColor, palette.skyBottom.cgColor]
        stars.opacity = palette.stars
        glow.colors = [palette.glow.withAlphaComponent(palette.glowOpacity).cgColor,
                       palette.glow.withAlphaComponent(palette.glowOpacity).cgColor,
                       palette.glow.withAlphaComponent(0).cgColor]
        darkSide.fillColor = palette.darkSide.cgColor
        face.colors = [palette.face.0.cgColor, palette.face.1.cgColor]
        chord.strokeColor = palette.chord.cgColor
        for (ridge, colors) in zip(ridges, palette.ridges) {
            ridge.fill.colors = [colors.0.cgColor, colors.1.cgColor]
            ridge.mist.colors = [palette.mist.withAlphaComponent(0).cgColor,
                                 palette.mist.withAlphaComponent(0.14).cgColor,
                                 palette.mist.withAlphaComponent(0.45).cgColor]
        }
        haze.colors = [palette.haze.withAlphaComponent(0.82).cgColor,
                       palette.haze.withAlphaComponent(0.4).cgColor,
                       palette.haze.withAlphaComponent(0).cgColor]
        placeOrb()
        CATransaction.commit()
    }

    // MARK: - Colours

    private struct Palette {
        let skyTop, skyBottom: NSColor
        let face: (NSColor, NSColor)
        let darkSide, glow, chord, mist, haze: NSColor
        let glowOpacity: CGFloat
        let stars: Float
        /// Back to front, left colour then right colour.
        let ridges: [(NSColor, NSColor)]

        static let day = Palette(
            skyTop: NSColor(hex: "#BFC5DB"), skyBottom: NSColor(hex: "#DAD6DE"),
            face: (NSColor(hex: "#FFF9F0"), NSColor(hex: "#FCEBDB")),
            darkSide: .clear, glow: NSColor(hex: "#FFE6CC"), chord: NSColor(hex: Theme.spacePalette[0]),
            mist: NSColor(hex: "#E6E3EC"), haze: NSColor(hex: "#DEDBE4"),
            glowOpacity: 0.3, stars: 0,
            ridges: [("#B6BFDC", "#BEC4DB"), ("#8CA1DB", "#B6BEDB"), ("#A0B0DF", "#93A7E0"), ("#6B8CDF", "#7A97E2"),
                     ("#577CDC", "#5D82E2"), ("#4974D3", "#4571D0"), ("#4370A8", "#4671C9"), ("#3F6B8B", "#3D6970")]
                .map { (NSColor(hex: $0.0), NSColor(hex: $0.1)) })

        static let night = Palette(
            skyTop: NSColor(hex: "#060A22"), skyBottom: NSColor(hex: "#1D2858"),
            face: (NSColor(hex: "#F6F5FF"), NSColor(hex: "#C6CAF0")),
            darkSide: NSColor(srgbRed: 120 / 255, green: 132 / 255, blue: 220 / 255, alpha: 0.16),
            glow: NSColor(hex: "#8FA0FF"), chord: NSColor(hex: "#8FA0FF"),
            mist: NSColor(hex: "#34418C"), haze: NSColor(hex: "#0B1030"),
            glowOpacity: 0.42, stars: 1,
            ridges: [("#222B5C", "#212956"), ("#21306E", "#1C2658"), ("#25347A", "#23337A"), ("#203183", "#223488"),
                     ("#1D2F87", "#1F328D"), ("#1A2B78", "#1A2A74"), ("#162954", "#18286B"), ("#11273A", "#10252B")]
                .map { (NSColor(hex: $0.0), NSColor(hex: $0.1)) })
    }

    // MARK: - Geometry

    /// A ridge: its line through key points, and gentle waves on top (phases fixed, so
    /// the range is the same as the presentation page's).
    private struct Ridge {
        let keys: [CGPoint]
        let amplitude: CGFloat
        let phases: [CGFloat]
    }

    private static let ridges: [Ridge] = [
        // far misty hills on the left, the sun sinks behind them
        ridge([(-60, 430), (300, 440), (520, 470), (760, 520), (1660, 560)], 18, [1.4944, 3.4178, 2.3233]),
        // the great mass on the right, rising steeply like a cliff
        ridge([(-60, 560), (640, 520), (760, 470), (850, 350), (980, 315), (1200, 300), (1420, 290), (1660, 280)], 22, [2.0337, 0.9473, 4.0879]),
        // a pale ridge across
        ridge([(-60, 560), (300, 540), (600, 560), (900, 600), (1200, 600), (1660, 610)], 20, [2.8409, 3.5154, 5.804]),
        // hills on the left
        ridge([(-60, 600), (200, 615), (450, 640), (700, 690), (1660, 760)], 22, [3.2781, 5.066, 6.0319]),
        // the strong mass on the right
        ridge([(-60, 760), (520, 730), (760, 640), (860, 560), (1050, 520), (1300, 470), (1500, 450), (1660, 470)], 24, [5.8082, 5.9572, 5.6045]),
        // the middle
        ridge([(-60, 740), (300, 760), (600, 790), (900, 720), (1200, 640), (1660, 600)], 22, [3.4422, 2.1718, 5.3057]),
        // a teal ridge
        ridge([(-60, 820), (400, 830), (700, 820), (1000, 880), (1300, 900), (1660, 920)], 20, [0.0771, 0.7059, 2.467]),
        // the foreground
        ridge([(-60, 900), (400, 910), (800, 930), (1150, 880), (1350, 900), (1660, 950)], 18, [4.283, 0.5753, 3.8799]),
    ]

    private static func ridge(_ keys: [(CGFloat, CGFloat)], _ amplitude: CGFloat, _ phases: [CGFloat]) -> Ridge {
        Ridge(keys: keys.map { CGPoint(x: $0.0, y: $0.1) }, amplitude: amplitude, phases: phases)
    }

    /// The ridge's outline, sampled every 32 units and smoothed into curves
    /// (Catmull-Rom), closed along the bottom of the box.
    private static func ridgePath(_ ridge: Ridge) -> CGPath {
        let waves: [(frequency: CGFloat, amplitude: CGFloat)] = [(1 / 420, 1), (1 / 190, 0.55), (1 / 85, 0.22)]
        func height(_ x: CGFloat) -> CGFloat {
            var y = ridge.keys.last!.y
            for (a, b) in zip(ridge.keys, ridge.keys.dropFirst()) where a.x <= x && x <= b.x {
                let t = (1 - cos((x - a.x) / (b.x - a.x) * .pi)) / 2
                y = a.y + (b.y - a.y) * t
                break
            }
            let noise = zip(waves, ridge.phases).reduce(CGFloat(0)) { sum, wave in
                sum + wave.0.amplitude * sin(x * wave.0.frequency * 6.28 + wave.1)
            }
            return y + ridge.amplitude * noise / 1.77 + 55
        }
        let points = stride(from: CGFloat(-60), through: 1660, by: 32).map { CGPoint(x: $0, y: height($0)) }
        let path = CGMutablePath()
        path.move(to: points[0])
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.addLine(to: CGPoint(x: points.last!.x, y: box.height))
        path.addLine(to: CGPoint(x: points[0].x, y: box.height))
        path.closeSubpath()
        return path
    }

    /// Seventy stars in the top half of the sky, in three brightnesses.
    private static func starDots() -> [CGPath] {
        var seed: UInt64 = 4
        func random() -> CGFloat {
            seed &+= 0x9E37_79B9_7F4A_7C15
            var z = seed
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return CGFloat(z ^ (z >> 31)) / CGFloat(UInt64.max)
        }
        let groups = [CGMutablePath(), CGMutablePath(), CGMutablePath()]
        for _ in 0..<70 {
            let x = random() * box.width
            let y = pow(random() * 470, 1.15) / pow(470, 0.15)
            let radius = [0.8, 1, 1, 1.3, 1.7][Int(random() * 4.999)]
            groups[Int(random() * 2.999)].addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        return groups
    }
}
