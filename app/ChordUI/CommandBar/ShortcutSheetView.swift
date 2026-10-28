import AppKit

/// The cheat sheet at the bottom of the command bar, as Chord's vision has it: Arc's main
/// shortcuts, as remapped in the settings, for an empty query.
final class ShortcutSheetView: NSView {
    private typealias C = BrowserWindowController
    private let grid = NSGridView()

    /// The actions shown, in reading order; the shortcuts come from the menu bar.
    private static let entries: [(title: String, action: Selector)] = [
        (String(localized: "New Tab", bundle: .chordUI), #selector(C.newTab(_:))),
        (String(localized: "Sidebar", bundle: .chordUI), #selector(C.toggleSidebarVisibility(_:))),
        (String(localized: "Split View", bundle: .chordUI), #selector(C.toggleSplitView(_:))),
        (String(localized: "Little Window", bundle: .chordUI), #selector(C.newLittleWindow(_:))),
        (String(localized: "Copy URL", bundle: .chordUI), #selector(C.copyURL(_:))),
        (String(localized: "Pin Tab", bundle: .chordUI), #selector(C.togglePinTab(_:))),
        (String(localized: "Next Space", bundle: .chordUI), #selector(C.nextSpace(_:))),
        (String(localized: "History", bundle: .chordUI), #selector(C.showHistory(_:))),
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        grid.rowSpacing = 6
        grid.columnSpacing = 14
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -22),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Keyboard shortcuts", bundle: .chordUI))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Reads the shortcuts again: they may have been remapped since.
    func refresh() {
        while grid.numberOfRows > 0 { grid.removeRow(at: 0) }
        var cells: [NSView] = Self.entries.compactMap { entry in
            MainMenu.shortcutDisplay(for: entry.action).map { cell(keys: $0, title: entry.title) }
        }
        // Peek has no menu item: it is a ⇧-click on a link, like Arc's.
        cells.append(cell(keys: String(localized: "⇧-click", bundle: .chordUI), title: String(localized: "Peek", bundle: .chordUI)))
        let columns = 3
        var row: [NSView] = []
        for view in cells {
            row.append(view)
            if row.count == columns {
                grid.addRow(with: row)
                row = []
            }
        }
        if !row.isEmpty { grid.addRow(with: row + Array(repeating: NSGridCell.emptyContentView, count: columns - row.count)) }
        setAccessibilityChildren(cells)
    }

    private func cell(keys: String, title: String) -> NSView {
        let key = NSTextField(labelWithString: keys)
        key.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        key.textColor = .labelColor
        key.alignment = .center
        key.wantsLayer = true
        key.layer?.cornerRadius = 4
        key.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.35).cgColor
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        let pair = NSStackView(views: [key, label])
        pair.spacing = 6
        key.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        pair.setAccessibilityElement(true)
        pair.setAccessibilityRole(.staticText)
        pair.setAccessibilityLabel("\(title), \(keys)")
        pair.setAccessibilityChildren([])
        return pair
    }
}
