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
    func sidebarCopyAddress()
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
    /// A swipe moved the sidebar this far toward `space` (0 to 1), or back to nothing.
    func sidebarSwipeProgress(toward space: Space?, fraction: CGFloat)
    /// The swipe was let go: `space` is coming in, or (nil) the active one comes back.
    func sidebarSwipeWillEnd(on space: Space?, duration: TimeInterval)
    /// The swipe brought `space` in, or (nil) went back to the active one.
    func sidebarSwipeEnded(on space: Space?)
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
            pager.current.tabList.delegate = delegate
            pager.current.favorites.delegate = delegate
            spaceSwitcher.sidebarDelegate = delegate
        }
    }

    /// The active Space's favorites and tabs, and the neighbouring Space during a swipe.
    let pager = SpacePagerView()
    var tabList: TabListView { pager.current.tabList }
    let spaceSwitcher = SpaceSwitcherView()
    /// Floating, the sidebar has its own glass: the window's (the desktop shows
    /// through, not the page under it), frosted and tinted the same way.
    private let floatingBackground = NSVisualEffectView()
    private let floatingFrost = GlassFrostView()
    private let floatingTint = SpaceTintView()
    private let addressPill = AddressPillView()
    private let resizeHandle = SidebarResizeHandle()
    // The first row shares the title bar with the traffic lights: a touch larger than
    // the other icons, so that they hold their own next to them.
    private lazy var backButton = IconButton(symbol: "arrow.left", label: "Page précédente (⌘[)", target: self, action: #selector(backClicked), size: Theme.titleRowHeight, pointSize: 15)
    private lazy var forwardButton = IconButton(symbol: "arrow.right", label: "Page suivante (⌘])", target: self, action: #selector(forwardClicked), size: Theme.titleRowHeight, pointSize: 15)
    private lazy var reloadButton = IconButton(symbol: "arrow.clockwise", label: "Recharger (⌘R)", target: self, action: #selector(reloadClicked), size: Theme.titleRowHeight, pointSize: 15)
    private lazy var collapseButton = IconButton(symbol: "sidebar.left", label: "Barre latérale (⌘S)", target: self, action: #selector(collapseClicked), size: Theme.titleRowHeight, pointSize: 15)
    private lazy var downloadsButton = IconButton(symbol: "tray.and.arrow.down", label: "Téléchargements (⇧⌘J)", target: self, action: #selector(downloadsClicked), size: 28, pointSize: 14)
    private lazy var addSpaceButton = IconButton(symbol: "plus", label: "Nouveau Space", target: self, action: #selector(addSpaceClicked), size: 28, pointSize: 13)

    /// Where the downloads panel opens from.
    var downloadsAnchor: NSView { downloadsButton }

    private var pagerTopToPill: NSLayoutConstraint!
    private var pagerTopToRow: NSLayoutConstraint!
    private var topRowCenter: NSLayoutConstraint!
    private var topRowLeading: NSLayoutConstraint!
    private weak var state: BrowserState?
    private var swipe: Swipe?
    /// The page is gliding to its place after a swipe; a new one waits for the end.
    private var swipeSettling = false

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
        self.state = state
        let space = state.activeSpace
        let splitIDs = state.isSplit ? Set(state.visibleTabs.map(\.id)) : []
        pager.current.update(space: space, spaces: state.spaces, favorites: state.favorites,
                             selectedID: state.selectedTab?.id, splitIDs: splitIDs)
        spaceSwitcher.update(spaces: state.spaces, active: space)
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
        pagerTopToPill.isActive = !onTop
        pagerTopToRow.isActive = onTop
    }

    /// The Space colour of the floating glass, set with the window's own tint.
    func setTint(_ color: NSColor, duration: TimeInterval = 0) {
        floatingTint.setColor(color, duration: duration)
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

        floatingBackground.material = Theme.windowMaterial
        floatingBackground.blendingMode = .behindWindow
        floatingBackground.state = .active
        floatingBackground.wantsLayer = true
        floatingBackground.layer?.cornerRadius = 14
        floatingBackground.layer?.masksToBounds = true
        floatingBackground.layer?.borderWidth = 0.5
        floatingBackground.layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
        floatingBackground.isHidden = true
        for layer in [floatingFrost, floatingTint] as [NSView] {
            layer.translatesAutoresizingMaskIntoConstraints = false
            floatingBackground.addSubview(layer)
        }

        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 2
        // Panel toggle next to the traffic lights, page navigation on the right.
        topRow.addView(collapseButton, in: .leading)
        topRow.addView(backButton, in: .trailing)
        topRow.addView(forwardButton, in: .trailing)
        topRow.addView(reloadButton, in: .trailing)

        addressPill.onClick = { [weak self] in self?.delegate?.sidebarAddressClicked() }
        addressPill.onCopy = { [weak self] in self?.delegate?.sidebarCopyAddress() }
        resizeHandle.onDrag = { [weak self] width, finished in self?.delegate?.sidebarResize(to: width, finished: finished) }

        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        // Like Arc: downloads on the left, the Spaces centred, a new Space on the right.
        bottomRow.addView(downloadsButton, in: .leading)
        bottomRow.addView(spaceSwitcher, in: .center)
        bottomRow.addView(addSpaceButton, in: .trailing)

        for view in [floatingBackground, topRow, addressPill, pager, bottomRow, resizeHandle] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        // The favorites keep their place: the page starts a little higher for their shadows.
        pagerTopToPill = pager.topAnchor.constraint(equalTo: addressPill.bottomAnchor, constant: 12 - SpacePageView.topInset)
        pagerTopToRow = pager.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 10 - SpacePageView.topInset)
        topRowCenter = topRow.centerYAnchor.constraint(equalTo: topAnchor, constant: 14)
        topRowLeading = topRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.trafficLightsWidth)

        NSLayoutConstraint.activate([
            floatingBackground.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            floatingBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            floatingBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            floatingBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            floatingFrost.topAnchor.constraint(equalTo: floatingBackground.topAnchor),
            floatingFrost.leadingAnchor.constraint(equalTo: floatingBackground.leadingAnchor),
            floatingFrost.trailingAnchor.constraint(equalTo: floatingBackground.trailingAnchor),
            floatingFrost.bottomAnchor.constraint(equalTo: floatingBackground.bottomAnchor),
            floatingTint.topAnchor.constraint(equalTo: floatingBackground.topAnchor),
            floatingTint.leadingAnchor.constraint(equalTo: floatingBackground.leadingAnchor),
            floatingTint.trailingAnchor.constraint(equalTo: floatingBackground.trailingAnchor),
            floatingTint.bottomAnchor.constraint(equalTo: floatingBackground.bottomAnchor),

            // The first row shares the title bar with the traffic lights.
            topRowCenter, topRowLeading,
            topRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            topRow.heightAnchor.constraint(equalToConstant: Theme.titleRowHeight),

            addressPill.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 8),
            addressPill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            addressPill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            addressPill.heightAnchor.constraint(equalToConstant: 34),

            pagerTopToPill,
            pager.leadingAnchor.constraint(equalTo: leadingAnchor),
            pager.trailingAnchor.constraint(equalTo: trailingAnchor),
            pager.bottomAnchor.constraint(equalTo: bottomRow.topAnchor, constant: -6),

            bottomRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
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
    ///
    /// Measured in the window, relative to where the sidebar rests (docked or floating).
    /// Off screen (hidden), nothing is measured: the row keeps its place in the sidebar
    /// and slides away with it. The height is the one the window puts the traffic lights
    /// at (`Theme.titleRowCenter`), not where macOS has them for the moment: it moves
    /// them back to its own place each time they are shown again.
    override func layout() {
        if let window, let contentView = window.contentView,
           case let origin = convert(NSPoint(x: 0, y: isFlipped ? 0 : bounds.height), to: nil), origin.x >= 0 {
            let topInWindow = contentView.bounds.height - origin.y
            let top = Theme.titleRowCenter - topInWindow
            var lightsTrailing = Theme.trafficLightsWidth - 8
            if let zoom = window.standardWindowButton(.zoomButton), let container = zoom.superview, !zoom.isHidden {
                lightsTrailing = container.convert(NSPoint(x: zoom.frame.maxX, y: 0), to: nil).x
            }
            let leading = lightsTrailing - origin.x + 8
            if abs(topRowCenter.constant - top) > 0.5 { topRowCenter.constant = top }
            if abs(topRowLeading.constant - leading) > 0.5 { topRowLeading.constant = leading }
        }
        super.layout()
    }

    /// The row's place depends on where the sidebar is in the window: lay it out again
    /// when the sidebar moves, not only when it is resized.
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        let moved = newOrigin != frame.origin
        super.setFrameOrigin(newOrigin)
        if moved { needsLayout = true }
    }

    // MARK: - Swipe between Spaces, like Arc

    /// A two-finger swipe in progress.
    private struct Swipe {
        /// The fingers' travel, positive to the right.
        var distance: CGFloat = 0
        /// The page's speed in points per second, smoothed over the last events.
        var velocity: CGFloat = 0
        var lastTime: TimeInterval
        /// The Space being brought in, and the side it comes from.
        var target: Space?
        var side: Int = 0
        /// Set by the first movement: a vertical gesture is left to the tabs' scrolling.
        var isHorizontal: Bool?
    }

    /// Like Arc: fingers moving right bring the next Space, which comes in from the right
    /// as the sidebar moves left. There is no Space before the first or after the last:
    /// the sidebar only gives a little, like a scroll view at its end.
    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        switch event.phase {
        case .began:
            swipe = swipeSettling ? nil : Swipe(lastTime: event.timestamp)
        case .changed:
            guard var swipe else { return }
            if swipe.isHorizontal == nil, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
                swipe.isHorizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            }
            guard swipe.isHorizontal == true else {
                self.swipe = swipe.isHorizontal == false ? nil : swipe
                return
            }
            let fingers = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            swipe.distance += fingers
            let interval = Perf.begin("space.swipe")
            let offset = followSwipe(&swipe)
            let elapsed = max(event.timestamp - swipe.lastTime, 1.0 / 240)
            let speed = -fingers / CGFloat(elapsed)
            swipe.velocity = swipe.velocity * 0.4 + speed * 0.6
            swipe.lastTime = event.timestamp
            self.swipe = swipe
            pager.setOffset(offset)
            interval.end()
        case .ended, .cancelled:
            finishSwipe()
        default:
            break
        }
    }

    /// Where the page goes for the fingers' travel, preparing the incoming Space.
    private func followSwipe(_ swipe: inout Swipe) -> CGFloat {
        let width = max(pager.bounds.width, 1)
        let side = swipe.distance > 0 ? 1 : (swipe.distance < 0 ? -1 : 0)
        if side != swipe.side {
            swipe.side = side
            swipe.target = neighborSpace(side: side)
            if let target = swipe.target, let state {
                pager.neighbor.update(space: target, spaces: state.spaces, favorites: state.favorites(of: target),
                                      selectedID: state.selectedTab(in: target)?.id, splitIDs: [])
            }
            pager.neighbor.isHidden = swipe.target == nil
        }
        guard swipe.target != nil else {
            // Rubber band: the further the fingers go, the less the page follows.
            let travel = abs(swipe.distance)
            return -CGFloat(side) * (1 - 1 / (travel * 0.55 / width + 1)) * width * 0.35
        }
        let offset = -min(max(swipe.distance, -width), width)
        delegate?.sidebarSwipeProgress(toward: swipe.target, fraction: abs(offset) / width)
        return offset
    }

    private func neighborSpace(side: Int) -> Space? {
        guard side != 0, let state, let index = state.spaces.firstIndex(where: { $0 === state.activeSpace }) else { return nil }
        let next = index + side
        return state.spaces.indices.contains(next) ? state.spaces[next] : nil
    }

    /// Past a third of the way, or flicked toward it, the new Space comes in; otherwise
    /// the active one comes back. Either way at about the speed the fingers left off.
    private func finishSwipe() {
        guard let swipe else { return }
        self.swipe = nil
        let width = max(pager.bounds.width, 1)
        let offset = pager.offset
        let direction: CGFloat = offset < 0 ? -1 : 1
        let towardTarget = swipe.velocity * direction
        let commit = swipe.target != nil && offset != 0
            && ((abs(offset) > width / 3 && towardTarget > -150) || towardTarget > 350)
        let target = commit ? direction * width : 0
        let remaining = abs(target - offset)
        let duration = TimeInterval(min(max(3 * remaining / max(abs(swipe.velocity), 1), 0.14), 0.38))
        let glide = remaining < 1 ? 0 : duration
        if swipe.target != nil {
            delegate?.sidebarSwipeWillEnd(on: commit ? swipe.target : nil, duration: glide)
        }
        swipeSettling = true
        pager.animateOffset(to: target, duration: glide) { [weak self] in
            guard let self else { return }
            self.swipeSettling = false
            // The new Space takes the current page before the pager snaps back to it,
            // in the same pass, so nothing flickers.
            self.delegate?.sidebarSwipeEnded(on: commit ? swipe.target : nil)
            self.pager.reset()
        }
    }

    // MARK: - Hover (for the floating mode)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    // Like Arc, the address's copy button shows while the pointer is anywhere in the sidebar.
    override func mouseEntered(with event: NSEvent) {
        addressPill.showsCopyButton = true
        delegate?.sidebarMouseEntered()
    }

    override func mouseExited(with event: NSEvent) {
        addressPill.showsCopyButton = false
        delegate?.sidebarMouseExited()
    }

    // MARK: - Actions

    @objc private func backClicked() { delegate?.sidebarGoBack() }
    @objc private func forwardClicked() { delegate?.sidebarGoForward() }
    @objc private func reloadClicked() { delegate?.sidebarReload() }
    @objc private func collapseClicked() { delegate?.sidebarToggle() }
    @objc private func downloadsClicked() { delegate?.sidebarShowDownloads() }
    @objc private func addSpaceClicked() { delegate?.sidebarAddSpace() }
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
