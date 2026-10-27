import Foundation

extension Bundle {
    /// ChordUI's own bundle, where its translations live (`Localizable.xcstrings`). The
    /// main bundle is Chromium's.
    static let chordUI = Bundle(for: ChordUIHost.self)
}

extension Locale {
    /// The language ChordUI shows, for formatters that must match it rather than the
    /// Mac's region.
    static let chordUI = Locale(identifier: Bundle.chordUI.preferredLocalizations.first ?? "en")
}
