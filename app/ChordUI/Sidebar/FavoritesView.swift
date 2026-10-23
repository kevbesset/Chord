import AppKit

extension NSPasteboard.PasteboardType {
    /// A Chord tab being dragged inside the sidebar; the value is the tab's UUID.
    static let chordTab = NSPasteboard.PasteboardType("app.chord.tab")
    /// A folder of pinned tabs being dragged; the value is the folder's UUID.
    static let chordFolder = NSPasteboard.PasteboardType("app.chord.folder")
}

/// Writes a tab for dragging: its id for Chord, its URL for other apps.
func pasteboardItem(for tab: Tab) -> NSPasteboardItem {
    let item = NSPasteboardItem()
    item.setString(tab.id.uuidString, forType: .chordTab)
    if let url = tab.url {
        item.setString(url.absoluteString, forType: .URL)
        item.setString(url.absoluteString, forType: .string)
    }
    return item
}

/// The favorites at the top of the sidebar: tiles shared by the Spaces of one profile,
/// four per row.
/// Fewer than four share the full width, like Arc.
final class FavoritesView: NSView {
    weak var delegate: SidebarDelegate?
    private var tiles: [FavoriteTileView] = []
    private var heightConstraint: NSLayoutConstraint!
    private var dropIndex: Int?
    private let dropIndicator = NSView()

    static let tileHeight: CGFloat = 46
    static let spacing: CGFloat = 8

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.isActive = true
        registerForDraggedTypes([.chordTab, .URL])

        dropIndicator.wantsLayer = true
        dropIndicator.layer?.cornerRadius = 1.5
        dropIndicator.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dropIndicator.isHidden = true
        addSubview(dropIndicator)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { true }

    func update(favorites: [Tab], selectedID: UUID?, splitIDs: Set<UUID>, accent: NSColor) {
        while tiles.count < favorites.count {
            let tile = FavoriteTileView()
            addSubview(tile, positioned: .below, relativeTo: dropIndicator)
            tiles.append(tile)
        }
        while tiles.count > favorites.count {
            tiles.removeLast().removeFromSuperview()
        }
        for (tile, tab) in zip(tiles, favorites) {
            tile.configure(tab: tab, selected: tab.id == selectedID || splitIDs.contains(tab.id), accent: accent)
            tile.delegate = delegate
        }
        heightConstraint.constant = height(for: favorites.count)
        needsLayout = true
    }

    /// Room for a drop even when there is no favorite yet, while a tab is dragged.
    private func height(for count: Int) -> CGFloat {
        let rows = (max(count, dropIndex == nil ? 0 : 1) + 3) / 4
        return rows == 0 ? 0 : CGFloat(rows) * Self.tileHeight + CGFloat(rows - 1) * Self.spacing
    }

    private var columns: Int { max(1, min(tiles.count, 4)) }

    private func frame(at index: Int) -> NSRect {
        let columns = CGFloat(columns)
        let width = (bounds.width - (columns - 1) * Self.spacing) / columns
        let column = CGFloat(index % Int(columns))
        let row = CGFloat(index / Int(columns))
        return NSRect(x: column * (width + Self.spacing), y: row * (Self.tileHeight + Self.spacing),
                      width: width, height: Self.tileHeight).integral
    }

    override func layout() {
        super.layout()
        for (index, tile) in tiles.enumerated() {
            tile.frame = frame(at: index)
        }
    }

    // MARK: - Drop

