import AppKit

protocol SidebarDelegate: AnyObject {
    func sidebarGoBack()
    func sidebarGoForward()
    func sidebarReload()
    func sidebarToggle()
    func sidebarAddressClicked()
    func sidebarNewTab()
    func sidebarSelect(_ tab: Tab)
    func sidebarClose(_ tab: Tab)
    func sidebarTogglePin(_ tab: Tab)
    func sidebarToggleFavorite(_ tab: Tab)
    func sidebarSplit(_ tab: Tab)
    func sidebarRemoveFromSplit(_ tab: Tab)
    func sidebarCopyURL(_ tab: Tab)
    func sidebarTab(withID id: UUID) -> Tab?
    func sidebarMove(_ tab: Tab, to destination: TabDestination)
    func sidebarMove(_ tab: Tab, toSpace space: Space)
    func sidebarMove(_ folder: Folder, into parent: Folder?, at index: Int)
    func sidebarOpen(_ urls: [URL], at destination: TabDestination)
    func sidebarNewFolder(with tab: Tab?)
    func sidebarRename(_ folder: Folder)
    func sidebarUngroup(_ folder: Folder)
    func sidebarDelete(_ folder: Folder)
    func sidebarSetExpanded(_ folder: Folder, _ expanded: Bool)
    func sidebarSelectSpace(_ space: Space)
    func sidebarAddSpace()
    func sidebarRename(_ space: Space)
    func sidebarSetColor(_ space: Space, hex: String)
    func sidebarDelete(_ space: Space)
    func sidebarSwipe(forward: Bool)
    func sidebarResize(to width: CGFloat, finished: Bool)
    func sidebarShowDownloads()
    func sidebarMouseEntered()
    func sidebarMouseExited()
}

/// The sidebar: navigation row, address, favorites, tabs, Spaces and downloads.
///
/// Docked, it is transparent and shows the window glass. Floating (revealed by
/// hovering the window edge while hidden), it gets its own glass and shadow.
final class SidebarView: NSView {
    weak var delegate: SidebarDelegate? {
        didSet {
            tabList.delegate = delegate
            favorites.delegate = delegate
            spaceSwitcher.sidebarDelegate = delegate
        }
    }

