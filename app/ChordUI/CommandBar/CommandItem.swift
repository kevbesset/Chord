import Foundation

/// One result in the command bar.
struct CommandItem {
    enum Action {
        case switchTab(Tab)
        case open(URL)
        case search(String)
        case run(() -> Void)
    }

    /// Results are grouped by section, in order of appearance.
    var section: String
    var title: String
    var subtitle: String? = nil
    /// SF Symbol shown when there is no site tile.
    var symbol: String? = nil
    /// Shows a site tile for this URL instead of a symbol.
    var tileURL: URL? = nil
    var shortcut: String? = nil
    var action: Action
}