    private func index(at point: NSPoint) -> Int {
        guard !tiles.isEmpty else { return 0 }
        for (index, tile) in tiles.enumerated() where point.x < tile.frame.midX && point.y < tile.frame.maxY {
            return index
        }
        return tiles.count
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        let index = index(at: point)
        if dropIndex == nil {
            dropIndex = index
            heightConstraint.constant = height(for: tiles.count)
        }
        dropIndex = index
        let reference = index < tiles.count ? frame(at: index) : (tiles.isEmpty ? NSRect(x: 0, y: 0, width: 0, height: Self.tileHeight) : frame(at: tiles.count - 1).offsetBy(dx: frame(at: 0).width + Self.spacing, dy: 0))
        dropIndicator.frame = NSRect(x: max(0, reference.minX - Self.spacing / 2 - 1.5), y: reference.minY + 6, width: 3, height: Self.tileHeight - 12)
        dropIndicator.isHidden = false
        return sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        endDrop()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let index = dropIndex ?? tiles.count
        endDrop()
        let pasteboard = sender.draggingPasteboard
        if let id = pasteboard.string(forType: .chordTab).flatMap(UUID.init(uuidString:)),
           let tab = delegate?.sidebarTab(withID: id) {
            delegate?.sidebarMove(tab, to: .favorites(index))
            return true
        }
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        delegate?.sidebarOpen(urls, at: .favorites(index))
        return true
    }

    private func endDrop() {
        dropIndex = nil
        dropIndicator.isHidden = true
        heightConstraint.constant = height(for: tiles.count)
    }
}

/// One favorite: a frosted tile with the site's icon, white when selected.
final class FavoriteTileView: NSView, NSDraggingSource {
    weak var delegate: SidebarDelegate?
    private(set) var tab: Tab?
    private let icon = FaviconTileView(size: 20)
    private var isSelected = false
    private var isHovered = false
    private var accent = NSColor.controlAccentColor
    private var mouseDownEvent: NSEvent?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(tab: Tab, selected: Bool, accent: NSColor) {
        self.tab = tab
        self.accent = accent
        icon.configure(url: tab.url, fallback: tab.displayTitle)
        toolTip = tab.displayTitle
        setAccessibilityLabel("Favori : \(tab.displayTitle)")
        isSelected = selected
        // A sleeping favorite is a little dimmer, like Arc.
        icon.alphaValue = tab.page == nil && !selected ? 0.85 : 1
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        guard let layer else { return }
        let dark = isDarkAppearance
        layer.cornerRadius = 11
        if isSelected {
            layer.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.16) : NSColor.white).cgColor
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = dark ? 0 : 0.08
            layer.shadowRadius = 3
            layer.shadowOffset = CGSize(width: 0, height: -1)
            layer.borderWidth = 1
            layer.borderColor = accent.withAlphaComponent(0.35).cgColor
        } else {
            let alpha: CGFloat = dark ? (isHovered ? 0.12 : 0.08) : (isHovered ? 0.78 : 0.62)
            layer.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
            layer.shadowOpacity = 0
            layer.borderWidth = 1
            layer.borderColor = NSColor.black.withAlphaComponent(dark ? 0.2 : 0.04).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    // MARK: - Click, drag, menu

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, let tab else { return }
        let distance = hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y)
        guard distance > 4 else { return }
        mouseDownEvent = nil
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem(for: tab))
        item.setDraggingFrame(bounds, contents: snapshotImage())
        beginDraggingSession(with: [item], event: start, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownEvent != nil, let tab else { return }
        mouseDownEvent = nil
        delegate?.sidebarSelect(tab)
    }

    override func accessibilityPerformPress() -> Bool {
        if let tab { delegate?.sidebarSelect(tab) }
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let tab else { return nil }
        let menu = NSMenu()
        menu.addItem(closureItem("Retirer des favoris") { [weak self] in self?.delegate?.sidebarToggleFavorite(tab) })
        menu.addItem(closureItem("Ouvrir en split view") { [weak self] in self?.delegate?.sidebarSplit(tab) })
        menu.addItem(closureItem("Copier l'URL") { [weak self] in self?.delegate?.sidebarCopyURL(tab) })
        menu.addItem(.separator())
        menu.addItem(closureItem("Mettre en veille") { [weak self] in self?.delegate?.sidebarClose(tab) })
        return menu
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : .copy
    }

    private func snapshotImage() -> NSImage {
        let image = NSImage(size: bounds.size)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            image.addRepresentation(rep)
        }
        return image
    }
}

/// A menu item that runs a closure. Keeps menus next to the views that show them.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}

func closureItem(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
    ClosureMenuItem(title, handler)
}
