import AppKit
import Combine

/// User preferences. Stored in UserDefaults.
public final class ChordSettings {
    public enum Key {
        case edgeless, searchTemplate, appearance, addressBar, sidebarWidth, commandBar, shortcuts, pictureInPicture
    }

    public enum Appearance: String, CaseIterable {
        case automatic, light, dark

        var nsAppearance: NSAppearance? {
            switch self {
            case .automatic: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    public static let sidebarWidthRange: ClosedRange<CGFloat> = 200...400

    public let changes = PassthroughSubject<Key, Never>()
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Edgeless: the page touches the window edges, no rounded card.
    public var edgeless: Bool {
        get { defaults.bool(forKey: "edgeless") }
        set { set(newValue, "edgeless", .edgeless) }
    }

    /// Search URL; `%s` is replaced by the query.
    public var searchTemplate: String {
        get { defaults.string(forKey: "searchTemplate") ?? "https://duckduckgo.com/?q=%s" }
        set { set(newValue, "searchTemplate", .searchTemplate) }
    }

    public var appearance: Appearance {
        get { defaults.string(forKey: "appearance").flatMap(Appearance.init(rawValue:)) ?? .automatic }
        set { set(newValue.rawValue, "appearance", .appearance) }
    }

    /// Like Arc: a video playing in a tab you leave (another tab, another Space) carries
    /// on in a picture-in-picture window, and goes back into its page when you return.
    public var autoPictureInPicture: Bool {
        get { defaults.object(forKey: "autoPictureInPicture") as? Bool ?? true }
        set { set(newValue, "autoPictureInPicture", .pictureInPicture) }
    }

    /// The address and navigation buttons sit in a 32 px bar on top of the page
    /// (Safari style) instead of the sidebar (Arc style). The default: a profile can
    /// choose its own place (`BrowserState.setAddressBarOnTop(_:for:)`).
    public var addressBarOnTop: Bool {
        get { defaults.bool(forKey: "addressBarOnTop") }
        set { set(newValue, "addressBarOnTop", .addressBar) }
    }

    public var sidebarWidth: CGFloat {
        get {
            let stored = defaults.double(forKey: "sidebarWidth")
            return stored > 0 ? min(max(CGFloat(stored), Self.sidebarWidthRange.lowerBound), Self.sidebarWidthRange.upperBound) : Theme.sidebarWidth
        }
        set { set(Double(newValue), "sidebarWidth", .sidebarWidth) }
    }

    /// The command bar's look: translucent glass, or an opaque panel.
    public var commandBarGlass: Bool {
        get { defaults.object(forKey: "commandBarGlass") as? Bool ?? true }
        set { set(newValue, "commandBarGlass", .commandBar) }
    }

    /// Whether Chord already offered to import Arc's sidebar.
    public var arcImportOffered: Bool {
        get { defaults.bool(forKey: "arcImportOffered") }
        set { defaults.set(newValue, forKey: "arcImportOffered") }
    }

    /// Remapped shortcuts, by menu item identifier. See `MainMenu`.
    public var shortcutOverrides: [String: String] {
        get { defaults.dictionary(forKey: "shortcutOverrides") as? [String: String] ?? [:] }
        set { set(newValue, "shortcutOverrides", .shortcuts) }
    }

    func searchURL(for query: String) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        return URL(string: searchTemplate.replacingOccurrences(of: "%s", with: encoded))
    }

    private func set(_ value: Any, _ key: String, _ change: Key) {
        defaults.set(value, forKey: key)
        changes.send(change)
    }
}
