import AppKit
import Combine

/// The downloads panel, like Arc's: a small popover above the downloads button with the
/// running downloads and the latest files. A click opens a file, the magnifier shows it
/// in the Finder, and files can be dragged out to other apps.
final class DownloadsPanelController: NSViewController {
    var onCancel: ((String) -> Void)?
    var onKeep: ((String) -> Void)?
    var onDismissFailed: ((String) -> Void)?

    private let downloads: Downloads
    private let list = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: String(localized: "No downloads", bundle: .chordUI))
    private var rows: [URL: DownloadRowView] = [:]
    private var cancellable: AnyCancellable?

    static let width: CGFloat = 340

    init(downloads: Downloads) {
        self.downloads = downloads
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let title = NSTextField(labelWithString: String(localized: "Downloads", bundle: .chordUI))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let showAll = NSButton(title: String(localized: "Show in Finder", bundle: .chordUI), target: self, action: #selector(openFolder))
        showAll.isBordered = false
        showAll.font = .systemFont(ofSize: 12)
        showAll.contentTintColor = .controlAccentColor
        let header = NSStackView(views: [title, NSView(), showAll])
        header.distribution = .fill

        list.orientation = .vertical
        list.alignment = .width
        list.spacing = 2
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center

        let column = NSStackView(views: [header, list, emptyLabel])
        column.orientation = .vertical
        column.alignment = .width
        column.spacing = 8
        column.edgeInsets = NSEdgeInsets(top: 12, left: 10, bottom: 10, right: 10)
        column.setCustomSpacing(10, after: header)
        column.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(column)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.width),
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -8),
        ])
        view = root
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reload()
        cancellable = downloads.changes
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in self?.reload() }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        cancellable = nil
    }

    /// Rows are kept by file, so a running download only updates its progress.
    private func reload() {
        let items = downloads.recent()
        var kept: [URL: DownloadRowView] = [:]
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items {
            let row = rows[item.url] ?? DownloadRowView()
            row.configure(item)
            row.onCancel = { [weak self] in if let id = item.id { self?.onCancel?(id) } }
            row.onKeep = { [weak self] in if let id = item.id { self?.onKeep?(id) } }
            row.onDismiss = { [weak self] in if let id = item.id { self?.onDismissFailed?(id) } }
            list.addArrangedSubview(row)
            kept[item.url] = row
        }
        rows = kept
        emptyLabel.isHidden = !items.isEmpty
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    @objc private func openFolder() {
        NSWorkspace.shared.open(downloads.folder)
    }
}

/// One download: the file's icon, its name, then its progress or its size and age.
final class DownloadRowView: NSView, NSDraggingSource {
    var onCancel: (() -> Void)?
    var onKeep: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var item: Downloads.Item?
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private lazy var revealButton = IconButton(symbol: "magnifyingglass", label: String(localized: "Show in Finder", bundle: .chordUI), target: self, action: #selector(reveal), size: 24, pointSize: 11)
    private lazy var cancelButton = IconButton(symbol: "xmark", label: String(localized: "Cancel download", bundle: .chordUI), target: self, action: #selector(cancel), size: 24, pointSize: 10)
    private lazy var keepButton: NSButton = {
        let button = NSButton(title: String(localized: "Keep", bundle: .chordUI), target: self, action: #selector(keep))
        button.controlSize = .small
        button.bezelStyle = .push
        return button
    }()
    private var isHovered = false
    private var mouseDownEvent: NSEvent?

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let ageFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .chordUI
        formatter.unitsStyle = .short
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        progress.style = .bar
        progress.controlSize = .small
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1

        let texts = NSStackView(views: [name, detail, progress])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 3
        for view in [icon, texts, keepButton, revealButton, cancelButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32),
            texts.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: keepButton.leadingAnchor, constant: -6),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: revealButton.leadingAnchor, constant: -6),
            keepButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -4),
            keepButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            progress.widthAnchor.constraint(equalTo: texts.widthAnchor),
            revealButton.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -2),
            revealButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ item: Downloads.Item) {
        self.item = item
        icon.image = NSWorkspace.shared.icon(forFile: item.url.path)
        name.stringValue = item.url.lastPathComponent
        setAccessibilityLabel(item.url.lastPathComponent)
        switch item.state {
        case .running(let fraction):
            progress.isHidden = false
            progress.doubleValue = fraction
            detail.stringValue = "\(Int((fraction * 100).rounded())) %"
            name.textColor = .labelColor
        case .done:
            progress.isHidden = true
            let size = (try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }
            let age = Date().timeIntervalSince(item.date) < 60 ? String(localized: "just now", bundle: .chordUI) : Self.ageFormatter.localizedString(for: item.date, relativeTo: Date())
            detail.stringValue = [size.map { Self.sizeFormatter.string(fromByteCount: Int64($0)) }, age].compactMap { $0 }.joined(separator: " · ")
            name.textColor = .labelColor
        case .failed:
            progress.isHidden = true
            detail.stringValue = String(localized: "Download failed", bundle: .chordUI)
            name.textColor = .secondaryLabelColor
        case .needsApproval(let warning):
            progress.isHidden = true
            detail.stringValue = warning == "insecure"
                ? String(localized: "Downloaded from an insecure address", bundle: .chordUI)
                : String(localized: "This type of file can harm your Mac", bundle: .chordUI)
            name.textColor = .labelColor
        }
        refreshButtons()
    }

    private var isRunning: Bool {
        switch item?.state {
        case .running, .needsApproval: return true
        default: return false
        }
    }

    private var needsApproval: Bool {
        if case .needsApproval = item?.state { return true }
        return false
    }

    private func refreshButtons() {
        // Cancel while running, dismiss a failure; the magnifier on hover once it exists.
        // A download held back offers to keep it.
        keepButton.isHidden = !needsApproval
        cancelButton.isHidden = !(isRunning || item?.state == .failed)
        cancelButton.toolTip = isRunning ? String(localized: "Cancel download", bundle: .chordUI) : String(localized: "Remove from list", bundle: .chordUI)
        revealButton.isHidden = !(isHovered && item?.state == .done)
        layer?.backgroundColor = isHovered
            ? (isDarkAppearance ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.05)).cgColor
            : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refreshButtons()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshButtons()
    }

    // MARK: - Open, drag out

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, let item, item.state == .done else { return }
        let distance = hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y)
        guard distance > 4 else { return }
        mouseDownEvent = nil
        let dragged = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        dragged.setDraggingFrame(icon.frame, contents: icon.image)
        beginDraggingSession(with: [dragged], event: start, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownEvent != nil, let item, item.state == .done else { return }
        mouseDownEvent = nil
        NSWorkspace.shared.open(item.url)
    }

    override func accessibilityPerformPress() -> Bool {
        if let item, item.state == .done { NSWorkspace.shared.open(item.url) }
        return true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    @objc private func reveal() {
        if let item { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    }

    @objc private func cancel() {
        if isRunning { onCancel?() } else { onDismiss?() }
    }

    @objc private func keep() {
        onKeep?()
    }
}