    let tabList = TabListView()
    let favorites = FavoritesView()
    let spaceSwitcher = SpaceSwitcherView()
    private let floatingBackground = NSVisualEffectView()
    private let floatingTint = NSView()
    private let addressPill = AddressPillView()
    private let resizeHandle = SidebarResizeHandle()
    // The first row shares the title bar with the traffic lights: a touch larger than
    // the other icons, so that they hold their own next to them.
    private lazy var backButton = IconButton(symbol: "chevron.left", label: "Page précédente (⌘[)", target: self, action: #selector(backClicked), size: 28, pointSize: 15)
    private lazy var forwardButton = IconButton(symbol: "chevron.right", label: "Page suivante (⌘])", target: self, action: #selector(forwardClicked), size: 28, pointSize: 15)
    private lazy var reloadButton = IconButton(symbol: "arrow.clockwise", label: "Recharger (⌘R)", target: self, action: #selector(reloadClicked), size: 28, pointSize: 15)
    private lazy var collapseButton = IconButton(symbol: "sidebar.left", label: "Barre latérale (⌘S)", target: self, action: #selector(collapseClicked), size: 28, pointSize: 15)
    private lazy var downloadsButton = IconButton(symbol: "arrow.down.circle", label: "Téléchargements (⇧⌘J)", target: self, action: #selector(downloadsClicked))

    private var favoritesTopToPill: NSLayoutConstraint!
    private var favoritesTopToRow: NSLayoutConstraint!
    private var listTop: NSLayoutConstraint!
    private var topRowCenter: NSLayoutConstraint!
    private var topRowLeading: NSLayoutConstraint!
    private var swipeDistance: CGFloat = 0
    private var swipeFired = false
    private var hasFavorites = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Empty areas of the sidebar act as a title bar, like Arc: they drag the window and
    /// zoom it on a double-click. Handled here rather than through `mouseDownCanMoveWindow`,
    /// which moves the window but ignores double-clicks.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.handleChromeMouseDown(event)
    }

    func update(state: BrowserState) {
        let space = state.activeSpace
        let selectedID = state.selectedTab?.id
        let splitIDs = state.isSplit ? Set(state.visibleTabs.map(\.id)) : []
        favorites.update(favorites: state.favorites, selectedID: selectedID, splitIDs: splitIDs, accent: space.accent)
        hasFavorites = !state.favorites.isEmpty
        listTop.constant = hasFavorites ? 12 : 0
        tabList.update(space: space, spaces: state.spaces, selectedID: selectedID, splitIDs: splitIDs)
        spaceSwitcher.update(spaces: state.spaces, active: space)
        floatingTint.layer?.backgroundColor = space.color.withAlphaComponent(0.06).cgColor
        updateNavigation(tab: state.selectedTab)
    }

    func updateNavigation(tab: Tab?) {
        backButton.isEnabled = tab?.page?.canGoBack ?? false
        forwardButton.isEnabled = tab?.page?.canGoForward ?? false
        reloadButton.isEnabled = tab != nil
        reloadButton.showsStop(tab?.page?.isLoading ?? false)
        addressPill.update(url: tab?.url)
    }

    /// Safari-style layout: the address and navigation move to a bar on top of the page.
    func setAddressBarOnTop(_ onTop: Bool) {
        for view in [backButton, forwardButton, reloadButton, addressPill] as [NSView] {
            view.isHidden = onTop
        }
        favoritesTopToPill.isActive = !onTop
        favoritesTopToRow.isActive = onTop
    }

    func setFloating(_ floating: Bool) {
        floatingBackground.isHidden = !floating
        resizeHandle.isHidden = floating
        if floating {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = 24
            shadow.shadowOffset = NSSize(width: 0, height: -8)
            self.shadow = shadow
        } else {
            self.shadow = nil
        }
    }

    // MARK: - Layout

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        floatingBackground.material = .popover
        floatingBackground.blendingMode = .withinWindow
        floatingBackground.state = .active
        floatingBackground.wantsLayer = true
        floatingBackground.layer?.cornerRadius = 14
        floatingBackground.layer?.masksToBounds = true
        floatingBackground.layer?.borderWidth = 0.5
        floatingBackground.layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
        floatingBackground.isHidden = true
        floatingTint.wantsLayer = true
        floatingTint.translatesAutoresizingMaskIntoConstraints = false
        floatingBackground.addSubview(floatingTint)

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 2
        // Panel toggle next to the traffic lights, page navigation on the right.
        topRow.addView(collapseButton, in: .leading)
        topRow.addView(backButton, in: .trailing)
        topRow.addView(forwardButton, in: .trailing)
        topRow.addView(reloadButton, in: .trailing)

        addressPill.onClick = { [weak self] in self?.delegate?.sidebarAddressClicked() }
        resizeHandle.onDrag = { [weak self] width, finished in self?.delegate?.sidebarResize(to: width, finished: finished) }

        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.addView(spaceSwitcher, in: .leading)
        bottomRow.addView(downloadsButton, in: .trailing)

        for view in [floatingBackground, topRow, addressPill, favorites, tabList, bottomRow, resizeHandle] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        favoritesTopToPill = favorites.topAnchor.constraint(equalTo: addressPill.bottomAnchor, constant: 12)
        favoritesTopToRow = favorites.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 10)
        listTop = tabList.topAnchor.constraint(equalTo: favorites.bottomAnchor, constant: 0)
        topRowCenter = topRow.centerYAnchor.constraint(equalTo: topAnchor, constant: 14)
        topRowLeading = topRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.trafficLightsWidth)

        NSLayoutConstraint.activate([
            floatingBackground.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            floatingBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            floatingBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            floatingBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            floatingTint.topAnchor.constraint(equalTo: floatingBackground.topAnchor),
            floatingTint.leadingAnchor.constraint(equalTo: floatingBackground.leadingAnchor),
            floatingTint.trailingAnchor.constraint(equalTo: floatingBackground.trailingAnchor),
            floatingTint.bottomAnchor.constraint(equalTo: floatingBackground.bottomAnchor),

            // The first row shares the title bar with the traffic lights.
            topRowCenter, topRowLeading,
            topRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            topRow.heightAnchor.constraint(equalToConstant: 28),

            addressPill.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 8),
            addressPill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            addressPill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            addressPill.heightAnchor.constraint(equalToConstant: 34),

            favoritesTopToPill,
            favorites.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            favorites.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            listTop,
            tabList.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            tabList.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            tabList.bottomAnchor.constraint(equalTo: bottomRow.topAnchor, constant: -6),

            bottomRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            bottomRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            bottomRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            bottomRow.heightAnchor.constraint(equalToConstant: 30),

            resizeHandle.topAnchor.constraint(equalTo: topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 2),
            resizeHandle.widthAnchor.constraint(equalToConstant: 6),
        ])
    }

