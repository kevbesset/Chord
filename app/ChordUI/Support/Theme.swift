import AppKit

/// Design constants from the mockups. One place to tune the look.
enum Theme {
    static let sidebarWidth: CGFloat = 256
    /// Space left in the sidebar's first row for the window's traffic lights.
    static let trafficLightsWidth: CGFloat = 76
    /// Gap around the content card. Zero in edgeless mode.
    static let contentInset: CGFloat = 10
    static let cardRadius: CGFloat = 10
    /// How strongly the active Space colours the window glass.
    static let spaceTintAlpha: CGFloat = 0.07
    static let tabRowHeight: CGFloat = 32
    /// The sidebar's first row (traffic lights, panel toggle, navigation). Like Arc, its
    /// buttons start level with the top of the page card, so the row sits a little lower
    /// than macOS puts traffic lights.
    static let titleRowHeight: CGFloat = 30
    static var titleRowCenter: CGFloat { contentInset + titleRowHeight / 2 }
    /// The window glass: the clearest material, frosted a little so text stays legible.
    /// Together they match the mockup's 42 % white over a 40 px blur.
    static let windowMaterial = NSVisualEffectView.Material.fullScreenUI
    static let glassFrostLight = NSColor.white.withAlphaComponent(0.22)
    static let glassFrostDark = NSColor.black.withAlphaComponent(0.18)

    /// Motion: short, decelerating, close to a damped spring.
    static let motionDuration: TimeInterval = 0.28
    static let motionCurve = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.0)

    static let spacePalette = ["#5B6CFF", "#2E7D4F", "#B4530A", "#6E56CF", "#0E7490", "#C2410C"]
    /// The tint of private browsing windows: a deep violet, on their forced dark mode.
    static let privateSpaceColor = "#5A4A8C"
    private static let spaceColorNames = ["Indigo", "Vert", "Ambre", "Violet", "Bleu canard", "Orange"]

    static func colorName(_ hex: String) -> String {
        spacePalette.firstIndex(of: hex).map { spaceColorNames[$0] } ?? hex
    }

    private static let tilePalette = [
        "#4A7BF7", "#E5484D", "#6E56CF", "#F48024", "#34C759",
        "#0A84FF", "#F05138", "#24292F", "#2BB3A8", "#B4530A",
    ]

    /// A stable colour per site, for the placeholder favicon tiles.
    static func tileColor(for key: String) -> NSColor {
        var hash: UInt32 = 5381
        for byte in key.utf8 { hash = (hash &* 33) &+ UInt32(byte) }
        return NSColor(hex: tilePalette[Int(hash % UInt32(tilePalette.count))])
    }

    /// A small coloured dot, for Space menus.
    static func dot(color: NSColor, size: CGFloat = 10) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    static func symbol(_ name: String, size: CGFloat = 13, weight: NSFont.Weight = .medium) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}

extension NSColor {
    /// `#RRGGBB` in sRGB.
    convenience init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension NSView {
    var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
