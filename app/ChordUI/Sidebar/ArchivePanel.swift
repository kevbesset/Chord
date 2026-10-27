import AppKit
import Combine

/// The archive, like Arc's: today's tabs closed with ⌘W or left unused for a while
/// (Settings › General), newest first, with a search. A click opens the tab again in
/// its Space.
final class ArchivePanelController: NSViewController, NSSearchFieldDelegate {
    var onRestore: ((ArchivedTab) -> Void)?
    var onClear: (() -> Void)?

    private let state: BrowserState
    private let search = NSSearchField()
    private let list = NSStackView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private lazy var clearButton = NSButton(title: String(localized: "Clear", bundle: .chordUI), target: self, action: #selector(clear))
    private var scrollHeight: NSLayoutConstraint!

    static let width: CGFloat = 340
    private static let rowHeight: CGFloat = 40
    private static let maxRows = 9

    private static let ageFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .chordUI
        formatter.unitsStyle = .short
        return formatter
    }()

    init(state: BrowserState) {
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let title = NSTextField(labelWithString: String(localized: "Archived Tabs", bundle: .chordUI))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 12)
        clearButton.contentTintColor = .controlAccentColor
        let header = NSStackView(views: [title, NSView(), clearButton])
        header.distribution = .fill

        search.placeholderString = String(localized: "Search archived tabs", bundle: .chordUI)
        search.delegate = self
        search.controlSize = .regular

        list.orientation = .vertical
        list.alignment = .width
        list.spacing = 0
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        list.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        let column = NSStackView(views: [header, search, scroll, emptyLabel])
        column.orientation = .vertical
        column.alignment = .width
        column.spacing = 8
        column.edgeInsets = NSEdgeInsets(top: 12, left: 10, bottom: 10, right: 10)
        column.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(column)
        scrollHeight = scroll.heightAnchor.constraint(equalToConstant: Self.rowHeight)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.width),
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -8),
            scrollHeight,
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            list.topAnchor.constraint(equalTo: document.topAnchor),
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        search.stringValue = ""
        reload()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(search)
    }

    func controlTextDidChange(_ obj: Notification) {
        reload()
    }

    /// ↩ in the search opens the first tab found.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)), let first = matches.first else { return false }
        onRestore?(first)
        return true
    }

    private var matches: [ArchivedTab] {
        let query = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return state.archive }
        return state.archive.filter {
            $0.displayTitle.lowercased().contains(query) || ($0.url?.absoluteString.lowercased().contains(query) ?? false)
        }
    }

    func reload() {
        guard isViewLoaded else { return }
        let items = matches
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items.prefix(200) {
            let row = ArchivedTabRowView(item: item, age: age(of: item), space: state.spaces.first { $0.id == item.spaceID })
            row.onClick = { [weak self] in self?.onRestore?(item) }
            list.addArrangedSubview(row)
        }
        emptyLabel.stringValue = state.archive.isEmpty
            ? String(localized: "No archived tabs", bundle: .chordUI)
            : String(localized: "No archived tab matches", bundle: .chordUI)
        emptyLabel.isHidden = !items.isEmpty
        scroll.isHidden = items.isEmpty
        clearButton.isEnabled = !state.archive.isEmpty
        scrollHeight.constant = Self.rowHeight * CGFloat(min(max(items.count, 1), Self.maxRows))
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    private func age(of item: ArchivedTab) -> String {
        Date().timeIntervalSince(item.date) < 60
            ? String(localized: "just now", bundle: .chordUI)
            : Self.ageFormatter.localizedString(for: item.date, relativeTo: Date())
    }

    @objc private func clear() {
        onClear?()
    }
}

/// One archived tab: its site's icon, its title, then its site and when it was archived.
final class ArchivedTabRowView: NSView {
    var onClick: (() -> Void)?
    private let icon = NSImageView()
    private var isHovered = false

    init(item: ArchivedTab, age: String, space: Space?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = FaviconStore.shared.icon(for: item.url) { [weak icon] image in icon?.image = image }
            ?? Theme.symbol("globe", size: 13)
        let title = NSTextField(labelWithString: item.displayTitle)
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let place = [item.url?.displayHost, space?.name, age].compactMap { $0 }.filter { !$0.isEmpty }
        let detail = NSTextField(labelWithString: place.joined(separator: " · "))
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let texts = NSStackView(views: [title, detail])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1
        for view in [icon, texts] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            texts.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.displayTitle)
        setAccessibilityHelp(String(localized: "Opens the tab again", bundle: .chordUI))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
        layer?.backgroundColor = hovered
            ? (isDarkAppearance ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.05)).cgColor
            : nil
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

/// Lays the list out from the top of the scroll view.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