    /// Lines the first row up with the traffic lights, wherever macOS draws them: centred
    /// on the same height, starting just after the green button.
    override func layout() {
        if let close = window?.standardWindowButton(.closeButton), let zoom = window?.standardWindowButton(.zoomButton),
           let container = close.superview {
            let center = convert(NSPoint(x: close.frame.midX, y: close.frame.midY), from: container)
            let top = isFlipped ? center.y : bounds.height - center.y
            let leading = convert(NSPoint(x: zoom.frame.maxX, y: 0), from: container).x + 8
            if abs(topRowCenter.constant - top) > 0.5 { topRowCenter.constant = top }
            if abs(topRowLeading.constant - leading) > 0.5 { topRowLeading.constant = leading }
        }
        super.layout()
    }

    // MARK: - Swipe between Spaces, like Arc

    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        if event.phase == .began || event.phase == .mayBegin {
            swipeDistance = 0
            swipeFired = false
        }
        // Positive when the fingers move right, whatever the scrolling direction setting.
        let fingers = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        swipeDistance += fingers
        if !swipeFired, abs(swipeDistance) > 60 {
            swipeFired = true
            delegate?.sidebarSwipe(forward: swipeDistance < 0)
        }
    }

    // MARK: - Hover (for the floating mode)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { delegate?.sidebarMouseEntered() }
    override func mouseExited(with event: NSEvent) { delegate?.sidebarMouseExited() }

    // MARK: - Actions

    @objc private func backClicked() { delegate?.sidebarGoBack() }
    @objc private func forwardClicked() { delegate?.sidebarGoForward() }
    @objc private func reloadClicked() { delegate?.sidebarReload() }
    @objc private func collapseClicked() { delegate?.sidebarToggle() }
    @objc private func downloadsClicked() { delegate?.sidebarShowDownloads() }
}

/// The sidebar's right edge: drag it to change the sidebar's width.
final class SidebarResizeHandle: NSView {
    /// The new width, then `finished` once the mouse is released.
    var onDrag: ((CGFloat, Bool) -> Void)?
    private var startX: CGFloat = 0
    private var startWidth: CGFloat = 0

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        startX = event.locationInWindow.x
        startWidth = superview?.frame.width ?? Theme.sidebarWidth
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(clamped(event), false)
    }

    override func mouseUp(with event: NSEvent) {
        onDrag?(clamped(event), true)
    }

    private func clamped(_ event: NSEvent) -> CGFloat {
        let width = startWidth + event.locationInWindow.x - startX
        return min(max(width, ChordSettings.sidebarWidthRange.lowerBound), ChordSettings.sidebarWidthRange.upperBound).rounded()
    }
}
