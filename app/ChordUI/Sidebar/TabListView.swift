import AppKit

/// The non-tab rows of the sidebar list. One shared instance each: outline views
/// identify rows by object.
final class ListMarker {
    enum Kind { case separator, header, newTab }
    let kind: Kind
    private init(_ kind: Kind) { self.kind = kind }

    static let separator = ListMarker(.separator)
    static let header = ListMarker(.header)
    static let newTab = ListMarker(.newTab)
}

/// Pinned tabs and their folders, then "Today" with "New Tab" first, then
/// today's tabs. An NSOutlineView: rows are recycled, so the list stays fast with many
/// tabs, and folders open and close like Arc's.
///
/// Tabs and folders are dragged to reorder them, into folders, above the separator to
/// pin them, onto the favorites, onto a Space to move them there. Links dragged in from
/// other apps open where they are dropped.
final class TabListView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    weak var delegate: SidebarDelegate?

    private let scrollView = SidebarScrollView()
    private let outline = SidebarOutlineView()
    private var space: Space?
    private var spaces: [Space] = []
    private var topLevel: [AnyObject] = []
    private var selectedID: UUID?
    private var splitIDs: Set<UUID> = []
    /// True while folders are opened to match the model, so that it is not saved back.
    private var restoringExpansion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .plain
        outline.backgroundColor = .clear
        outline.selectionHighlightStyle = .none
        outline.intercellSpacing = NSSize(width: 0, height: 2)
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.indentationPerLevel = 14
        outline.autoresizesOutlineColumn = false
        outline.focusRingType = .none
        outline.draggingDestinationFeedbackStyle = .gap
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(rowClicked)
        outline.onMiddleClick = { [weak self] row in
            guard let self, let tab = self.outline.item(atRow: row) as? Tab else { return }
            self.delegate?.sidebarClose(tab)
        }
        outline.isWindowChrome = { [weak self] row in
            guard let self, let marker = self.outline.item(atRow: row) as? ListMarker else { return row < 0 }
            return marker.kind != .newTab
        }
        outline.registerForDraggedTypes([.chordTab, .chordFolder, .URL])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask(.copy, forLocal: false)
        let menu = NSMenu()
        menu.delegate = self
        outline.menu = menu

        scrollView.documentView = outline
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(space: Space, spaces: [Space], selectedID: UUID?, splitIDs: Set<UUID>) {
        self.space = space
        self.spaces = spaces
        self.selectedID = selectedID
        self.splitIDs = splitIDs
        topLevel = space.pinnedItems.map(\.object)
            + (space.pinnedItems.isEmpty ? [] : [ListMarker.separator])
            + [ListMarker.header, ListMarker.newTab]
            + space.today
        outline.reloadData()
        restoringExpansion = true
        expandSaved(space.pinnedItems)
        restoringExpansion = false
    }

    private func expandSaved(_ items: [PinnedItem]) {
        for case .folder(let folder) in items where folder.isExpanded {
            outline.expandItem(folder)
            expandSaved(folder.items)
        }
    }

    /// Redraws one tab's row (title, URL or icon changed) without reloading the list.
    func reloadTab(id: UUID) {
        guard let tab = space?.allTabs.first(where: { $0.id == id }) else { return }
        outline.reloadItem(tab)
    }

    /// Slides the list sideways when the Space changes, in the direction of the switch.
    // MARK: - Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return topLevel.count }
        return (item as? Folder)?.items.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let folder = item as? Folder { return folder.items[index].object }
        return topLevel[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is Folder
    }

    // MARK: - Delegate

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let marker = item as? ListMarker else { return Theme.tabRowHeight }
        switch marker.kind {
        case .separator: return 13
        case .header: return 26
        case .newTab: return Theme.tabRowHeight
        }
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { false }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        switch item {
        case let tab as Tab:
            let cell = outlineView.makeView(withIdentifier: TabCellView.reuseID, owner: nil) as? TabCellView ?? TabCellView()
            cell.configure(tab: tab, selected: tab.id == selectedID, inSplit: splitIDs.contains(tab.id))
            cell.onClose = { [weak self] in self?.delegate?.sidebarClose(tab) }
            return cell
        case let folder as Folder:
            let cell = outlineView.makeView(withIdentifier: FolderCellView.reuseID, owner: nil) as? FolderCellView ?? FolderCellView()
            cell.configure(folder: folder, expanded: outlineView.isItemExpanded(folder))
            return cell
        case let marker as ListMarker:
            switch marker.kind {
            case .newTab:
                return outlineView.makeView(withIdentifier: NewTabCellView.reuseID, owner: nil) as? NewTabCellView ?? NewTabCellView()
            case .header:
                let cell = outlineView.makeView(withIdentifier: HeaderCellView.reuseID, owner: nil) as? HeaderCellView ?? HeaderCellView()
                cell.configure(title: String(localized: "Today", bundle: .chordUI), count: space?.today.count ?? 0)
                return cell
            case .separator:
                return outlineView.makeView(withIdentifier: SeparatorCellView.reuseID, owner: nil) as? SeparatorCellView ?? SeparatorCellView()
            }
        default:
            return nil
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        folderToggled(notification, expanded: true)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        folderToggled(notification, expanded: false)
    }

    private func folderToggled(_ notification: Notification, expanded: Bool) {
        guard let folder = notification.userInfo?["NSObject"] as? Folder else { return }
        (outline.view(atColumn: 0, row: outline.row(forItem: folder), makeIfNecessary: false) as? FolderCellView)?.setExpanded(expanded)
        guard !restoringExpansion else { return }
        delegate?.sidebarSetExpanded(folder, expanded)
    }

    @objc private func rowClicked() {
        let row = outline.clickedRow
        guard row >= 0 else { return }
        switch outline.item(atRow: row) {
        case let tab as Tab:
            delegate?.sidebarSelect(tab)
        case let folder as Folder:
            let expand = !outline.isItemExpanded(folder)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                if expand { outline.expandItem(folder) } else { outline.collapseItem(folder) }
            }
        case let marker as ListMarker where marker.kind == .newTab:
            delegate?.sidebarNewTab()
        default:
            break
        }
    }

    // MARK: - Drag and drop

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        switch item {
        case let tab as Tab:
            return pasteboardItem(for: tab)
        case let folder as Folder:
            let entry = NSPasteboardItem()
            entry.setString(folder.id.uuidString, forType: .chordFolder)
            return entry
        default:
            return nil
        }
    }

    /// Where a drop lands. In a folder; or at the top level: the pinned tabs down to the
    /// "Today" header, today's tabs from "New Tab" down.
    private func destination(item: Any?, index: Int) -> TabDestination? {
        guard let space else { return nil }
        if let folder = item as? Folder {
            return .pinned(folder, index < 0 ? folder.items.count : index)
        }
        guard item == nil else { return nil }
        let pinnedCount = space.pinnedItems.count
        let todayStart = pinnedCount + (pinnedCount == 0 ? 0 : 1) + 2
        let index = index < 0 ? topLevel.count : index
        if index <= pinnedCount { return .pinned(nil, index) }
        if index < todayStart - 1 { return .pinned(nil, pinnedCount) }
        return .today(max(0, index - todayStart))
    }

    private func draggedFolder(_ info: NSDraggingInfo) -> Folder? {
        guard let id = info.draggingPasteboard.string(forType: .chordFolder).flatMap(UUID.init(uuidString:)) else { return nil }
        return space?.folders.first { $0.id == id }
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        guard let space else { return [] }
        // On a tab or a marker: drop just above it instead.
        if item is Tab || item is ListMarker, let object = item as AnyObject? {
            let parent = space.parent(of: object)
            let siblings: [AnyObject] = parent?.items.map(\.object) ?? topLevel
            guard let position = siblings.firstIndex(where: { $0 === object }) else { return [] }
            outlineView.setDropItem(parent, dropChildIndex: position)
            return validate(info, item: parent, index: position)
        }
        return validate(info, item: item, index: index)
    }

    private func validate(_ info: NSDraggingInfo, item: Any?, index: Int) -> NSDragOperation {
        guard let destination = destination(item: item, index: index) else { return [] }
        if let folder = draggedFolder(info) {
            // Folders live among pinned tabs only, and never inside themselves.
            guard case .pinned(let parent, _) = destination else { return [] }
            if let parent, space?.folder(folder, contains: parent) == true { return [] }
            return .move
        }
        return info.draggingPasteboard.types?.contains(.chordTab) == true ? .move : .copy
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let destination = destination(item: item, index: index) else { return false }
        if let folder = draggedFolder(info) {
            guard case .pinned(let parent, let position) = destination else { return false }
            delegate?.sidebarMove(folder, into: parent, at: position)
            return true
        }
        let pasteboard = info.draggingPasteboard
        if let id = pasteboard.string(forType: .chordTab).flatMap(UUID.init(uuidString:)),
           let tab = delegate?.sidebarTab(withID: id) {
            delegate?.sidebarMove(tab, to: destination)
            return true
        }
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        delegate?.sidebarOpen(urls, at: destination)
        return true
    }

    // MARK: - Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outline.clickedRow
        switch row >= 0 ? outline.item(atRow: row) : nil {
        case let tab as Tab:
            tabMenu(menu, tab)
        case let folder as Folder:
            menu.addItem(closureItem(String(localized: "Rename…", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarRename(folder) })
            menu.addItem(closureItem(String(localized: "New Folder", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarNewFolder(with: nil) })
            menu.addItem(.separator())
            menu.addItem(closureItem(String(localized: "Ungroup", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarUngroup(folder) })
            menu.addItem(closureItem(String(localized: "Delete Folder and Its Tabs…", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarDelete(folder) })
        default:
            menu.addItem(closureItem(String(localized: "New Folder", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarNewFolder(with: nil) })
            menu.addItem(closureItem(String(localized: "New Tab", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarNewTab() })
        }
    }

    private func tabMenu(_ menu: NSMenu, _ tab: Tab) {
        menu.addItem(closureItem(String(localized: "Add to Favorites", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarToggleFavorite(tab) })
        menu.addItem(closureItem(tab.isPinned ? String(localized: "Unpin", bundle: .chordUI) : String(localized: "Pin", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarTogglePin(tab) })
        menu.addItem(closureItem(String(localized: "New Folder with This Tab", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarNewFolder(with: tab) })
        if let space, let folder = space.parent(of: tab) {
            menu.addItem(closureItem(String(localized: "Move Out of “\(folder.name)”", bundle: .chordUI)) { [weak self] in
                let parent = space.parent(of: folder)
                let position = (space.items(in: parent).firstIndex { $0.object === folder } ?? 0) + 1
                self?.delegate?.sidebarMove(tab, to: .pinned(parent, position))
            })
        }
        if splitIDs.contains(tab.id) {
            menu.addItem(closureItem(String(localized: "Remove from Split View", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarRemoveFromSplit(tab) })
        } else if tab.id != selectedID {
            menu.addItem(closureItem(String(localized: "Open in Split View", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarSplit(tab) })
        }
        let others = spaces.filter { $0 !== space }
        if !others.isEmpty {
            let move = NSMenuItem(title: String(localized: "Move To", bundle: .chordUI), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for other in others {
                let entry = closureItem(other.name) { [weak self] in self?.delegate?.sidebarMove(tab, toSpace: other) }
                entry.image = Theme.dot(color: other.color)
                submenu.addItem(entry)
            }
            move.submenu = submenu
            menu.addItem(move)
        }
        menu.addItem(.separator())
        menu.addItem(closureItem(String(localized: "Copy URL", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarCopyURL(tab) })
        menu.addItem(.separator())
        menu.addItem(closureItem(tab.isPinned ? String(localized: "Unload", bundle: .chordUI) : String(localized: "Close Tab", bundle: .chordUI)) { [weak self] in self?.delegate?.sidebarClose(tab) })
    }
}

/// The list fills most of the sidebar, so its empty space and its non-clickable rows
/// (headers, separators) move the window like the rest of the sidebar.
final class SidebarOutlineView: NSOutlineView {
    /// Whether a row is part of the window chrome. Clicks below the last row always are.
    var isWindowChrome: (Int) -> Bool = { _ in true }
    /// A middle click on a row, like a browser's on a tab: closes it.
    var onMiddleClick: (Int) -> Void = { _ in }
    private var middleClickRow: Int?

    override func mouseDown(with event: NSEvent) {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row < 0 || isWindowChrome(row) {
            window?.handleChromeMouseDown(event)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return super.otherMouseDown(with: event) }
        middleClickRow = row(at: convert(event.locationInWindow, from: nil))
    }

    /// Acts on release over the row it started on, so that sliding off cancels it.
    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return super.otherMouseUp(with: event) }
        let row = row(at: convert(event.locationInWindow, from: nil))
        defer { middleClickRow = nil }
        guard row >= 0, row == middleClickRow else { return }
        onMiddleClick(row)
    }

    /// No disclosure triangle: folders draw their own chevron. Hiding it here rather than
    /// through `shouldShowOutlineCellForItem`, which also stops folders from collapsing.
    override func frameOfOutlineCell(atRow row: Int) -> NSRect { .zero }

    /// Rows start at the left edge, indented only by their depth: no room is kept for
    /// disclosure triangles.
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var frame = super.frameOfCell(atColumn: column, row: row)
        let indent = CGFloat(max(0, level(forRow: row))) * indentationPerLevel
        frame.origin.x = indent
        frame.size.width = bounds.width - indent
        return frame
    }
}

/// Hands horizontal swipes up to the sidebar, which switches Spaces with them. The
/// direction is decided once per gesture, so that a swipe that drifts a little up or
/// down keeps moving the Spaces, and a scroll keeps scrolling.
final class SidebarScrollView: NSScrollView {
    private var horizontal: Bool?

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || event.phase == .mayBegin { horizontal = nil }
        if horizontal == nil, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
            horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        }
        if event.phase == .began {
            // The sidebar needs the start of every gesture, before the direction is known.
            nextResponder?.scrollWheel(with: event)
        }
        if horizontal == true || ((event.phase == .ended || event.phase == .cancelled) && horizontal != false) {
            if event.phase != .began { nextResponder?.scrollWheel(with: event) }
            return
        }
        super.scrollWheel(with: event)
    }
}
