import AppKit
import Combine

/// One browser window: glass background, sidebar, page area and command bar,
/// plus the Peek, the little windows and the settings it opens.
public final class BrowserWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    enum SidebarMode {
        /// Part of the layout, the page sits beside it.
        case docked
        /// Off screen; hovering the left edge brings it back as `floating`.
        case hidden
        /// Over the page, with its own glass and shadow, until the mouse leaves.
        case floating
    }

    public let state: BrowserState
    public let settings: ChordSettings
    /// This window's Space and selected tabs; the Spaces themselves are shared.
    public let selection: WindowSelection
    /// Called once the window has closed, for its host to let it go.
    public var onClose: ((BrowserWindowController) -> Void)?

    private let rootView = NSVisualEffectView()
    private let frostView = GlassFrostView()
    private let tintView = SpaceTintView()
    private let sidebar = SidebarView()
    private let pageArea = PageAreaView()
    private let edgeHover = EdgeHoverView()
    private lazy var commandBar = CommandBarController(state: state, settings: settings)
    private let siteControls = SiteControlsController()
    private var siteControlsTabID: UUID?
    private let permissionPrompt = PermissionPromptController()
    private let extensionPopup = ExtensionPopupController()
    private let toast = ToastView()
    /// The page searched with ⌘F while the find bar is up.
    private weak var findPage: ChordWebPage?
    /// True while a swipe hands its Space to the state, which needs no slide of its own.
    private var isEndingSwipe = false
    private lazy var peek = makePeek()
    private var settingsWindow: SettingsWindowController?
    private var littleWindows: [LittleWindowController] = []
    private lazy var downloadsPopover = makeDownloadsPopover()

    private var sidebarWidth: NSLayoutConstraint!
    private var sidebarLeading: NSLayoutConstraint!
    private var sidebarTop: NSLayoutConstraint!
    private var sidebarBottom: NSLayoutConstraint!
    private var cardLeadingDocked: NSLayoutConstraint!
    private var cardLeadingFree: NSLayoutConstraint!
    private var cardTop: NSLayoutConstraint!
    private var cardTrailing: NSLayoutConstraint!
    private var cardBottom: NSLayoutConstraint!

    private var sidebarMode = SidebarMode.docked
    private var pendingReveal: DispatchWorkItem?
    private var pendingHide: DispatchWorkItem?
    private var lastSpaceIndex = 0
    /// The pages this window showed last, to know which ones just left the screen.
    private let shownPages = NSHashTable<AnyObject>.weakObjects()
    /// The address bar's place as last laid out, to move it only when the Space's
    /// profile wants another one.
    private var shownAddressBarOnTop: Bool?
    /// One per pane, for the pages another window shows.
    private var elsewhereViews: [PageElsewhereView] = []
    private var cancellables = Set<AnyCancellable>()
    /// The title bar's views being watched, and a placing waiting for the next turn.
    private var trafficLightObservers: [NSObjectProtocol] = []
    private var trafficLightsPending = false

    private static let frameName = "ChordMainWindow"

    /// `cascadingFrom`: the window this one opens from (⌘N), which it sits next to.
    public init(state: BrowserState, settings: ChordSettings, cascadingFrom previous: NSWindow? = nil) {
        self.state = state
        self.settings = settings
        selection = state.openWindow()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        // Chord reopens its windows from its own session: macOS's window restoration
        // would only add its "reopen windows?" alert after a crash.
        window.isRestorable = false
        window.minSize = NSSize(width: 720, height: 480)
        window.title = state.isPrivate ? String(localized: "Private Browsing", bundle: .chordUI) : "Chord"
        // No system shadow: macOS draws its dark outline as part of the shadow, a black
        // line all around the glass. Without it the glass meets the desktop cleanly.
        window.hasShadow = false
        super.init(window: window)
        window.delegate = self

        state.withWindow(selection) {
            buildLayout()
            bindState()
            applyAppearanceSettings(animated: false)
            MainMenu.apply(settings.shortcutOverrides, to: NSApp.mainMenu)
            lastSpaceIndex = state.spaces.firstIndex { $0 === state.activeSpace } ?? 0
            refreshAll()
        }

        if let previous {
            // Next to the window it came from, like any Mac app's new window.
            window.setFrame(previous.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: previous.frame.minX, y: previous.frame.maxY)))
        } else if !state.isPrivate {
            if !window.setFrameUsingName(Self.frameName) { window.center() }
            _ = window.setFrameAutosaveName(Self.frameName)
        } else {
            window.center()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        positionTrafficLights()
        if state.isPrivate {
            DispatchQueue.main.async { [weak self] in self?.newTab(nil) }
        } else if !settings.arcImportOffered, state.isPristine, ArcImport.isAvailable {
            // First launch with Arc on this Mac: offer to bring its sidebar over.
            DispatchQueue.main.async { [weak self] in self?.offerArcImport() }
        } else if state.activeSpace.allTabs.isEmpty && state.favorites.isEmpty {
            // An empty Space: go straight to the command bar.
            DispatchQueue.main.async { [weak self] in self?.newTab(nil) }
        }
    }

    // MARK: - Layout

    private func buildLayout() {
        guard let window else { return }

        // The whole window is glass; the active Space tints it. It stays glass when the
        // window is inactive, like Arc: following the active state would turn it opaque grey.
        rootView.material = Theme.windowMaterial
        rootView.blendingMode = .behindWindow
        rootView.state = .active
        window.contentView = rootView

        sidebar.delegate = self
        edgeHover.isHidden = true
        edgeHover.onEnter = { [weak self] in self?.scheduleReveal() }
        edgeHover.onExit = { [weak self] in self?.pendingReveal?.cancel() }
        pageArea.onAction = { [weak self] action in self?.handle(action) }
        pageArea.moreMenu = { [weak self] in self?.moreMenu() ?? NSMenu() }
        setUpFindBar()
        pageArea.home.onSearch = { [weak self] in self?.newTab(nil) }
        pageArea.home.onOpen = { [weak self] tab in self?.sidebarSelect(tab) }

        // Back to front: frost, tint, pages, edge strip, sidebar. Overlays go on top later.
        for view in [frostView, tintView, pageArea, edgeHover, sidebar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            rootView.addSubview(view)
        }

        sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: settings.sidebarWidth)
        sidebarLeading = sidebar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor)
        sidebarTop = sidebar.topAnchor.constraint(equalTo: rootView.topAnchor)
        sidebarBottom = sidebar.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        cardLeadingDocked = pageArea.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor)
        cardLeadingFree = pageArea.leadingAnchor.constraint(equalTo: rootView.leadingAnchor)
        cardTop = pageArea.topAnchor.constraint(equalTo: rootView.topAnchor)
        cardTrailing = rootView.trailingAnchor.constraint(equalTo: pageArea.trailingAnchor)
        cardBottom = rootView.bottomAnchor.constraint(equalTo: pageArea.bottomAnchor)

        NSLayoutConstraint.activate([
            frostView.topAnchor.constraint(equalTo: rootView.topAnchor),
            frostView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            frostView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            frostView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            tintView.topAnchor.constraint(equalTo: rootView.topAnchor),
            tintView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            tintView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

            sidebarWidth, sidebarLeading, sidebarTop, sidebarBottom,
            cardLeadingDocked, cardTop, cardTrailing, cardBottom,

            edgeHover.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            edgeHover.topAnchor.constraint(equalTo: rootView.topAnchor),
            edgeHover.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            edgeHover.widthAnchor.constraint(equalToConstant: 6),
        ])
    }

    private func applyAppearanceSettings(animated: Bool) {
        let edgeless = settings.edgeless
        let inset = edgeless ? 0 : Theme.contentInset
        cardTop.constant = inset
        cardTrailing.constant = inset
        cardBottom.constant = inset
        cardLeadingFree.constant = inset
        sidebarWidth.constant = settings.sidebarWidth
        if sidebarMode == .hidden { sidebarLeading.constant = -(settings.sidebarWidth + 32) }
        let onTop = addressBarOnTop
        shownAddressBarOnTop = onTop
        pageArea.setStyle(edgeless: edgeless, toolbarOnTop: onTop, accent: state.activeSpace.accent)
        sidebar.setAddressBarOnTop(onTop)
        commandBar.isGlass = settings.commandBarGlass
        let appearance = settings.appearance.nsAppearance
        // Private browsing is always dark, so that it is never mistaken for a normal window.
        window?.appearance = state.isPrivate ? NSAppearance(named: .darkAqua) : appearance
        settingsWindow?.window?.appearance = appearance
        for little in littleWindows { little.window?.appearance = appearance }
        layoutChanges(animated: animated)
        reanchorPermissionPrompt()
    }

    private func layoutChanges(animated: Bool) {
        guard animated else {
            rootView.layoutSubtreeIfNeeded()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.motionDuration
            context.timingFunction = Theme.motionCurve
            context.allowsImplicitAnimation = true
            self.rootView.layoutSubtreeIfNeeded()
        }
    }

    /// The Space colour on the window glass, and on the sidebar's own glass when it floats.
    private func setTint(_ color: NSColor, duration: TimeInterval = 0) {
        tintView.setColor(color, duration: duration)
        sidebar.setTint(color, duration: duration)
    }

    private func updateTint(animated: Bool) {
        setTint(state.activeSpace.color, duration: animated ? Theme.motionDuration : 0)
        pageArea.setStyle(edgeless: settings.edgeless, toolbarOnTop: addressBarOnTop, accent: state.activeSpace.accent)
    }

    /// Where the address bar sits in this window: the choice of its Space's profile, else
    /// the default of the settings.
    private var addressBarOnTop: Bool {
        state.addressBarOnTop(for: state.activeSpace) ?? settings.addressBarOnTop
    }

    /// Moves the address bar when the Space now shown, or its profile, wants it elsewhere.
    private func updateAddressBarPosition(animated: Bool) {
        let onTop = addressBarOnTop
        guard onTop != shownAddressBarOnTop else { return }
        shownAddressBarOnTop = onTop
        pageArea.setStyle(edgeless: settings.edgeless, toolbarOnTop: onTop, accent: state.activeSpace.accent)
        sidebar.setAddressBarOnTop(onTop)
        layoutChanges(animated: animated)
        reanchorPermissionPrompt()
    }

    // MARK: - Sidebar modes

    private func setSidebarMode(_ mode: SidebarMode, animated: Bool) {
        guard mode != sidebarMode else { return }
        let interval = Perf.begin("sidebar.toggle")
        let previous = sidebarMode
        sidebarMode = mode
        pendingReveal?.cancel()
        pendingHide?.cancel()

        switch mode {
        case .docked:
            cardLeadingFree.isActive = false
            cardLeadingDocked.isActive = true
            sidebarLeading.constant = 0
            sidebarTop.constant = 0
            sidebarBottom.constant = 0
            sidebar.setFloating(false)
        case .hidden:
            cardLeadingDocked.isActive = false
            cardLeadingFree.isActive = true
            sidebarLeading.constant = -(settings.sidebarWidth + 32)
            // A floating sidebar slides away as it is; a docked one keeps its flat look.
            sidebar.setFloating(previous == .floating)
        case .floating:
            cardLeadingDocked.isActive = false
            cardLeadingFree.isActive = true
            sidebarLeading.constant = 4
            sidebarTop.constant = 0
            sidebarBottom.constant = -6
            sidebar.setFloating(true)
        }

        edgeHover.isHidden = mode != .hidden
        setTrafficLightsHidden(mode == .hidden)
        if mode != .hidden {
            // Shown again, the traffic lights are back where macOS puts them: move them
            // to the sidebar's row now, and again once AppKit has laid its title bar out.
            positionTrafficLights()
            DispatchQueue.main.async { [weak self] in self?.positionTrafficLights() }
        }
        layoutChanges(animated: animated)
        reanchorPermissionPrompt()
        DispatchQueue.main.async { interval.end() }
    }

    /// Moves the traffic lights down to the sidebar's first row, centred on it like Arc's,
    /// by making the title bar's container taller and centring the buttons in it (the way
    /// Electron's trafficLightPosition works). macOS lays the title bar out again on
    /// resizes, key changes, full screen, and whenever the window's title changes (each
    /// page title): the title bar's views are watched, and the lights go back as soon as
    /// macOS moves them.
    private func positionTrafficLights() {
        guard let window, !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview, let container = titlebar.superview else { return }
        if trafficLightObservers.isEmpty {
            for view in [container, titlebar, close] {
                view.postsFrameChangedNotifications = true
                trafficLightObservers.append(NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                    self?.schedulePositionTrafficLights()
                })
            }
        }
        let height = Theme.titleRowCenter * 2
        var frame = container.frame
        if frame.height != height || frame.maxY != window.frame.height {
            frame.size.height = height
            frame.origin.y = window.frame.height - height
            container.frame = frame
        }
        titlebar.frame = container.bounds
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(kind) else { continue }
            let y = ((height - button.frame.height) / 2).rounded()
            if button.frame.minY != y { button.setFrameOrigin(NSPoint(x: button.frame.minX, y: y)) }
        }
        sidebar.needsLayout = true
    }

    /// Once AppKit has finished laying the title bar out (moving the lights there would
    /// be undone by the rest of its pass).
    private func schedulePositionTrafficLights() {
        guard !trafficLightsPending else { return }
        trafficLightsPending = true
        DispatchQueue.main.async { [weak self] in
            self?.trafficLightsPending = false
            self?.positionTrafficLights()
        }
    }

    public func windowDidResize(_ notification: Notification) { positionTrafficLights() }
    public func windowDidEndLiveResize(_ notification: Notification) { positionTrafficLights() }
    /// The window the user turns to: its selection is the one actions apply to, and its
    /// pages come back if another window was showing them.
    public func windowDidBecomeKey(_ notification: Notification) {
        positionTrafficLights()
        state.activate(selection)
        showSelectedPage(focus: false)
    }
    public func windowDidResignKey(_ notification: Notification) { positionTrafficLights() }
    public func windowDidExitFullScreen(_ notification: Notification) { positionTrafficLights() }

    private func setTrafficLightsHidden(_ hidden: Bool) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    /// Waits a little so that brushing past the edge does not open the sidebar.
    private func scheduleReveal() {
        guard sidebarMode == .hidden else { return }
        pendingReveal?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.sidebarMode == .hidden else { return }
            self.setSidebarMode(.floating, animated: true)
        }
        pendingReveal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func scheduleHide() {
        guard sidebarMode == .floating else { return }
        pendingHide?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.sidebarMode == .floating, !self.commandBar.isVisible, !self.siteControls.isVisible,
                  !self.permissionPrompt.isVisible, !self.extensionPopup.isVisible else { return }
            self.setSidebarMode(.hidden, animated: true)
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - State

    private func bindState() {
        // Each window draws the change with its own selection.
        state.changes
            .sink { [weak self] change in
                guard let self else { return }
                self.state.withWindow(self.selection) { self.handle(change) }
            }
            .store(in: &cancellables)
        settings.changes
            .sink { [weak self] key in
                guard let self else { return }
                self.state.withWindow(self.selection) { self.handle(key) }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: PageHostView.didMoveNotification)
            .sink { [weak self] _ in self?.pagesDidMove() }
            .store(in: &cancellables)
        commandBar.actionsProvider = { [weak self] in self?.commandActions() ?? [] }
        commandBar.onDismiss = { [weak self] in self?.focusPage() }
        permissionPrompt.onClose = { [weak self] in self?.permissionPromptClosed() }
        let extensionActions = makeExtensionActions()
        sidebar.extensionActions = extensionActions
        pageArea.toolbar.extensionActions = extensionActions
        siteControls.extensionActions = extensionActions
        extensionPopup.onClose = { [weak self] in self?.extensionPopupClosed() }
    }

    private func handle(_ key: ChordSettings.Key) {
        switch key {
        case .sidebarWidth:
            sidebarWidth.constant = settings.sidebarWidth
        case .shortcuts:
            MainMenu.apply(settings.shortcutOverrides, to: NSApp.mainMenu)
        case .searchTemplate:
            break
        case .pictureInPicture:
            break
        case .edgeless, .appearance, .addressBar, .commandBar:
            applyAppearanceSettings(animated: key == .edgeless || key == .addressBar)
        }
    }

    private func handle(_ change: StateChange) {
        switch change {
        case .spaces:
            updateTint(animated: true)
            updateAddressBarPosition(animated: true)
            sidebar.update(state: state)
            showSelectedPage(focus: false)
        case .tabs:
            sidebar.update(state: state)
            showSelectedPage(focus: false)
        case .activeSpace:
            let interval = Perf.begin("space.switch")
            let index = state.spaces.firstIndex { $0 === state.activeSpace } ?? 0
            // A swipe has already slid the sidebar to the new Space.
            if index != lastSpaceIndex, !isEndingSwipe { sidebar.pager.slide(forward: index > lastSpaceIndex) }
            lastSpaceIndex = index
            updateTint(animated: true)
            updateAddressBarPosition(animated: true)
            sidebar.update(state: state)
            showSelectedPage(focus: true)
            DispatchQueue.main.async { interval.end() }
        case .selection:
            sidebar.update(state: state)
            showSelectedPage(focus: true)
        case .tab(let id):
            guard let tab = state.tab(withID: id) else { return }
            if tab.isFavorite {
                sidebar.update(state: state)
            } else {
                sidebar.tabList.reloadTab(id: id)
            }
            pageArea.refresh(tab: tab)
            if let selected = state.selectedTab, selected.id == id {
                sidebar.updateNavigation(tab: selected)
                window?.title = selected.displayTitle
            }
        case .downloadStarted:
            // Like Arc, a new download shows itself.
            if window?.isKeyWindow == true, !downloadsPopover.isShown { showDownloads(nil) }
        case .peek(let url):
            presentPeek(url)
        case .permission(let ask):
            presentPermission(ask)
        case .extensions:
            updateExtensions()
            siteControls.refresh()
        case .addressBar:
            updateAddressBarPosition(animated: true)
        case .findResult(let result):
            if result.page === findPage, !pageArea.findBar.isHidden {
                pageArea.findBar.showResult(count: result.count, activeMatch: result.activeMatch)
            }
        }
    }

    private func refreshAll() {
        updateTint(animated: false)
        updateAddressBarPosition(animated: false)
        sidebar.update(state: state)
        showSelectedPage(focus: false)
    }

    private func showSelectedPage(focus: Bool) {
        let tabs = state.visibleTabs
        // A page has a single view. The window the user acts in takes it from another
        // window that selected the same tab, which then says where it went.
        let isKey = window?.isKeyWindow == true
        let views = tabs.enumerated().map { index, tab -> NSView in
            let host = PageHostView.host(for: state.page(for: tab))
            guard !isKey, let other = host.window, other !== window, other.isVisible else { return host }
            return elsewhereView(at: index)
        }
        let selected = state.selectedTab
        if tabs.isEmpty { pageArea.home.update(space: state.activeSpace, favorites: state.favorites) }
        pageArea.show(tabs: tabs, views: views, activeID: selected?.id)
        window?.title = selected?.displayTitle ?? (state.isPrivate ? String(localized: "Private Browsing", bundle: .chordUI) : "Chord")
        if focus, let view = selected?.page?.view, view.window === window, !commandBar.isVisible, !peek.isVisible {
            window?.makeFirstResponder(view)
        }
        sidebar.updateNavigation(tab: selected)
        updateExtensions()
        // Only the key window's page is the engine's active one.
        if window?.isKeyWindow == true { selected?.page?.didBecomeActive?() }
        updatePictureInPicture(showing: tabs.compactMap(\.page))
        // The site controls belong to the page they were opened on.
        if siteControls.isVisible, siteControlsTabID != selected?.id { siteControls.dismiss() }
        // So does the find bar.
        if !pageArea.findBar.isHidden, findPage !== selected?.page { closeFindBar(focusPage: false) }
    }

    private func elsewhereView(at index: Int) -> PageElsewhereView {
        while elsewhereViews.count <= index { elsewhereViews.append(PageElsewhereView()) }
        return elsewhereViews[index]
    }

    /// A page moved between windows: this window takes back a page of its selection
    /// that is free again, or says where one went.
    private func pagesDidMove() {
        guard pageArea.isMissingPage else { return }
        state.withWindow(selection) { showSelectedPage(focus: false) }
    }

    /// Like Arc: a video playing in a page that leaves the screen carries on in a
    /// picture-in-picture window, and a page back on screen takes its video back.
    private func updatePictureInPicture(showing pages: [ChordWebPage]) {
        let showing = Set(pages.map { ObjectIdentifier($0) })
        let previous = shownPages.allObjects.compactMap { $0 as? ChordWebPage }
        let previousIDs = Set(previous.map { ObjectIdentifier($0) })
        if settings.autoPictureInPicture {
            for page in previous where !showing.contains(ObjectIdentifier(page)) {
                page.enterPictureInPictureIfPlaying?()
            }
        }
        for page in pages where !previousIDs.contains(ObjectIdentifier(page)) {
            page.exitPictureInPicture?()
        }
        shownPages.removeAllObjects()
        pages.forEach { shownPages.add($0) }
    }

    private func focusPage() {
        if let view = state.selectedTab?.page?.view {
            window?.makeFirstResponder(view)
        }
    }

    /// Every way of copying an address ends here, so that each one shows the toast.
    private func copy(_ url: URL?) {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        toast.show(String(localized: "URL copied", bundle: .chordUI), detail: url.displayHost, symbol: "checkmark.circle.fill", in: rootView, over: pageArea, accent: state.activeSpace.accent)
    }

    private func handle(_ action: PageBarAction) {
        switch action {
        case .back: goBack(nil)
        case .forward: goForward(nil)
        case .reload: reloadOrStop()
        case .address: openLocation(nil)
        case .split: toggleSplitView(nil)
        case .copyURL: copyURL(nil)
        case .siteControls(let anchor): showSiteControls(from: anchor)
        case .closePane(let tab): state.removeFromSplit(tab)
        case .activate(let tab): sidebarSelect(tab)
        }
    }

    private func moreMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(closureItem(String(localized: "Copy URL", bundle: .chordUI)) { [weak self] in self?.copyURL(nil) })
        menu.addItem(closureItem(String(localized: "Open in Little Window", bundle: .chordUI)) { [weak self] in
            guard let self, let url = self.state.selectedTab?.url else { return }
            self.openLittleWindow(url: url)
        })
        menu.addItem(.separator())
        menu.addItem(closureItem(String(localized: "Address Bar in Sidebar", bundle: .chordUI)) { [weak self] in
            guard let self else { return }
            self.state.setAddressBarOnTop(false, for: self.state.activeSpace)
        })
        menu.addItem(closureItem(settings.edgeless ? String(localized: "Turn Off Edgeless Mode", bundle: .chordUI) : String(localized: "Turn On Edgeless Mode", bundle: .chordUI)) { [weak self] in self?.toggleEdgeless(nil) })
        menu.addItem(.separator())
        menu.addItem(closureItem(String(localized: "Settings…", bundle: .chordUI)) { [weak self] in self?.showSettings(nil) })
        return menu
    }

    // MARK: - Command bar

    private func presentCommandBar(mode: CommandBarController.Mode, text: String, anchoredTo anchor: NSView? = nil) {
        pendingHide?.cancel()
        if peek.isVisible { peek.dismiss() }
        commandBar.present(in: rootView, centeredOn: pageArea, anchoredTo: anchor, mode: mode, text: text, accent: state.activeSpace.accent)
    }

    /// The address field on screen, if there is one: the top bar's, or the sidebar's
    /// while the sidebar shows.
    private var visibleAddressField: NSView? {
        let toolbarAddress = pageArea.toolbar.addressAnchor
        if addressBarOnTop {
            return toolbarAddress.window != nil && !toolbarAddress.isHiddenOrHasHiddenAncestor ? toolbarAddress : nil
        }
        return sidebarMode == .hidden ? nil : sidebar.addressAnchor
    }

    private func commandActions() -> [CommandItem] {
        let selected = state.selectedTab
        var actions = [
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: state.isSplit ? String(localized: "Exit Split View", bundle: .chordUI) : String(localized: "Open in Split View", bundle: .chordUI),
                        symbol: "rectangle.split.2x1", shortcut: "⌃⇧=", action: .run { [weak self] in self?.toggleSplitView(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Open in Little Window", bundle: .chordUI), symbol: "macwindow.on.rectangle", shortcut: "⌥⌘N",
                        action: .run { [weak self] in self?.openLittleWindow(url: self?.state.selectedTab?.url) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "New Tab in Space \(state.activeSpace.name)", bundle: .chordUI), symbol: "plus", shortcut: "⌘T",
                        action: .run { [weak self] in self?.newTab(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: sidebarMode == .docked ? String(localized: "Hide Sidebar", bundle: .chordUI) : String(localized: "Show Sidebar", bundle: .chordUI),
                        symbol: "sidebar.left", shortcut: "⌘S", action: .run { [weak self] in self?.toggleSidebarVisibility(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Copy URL", bundle: .chordUI), symbol: "link", shortcut: "⇧⌘C",
                        action: .run { [weak self] in self?.copyURL(nil) }),
        ]
        if let selected {
            actions += [
                CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: selected.isPinned ? String(localized: "Unpin Tab", bundle: .chordUI) : String(localized: "Pin Tab", bundle: .chordUI), symbol: "pin",
                            shortcut: "⌘D", action: .run { [weak self] in self?.togglePinTab(nil) }),
                CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: selected.isFavorite ? String(localized: "Remove from Favorites", bundle: .chordUI) : String(localized: "Add to Favorites", bundle: .chordUI), symbol: "star",
                            action: .run { [weak self] in self?.toggleFavoriteTab(nil) }),
            ]
        }
        actions += [
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Reopen Closed Tab", bundle: .chordUI), symbol: "arrow.uturn.backward", shortcut: "⇧⌘T",
                        action: .run { [weak self] in self?.reopenClosedTab(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Browser Settings", bundle: .chordUI), subtitle: "chord://settings", symbol: "gearshape",
                        action: .run { [weak self] in self?.openInternalPage("settings") }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Extensions", bundle: .chordUI), subtitle: "chord://extensions", symbol: "puzzlepiece.extension",
                        action: .run { [weak self] in self?.openInternalPage("extensions") }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "New Folder", bundle: .chordUI), symbol: "folder.badge.plus",
                        action: .run { [weak self] in self?.newFolder(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "New Space", bundle: .chordUI), symbol: "square.stack",
                        action: .run { [weak self] in self?.newSpace(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Rename Space", bundle: .chordUI), symbol: "pencil",
                        action: .run { [weak self] in self?.renameSpace(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Next Space", bundle: .chordUI), symbol: "arrow.right.square", shortcut: "⌥⌘→",
                        action: .run { [weak self] in self?.nextSpace(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: addressBarOnTop ? String(localized: "Address Bar in Sidebar", bundle: .chordUI) : String(localized: "Address Bar on Top", bundle: .chordUI),
                        symbol: "menubar.rectangle", shortcut: "⇧⌘D", action: .run { [weak self] in self?.toggleAddressBarPosition(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: settings.edgeless ? String(localized: "Turn Off Edgeless Mode", bundle: .chordUI) : String(localized: "Turn On Edgeless Mode", bundle: .chordUI),
                        symbol: "rectangle.inset.filled", action: .run { [weak self] in self?.toggleEdgeless(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Import from Arc", bundle: .chordUI), symbol: "square.and.arrow.down",
                        action: .run { [weak self] in self?.importFromArc(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Import Logins from Arc", bundle: .chordUI), symbol: "key",
                        action: .run { [weak self] in self?.importArcLogins(nil) }),
            CommandItem(section: String(localized: "Actions", bundle: .chordUI), title: String(localized: "Settings", bundle: .chordUI), symbol: "gearshape", shortcut: "⌘,",
                        action: .run { [weak self] in self?.showSettings(nil) }),
        ]
        return actions
    }

    // MARK: - Peek

    private func makePeek() -> PeekController {
        let peek = PeekController(engine: { [state] in state.engine(for: state.activeSpace) })
        peek.onOpenInTab = { [weak self] page in
            guard let self else { return }
            self.state.openTab(url: page.url ?? URL(string: "about:blank")!, adopting: page)
        }
        peek.onSplit = { [weak self] page in
            guard let self else { return }
            let tab = self.state.openTab(url: page.url ?? URL(string: "about:blank")!, select: false, adopting: page)
            self.state.addToSplit(tab)
        }
        peek.onNewTab = { [weak self] url in self?.state.openTab(url: url) }
        peek.onDismiss = { [weak self] in self?.focusPage() }
        return peek
    }

    private func presentPeek(_ url: URL) {
        if commandBar.isVisible { commandBar.dismiss() }
        let inset = sidebarMode == .docked ? settings.sidebarWidth : 0
        peek.present(url: url, in: rootView, contentInset: inset, accent: state.activeSpace.accent)
    }

    // MARK: - Permission prompts

    /// A site's question, from the window that shows its page. For the selected page it
    /// hangs from the site controls, like Arc's, and a closed sidebar comes back floating
    /// to hold it; for another page (a split pane, a Peek), from the top of the page.
    private func presentPermission(_ ask: PermissionAsk) {
        if let little = littleWindows.first(where: { $0.shows(ask.page) }) {
            little.presentPermission(ask.request)
            return
        }
        guard let window, ask.page.view.window === window else { return }
        if ask.page === state.selectedTab?.page, !addressBarOnTop, sidebarMode == .hidden {
            setSidebarMode(.floating, animated: true)
            // Once the sidebar has slid in, so that the question appears where it stays.
            DispatchQueue.main.asyncAfter(deadline: .now() + Theme.motionDuration) { [weak self] in
                self?.showPermission(ask)
            }
            return
        }
        showPermission(ask)
    }

    private func showPermission(_ ask: PermissionAsk) {
        let anchor = permissionAnchor(for: ask.page)
        permissionPrompt.present(ask.request, for: ask.page, from: anchor.view, rect: anchor.rect)
    }

    /// The selected page's site controls when they are on screen, else the top of the page.
    private func permissionAnchor(for page: ChordWebPage) -> (view: NSView, rect: NSRect?) {
        if page === state.selectedTab?.page {
            if addressBarOnTop {
                let button = pageArea.toolbar.siteControlsAnchor
                if button.window != nil, !button.isHiddenOrHasHiddenAncestor { return (button, nil) }
            } else if sidebarMode != .hidden {
                sidebar.pinsAddressButtons = true
                sidebar.layoutSubtreeIfNeeded()
                return (sidebar.siteControlsAnchor, nil)
            }
        }
        return (page.view, PermissionPromptController.pageTop(of: page.view))
    }

    /// The question follows its anchor when the sidebar or the address bar moves.
    private func reanchorPermissionPrompt() {
        guard permissionPrompt.isVisible else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.motionDuration) { [weak self] in
            guard let self, self.permissionPrompt.isVisible, let page = self.permissionPrompt.page else { return }
            let anchor = self.permissionAnchor(for: page)
            // The page may have left this window while the layout moved.
            guard anchor.view.window === self.window else { return }
            self.permissionPrompt.reanchor(to: anchor.view, rect: anchor.rect)
        }
    }

    private func resumePermissionPrompt() {
        guard permissionPrompt.isSuspended, let page = permissionPrompt.page else { return }
        let anchor = permissionAnchor(for: page)
        permissionPrompt.resume(from: anchor.view, rect: anchor.rect)
    }

    private func permissionPromptClosed() {
        sidebar.pinsAddressButtons = false
        // A sidebar that came out for the question goes away again, unless the pointer is in it.
        if sidebarMode == .floating, let window,
           !sidebar.bounds.contains(sidebar.convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
            scheduleHide()
        }
    }

    // MARK: - Extensions

    /// What extensions' buttons do, in the address fields and the site card: always on
    /// the selected page.
    private func makeExtensionActions() -> ExtensionActions {
        ExtensionActions(
            run: { [weak self] item, anchor in self?.runExtension(item, from: anchor) },
            setPinned: { [weak self] item, pinned in self?.state.selectedTab?.page?.setExtension?(item.id, pinned: pinned) },
            open: { [weak self] url in self?.state.openTab(url: url) },
            uninstall: { [weak self] item in self?.confirmUninstall(item) }
        )
    }

    /// The pinned extensions of the selected page, with its badges, in the address.
    private func updateExtensions() {
        let pinned = PageExtension.all(of: state.selectedTab?.page).filter(\.isPinned)
        sidebar.setExtensions(pinned)
        pageArea.toolbar.setExtensions(pinned)
    }

    /// Like a click on the extension's button in Chrome: it acts on the selected page,
    /// and its popup, if it has one, hangs from `anchor`.
    private func runExtension(_ item: PageExtension, from anchor: NSView) {
        guard let page = state.selectedTab?.page else { return }
        page.didBecomeActive?()
        guard let popup = page.runExtension?(item.id) else { return }
        // The sidebar's buttons stay while the popup hangs from one of them.
        if anchor.isDescendant(of: sidebar) { sidebar.pinsAddressButtons = true }
        pendingHide?.cancel()
        extensionPopup.show(popup, from: anchor)
    }

    private func extensionPopupClosed() {
        if !permissionPrompt.isVisible { sidebar.pinsAddressButtons = false }
        if sidebarMode == .floating, let window,
           !sidebar.bounds.contains(sidebar.convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
            scheduleHide()
        }
        focusPage()
    }

    private func confirmUninstall(_ item: PageExtension) {
        guard let window, let page = state.selectedTab?.page else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Remove “\(item.name)”?", bundle: .chordUI)
        alert.informativeText = String(localized: "The extension and its data are removed from this profile.", bundle: .chordUI)
        alert.addButton(withTitle: String(localized: "Remove", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            page.uninstallExtension?(item.id)
        }
    }

    // MARK: - Little windows

    /// Opens a little window (Little Arc), on `url` or empty with the address focused.
    /// The host calls this for links opened from other apps.
    public func openLittleWindow(url: URL?) {
        let interval = Perf.begin("littlewindow.open")
        // Like Little Arc: the page goes to the last Space used, unless another is picked.
        let little = LittleWindowController(engine: state.engine(for: state.activeSpace), settings: settings, url: url,
                                            space: state.activeSpace, spaces: { [weak self] in self?.state.spaces ?? [] })
        little.onOpenInChord = { [weak self] page, space in
            guard let self else { return }
            let target = self.state.spaces.contains { $0 === space } ? space : self.state.activeSpace
            self.state.openTab(url: page.url ?? URL(string: "about:blank")!, adopting: page, in: target)
            self.window?.makeKeyAndOrderFront(nil)
        }
        little.onNewTab = { [weak self] url in self?.state.openTab(url: url) }
        little.onClose = { [weak self] closed in self?.littleWindows.removeAll { $0 === closed } }
        littleWindows.append(little)
        little.showWindow(nil)
        if url == nil { little.focusAddress() }
        DispatchQueue.main.async { interval.end() }
    }

    // MARK: - Arc import

    private func offerArcImport() {
        guard let window else { return }
        settings.arcImportOffered = true
        let alert = NSAlert()
        alert.messageText = String(localized: "Bring over your Arc sidebar?", bundle: .chordUI)
        alert.informativeText = String(localized: "Chord found Arc on this Mac. Your Spaces, favorites and pinned tabs can come over as they are. Arc is left unchanged.", bundle: .chordUI)
        alert.addButton(withTitle: String(localized: "Import", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Later", bundle: .chordUI))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                self.importFromArc(nil)
            } else {
                self.newTab(nil)
            }
        }
    }

    // MARK: - Spaces

    private func promptRename(_ space: Space) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Space", bundle: .chordUI)
        alert.addButton(withTitle: String(localized: "Rename", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
        let field = NSTextField(string: space.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.state.rename(space, to: field.stringValue)
        }
    }

    private func promptRename(_ folder: Folder) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Folder", bundle: .chordUI)
        alert.addButton(withTitle: String(localized: "Rename", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
        let field = NSTextField(string: folder.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.state.rename(folder, to: field.stringValue)
        }
    }

    private func confirmDelete(_ folder: Folder) {
        guard let window else { return }
        let count = folder.tabs.count
        guard count > 0 else {
            state.delete(folder)
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete the folder “\(folder.name)”?", bundle: .chordUI)
        alert.informativeText = count == 1 ? String(localized: "Its tab will be closed.", bundle: .chordUI) : String(localized: "Its \(count) tabs will be closed. “Ungroup” keeps the tabs.", bundle: .chordUI)
        alert.addButton(withTitle: String(localized: "Delete", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.state.delete(folder)
        }
    }

    /// Asks first when tabs would close, or when the Space takes its profile with it.
    private func confirmDelete(_ space: Space) {
        guard let window else { return }
        let count = space.allTabs.count
        let deletesProfile = state.isLastSpace(ofItsProfile: space)
        guard count > 0 || deletesProfile else {
            state.delete(space)
            return
        }
        var details: [String] = []
        if count > 0 { details.append(count == 1 ? String(localized: "Its tab will be closed.", bundle: .chordUI) : String(localized: "Its \(count) tabs will be closed.", bundle: .chordUI)) }
        if deletesProfile { details.append(BrowserState.profileDeletionWarning) }
        let alert = NSAlert()
        alert.messageText = deletesProfile
            ? String(localized: "Delete the Space “\(space.name)” and its profile?", bundle: .chordUI)
            : String(localized: "Delete the Space “\(space.name)”?", bundle: .chordUI)
        alert.informativeText = details.joined(separator: " ")
        alert.addButton(withTitle: String(localized: "Delete", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.state.delete(space)
        }
    }

    // MARK: - Menu actions (reached through the responder chain)

    @objc public func newTab(_ sender: Any?) {
        presentCommandBar(mode: .newTab, text: "")
    }

    @objc public func newLittleWindow(_ sender: Any?) {
        openLittleWindow(url: nil)
    }

    /// ⌘L or a click on the address: like Arc, the compact bar over the address field
    /// when one is on screen.
    @objc public func openLocation(_ sender: Any?) {
        presentCommandBar(mode: .currentTab, text: state.selectedTab?.url?.editableString ?? "", anchoredTo: visibleAddressField)
    }

    @objc public func closeTab(_ sender: Any?) {
        if peek.isVisible {
            peek.dismiss()
        } else if siteControls.isVisible {
            siteControls.dismiss()
        } else if commandBar.isVisible {
            commandBar.dismiss()
        } else if let tab = state.selectedTab {
            state.close(tab)
        }
    }

    @objc public func reopenClosedTab(_ sender: Any?) {
        state.reopenClosedTab()
    }

    /// ⌘S, and ⌘B. Not named `toggleSidebar:`: AppKit's windows answer that action for
    /// their own split-view sidebars and disable it, so the menu item never reached Chord.
    @objc public func toggleSidebarVisibility(_ sender: Any?) {
        setSidebarMode(sidebarMode == .docked ? .hidden : .docked, animated: true)
    }

    /// ⌃⇧=: from a Peek, puts it beside the page; otherwise opens a split by asking for
    /// the second page in the command bar, or leaves the split on screen.
    @objc public func toggleSplitView(_ sender: Any?) {
        let interval = Perf.begin("split.toggle")
        if peek.isVisible {
            peek.openInSplit()
        } else if state.isSplit {
            state.unsplit()
        } else if state.selectedTab != nil {
            presentCommandBar(mode: .split, text: "")
        }
        DispatchQueue.main.async { interval.end() }
    }

    @objc public func toggleEdgeless(_ sender: Any?) {
        settings.edgeless.toggle()
    }

    /// Only for the profile of the Space shown: Spaces on other profiles keep theirs.
    @objc public func toggleAddressBarPosition(_ sender: Any?) {
        state.setAddressBarOnTop(!addressBarOnTop, for: state.activeSpace)
    }

    @objc public func togglePinTab(_ sender: Any?) {
        if let tab = state.selectedTab { state.togglePin(tab) }
    }

    @objc public func toggleFavoriteTab(_ sender: Any?) {
        if let tab = state.selectedTab { state.toggleFavorite(tab) }
    }

    /// A folder in the pinned tabs, named right away.
    @objc public func newFolder(_ sender: Any?) {
        promptRename(state.newFolder())
    }

    @objc public func reloadPage(_ sender: Any?) {
        state.selectedTab?.page?.reload()
    }

    /// ⇧⌘R: reload without the cache, falling back to a plain reload.
    @objc public func reloadPageIgnoringCache(_ sender: Any?) {
        guard let page = state.selectedTab?.page else { return }
        if let reloadIgnoringCache = page.reloadIgnoringCache { reloadIgnoringCache() } else { page.reload() }
    }

    @objc public func stopLoading(_ sender: Any?) {
        state.selectedTab?.page?.stopLoading()
    }

    /// ⌥⌘I, when the engine has developer tools (Chromium's DevTools).
    @objc public func toggleDevTools(_ sender: Any?) {
        state.selectedTab?.page?.toggleDevTools?()
    }

    /// ⌃⌘P: the page's video in a picture-in-picture window, or back.
    @objc public func togglePictureInPicture(_ sender: Any?) {
        state.selectedTab?.page?.togglePictureInPicture?()
    }

    /// The reload buttons turn into stop buttons while the page loads, like Arc's.
    private func reloadOrStop() {
        if state.selectedTab?.page?.isLoading == true { stopLoading(nil) } else { reloadPage(nil) }
    }

    @objc public func goBack(_ sender: Any?) {
        state.selectedTab?.page?.goBack()
    }

    @objc public func goForward(_ sender: Any?) {
        state.selectedTab?.page?.goForward()
    }

    @objc public func nextTab(_ sender: Any?) {
        state.selectTab(offset: 1)
    }

    @objc public func previousTab(_ sender: Any?) {
        state.selectTab(offset: -1)
    }

    /// ⌘1…⌘9; the menu item's tag is the number.
    @objc public func selectTabByNumber(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        state.selectTab(number: item.tag)
    }

    @objc public func copyURL(_ sender: Any?) {
        copy(state.selectedTab?.url)
    }

    // MARK: - Find, zoom, print

    private func setUpFindBar() {
        let bar = pageArea.findBar
        bar.onChange = { [weak self] text in self?.findPage?.find?(text, forward: true) }
        bar.onNext = { [weak self] in self?.findNext(nil) }
        bar.onPrevious = { [weak self] in self?.findPrevious(nil) }
        bar.onClose = { [weak self] in self?.closeFindBar(focusPage: true) }
    }

    /// ⌘F: the find bar over the selected page, its text selected to type a new one.
    /// The text stays from one search to the next, like Safari's.
    @objc public func showFindBar(_ sender: Any?) {
        guard let page = state.selectedTab?.page, page.find != nil else { return }
        let interval = Perf.begin("find.open")
        if commandBar.isVisible { commandBar.dismiss() }
        let bar = pageArea.findBar
        let wasHidden = bar.isHidden
        if findPage !== page {
            findPage?.stopFinding?()
            findPage = page
        }
        if wasHidden {
            bar.clearResult()
            bar.isHidden = false
            pageArea.needsLayout = true
            pageArea.layoutSubtreeIfNeeded()
            bar.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                bar.animator().alphaValue = 1
            }
            // Searches the text left from the last time again.
            if !bar.text.isEmpty { page.find?(bar.text, forward: true) }
        }
        bar.focus()
        DispatchQueue.main.async { interval.end() }
    }

    /// ⌘G and ⇧⌘G: the next or previous match, opening the find bar if needed.
    @objc public func findNext(_ sender: Any?) {
        find(forward: true)
    }

    @objc public func findPrevious(_ sender: Any?) {
        find(forward: false)
    }

    private func find(forward: Bool) {
        let bar = pageArea.findBar
        guard !bar.isHidden, let page = findPage else {
            showFindBar(nil)
            return
        }
        guard !bar.text.isEmpty else { return }
        page.find?(bar.text, forward: forward)
    }

    private func closeFindBar(focusPage focus: Bool) {
        let bar = pageArea.findBar
        guard !bar.isHidden else { return }
        findPage?.stopFinding?()
        findPage = nil
        bar.isHidden = true
        if focus { focusPage() }
    }

    @objc public func zoomIn(_ sender: Any?) { zoom(1) }
    @objc public func zoomOut(_ sender: Any?) { zoom(-1) }
    @objc public func actualSize(_ sender: Any?) { zoom(0) }

    /// The engine keeps the zoom per site; the toast says where it is now.
    private func zoom(_ direction: Int) {
        guard let page = state.selectedTab?.page, let zoomPage = page.zoom else { return }
        zoomPage(direction)
        let percent = page.zoomPercent ?? 100
        let text = (Double(percent) / 100).formatted(.percent.locale(.chordUI))
        let symbol = direction > 0 ? "plus.magnifyingglass" : direction < 0 ? "minus.magnifyingglass" : "1.magnifyingglass"
        toast.show(text, detail: state.selectedTab?.url?.displayHost, symbol: symbol, in: rootView, over: pageArea, accent: state.activeSpace.accent)
    }

    @objc public func printPage(_ sender: Any?) {
        state.selectedTab?.page?.printPage?()
    }

    /// ⌥⌘U: the page's source, in a new tab.
    @objc public func viewSource(_ sender: Any?) {
        guard let url = state.selectedTab?.url, !url.absoluteString.hasPrefix("view-source:"),
              let source = URL(string: "view-source:" + url.absoluteString) else { return }
        state.openTab(url: source)
    }

    @objc public func toggleMuteTab(_ sender: Any?) {
        if let tab = state.selectedTab { state.toggleMute(tab) }
    }

    /// One of Chromium's internal pages (chord://settings…), in a new tab.
    private func openInternalPage(_ path: String) {
        guard let url = URL(string: "chrome://\(path)") else { return }
        state.openTab(url: url)
    }

    /// The selected page's site controls (permissions, quick actions), like Arc's.
    private func showSiteControls(from anchor: NSView) {
        guard let tab = state.selectedTab, let page = tab.page, let url = tab.url else { return }
        pendingHide?.cancel()
        if commandBar.isVisible { commandBar.dismiss() }
        siteControls.isGlass = settings.commandBarGlass
        siteControls.onCopy = { [weak self] in self?.copy(url) }
        siteControls.onOpen = { [weak self] url in self?.state.openTab(url: url) }
        siteControls.onDismiss = { [weak self] in
            self?.focusPage()
            self?.resumePermissionPrompt()
        }
        // A site's question waiting there steps aside, and comes back after.
        permissionPrompt.suspend()
        siteControlsTabID = tab.id
        siteControls.present(page: page, url: url, in: rootView, below: anchor)
    }

    @objc public func nextSpace(_ sender: Any?) {
        state.selectSpace(offset: 1)
    }

    @objc public func previousSpace(_ sender: Any?) {
        state.selectSpace(offset: -1)
    }

    /// ⌃1…⌃9; the menu item's tag is the number.
    @objc public func selectSpaceByNumber(_ sender: Any?) {
        guard let item = sender as? NSMenuItem else { return }
        state.selectSpace(number: item.tag)
    }

    @objc public func newSpace(_ sender: Any?) {
        let space = state.addSpace()
        promptRename(space)
    }

    @objc public func renameSpace(_ sender: Any?) {
        promptRename(state.activeSpace)
    }

    @objc public func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(state: state, settings: settings) { [weak self] in self?.importFromArc(nil) }
            settingsWindow?.window?.appearance = settings.appearance.nsAppearance
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    /// Arc's sidebar, then the logins, passwords and history of its profiles.
    @objc public func importFromArc(_ sender: Any?) {
        guard let window else { return }
        let sidebar: String
        do {
            let result = try ArcImport.load()
            let count = state.importFromArc(result)
            let favorites = result.favorites.values.reduce(0) { $0 + $1.count }
            sidebar = String(localized: "\(result.spaces.count) Spaces, \(result.folderCount) folders, \(favorites) favorites, \(count) tabs in all, with Arc's icons. A Space imported before is updated rather than duplicated.", bundle: .chordUI)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Couldn't import from Arc", bundle: .chordUI)
            alert.informativeText = (error as? ArcImport.Failure) == .notFound
                ? String(localized: "Arc's sidebar can't be found on this Mac.", bundle: .chordUI)
                : String(localized: "Arc's sidebar file couldn't be read.", bundle: .chordUI)
            alert.beginSheetModal(for: window)
            return
        }
        state.importArcData { [weak self] data in
            self?.showArcImport(title: String(localized: "Arc imported", bundle: .chordUI), sidebar: sidebar, data: data)
        }
    }

    /// Only the logins, passwords and history of Arc's profiles, into the profiles of
    /// the Spaces that came from them, without touching the sidebar.
    @objc public func importArcLogins(_ sender: Any?) {
        state.importArcData { [weak self] data in
            self?.showArcImport(title: String(localized: "Arc logins imported", bundle: .chordUI), sidebar: nil, data: data)
        }
    }

    private func showArcImport(title: String, sidebar: String?, data: BrowserState.ArcDataImport) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        var lines: [String] = sidebar.map { [$0] } ?? []
        if data.profiles == 0 {
            lines.append(String(localized: "No Space comes from an Arc profile: nothing else to bring over.", bundle: .chordUI))
        } else if data.keyDenied {
            alert.alertStyle = .warning
            lines.append(String(localized: "macOS didn't give access to Arc's key: logins and passwords stayed in Arc. \(data.pages) history pages imported.", bundle: .chordUI))
        } else {
            lines.append(String(localized: "\(data.cookies) login cookies, \(data.passwords) passwords and \(data.pages) history pages imported, each into the profile of its Spaces. What was already in Chord is kept.", bundle: .chordUI))
        }
        if data.extensions > 0 {
            lines.append(data.extensions == 1 ? String(localized: "1 extension installed from the Chrome Web Store.", bundle: .chordUI) : String(localized: "\(data.extensions) extensions installed from the Chrome Web Store.", bundle: .chordUI))
        }
        if data.siteStorage || data.extensions > 0 {
            lines.append(String(localized: "Site and extension data arrive at Chord's next launch.", bundle: .chordUI))
        }
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.beginSheetModal(for: window)
    }

    /// ⇧⌘J: the downloads panel, above the downloads button, or from the window's
    /// bottom-left corner while the sidebar is hidden.
    @objc public func showDownloads(_ sender: Any?) {
        if downloadsPopover.isShown {
            downloadsPopover.performClose(nil)
            return
        }
        if sidebarMode == .hidden {
            let corner = NSRect(x: 16, y: 8, width: 1, height: 1)
            downloadsPopover.show(relativeTo: corner, of: rootView, preferredEdge: .maxY)
        } else {
            let anchor = sidebar.downloadsAnchor
            downloadsPopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        }
    }

    private func makeDownloadsPopover() -> NSPopover {
        let panel = DownloadsPanelController(downloads: state.downloads)
        panel.onCancel = { [weak self] id in self?.state.cancelDownload(id) }
        panel.onDismissFailed = { [weak self] id in self?.state.downloads.remove(id: id) }
        let popover = NSPopover()
        popover.contentViewController = panel
        popover.behavior = .transient
        popover.animates = true
        return popover
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleEdgeless(_:)):
            menuItem.state = settings.edgeless ? .on : .off
            return true
        case #selector(toggleAddressBarPosition(_:)):
            menuItem.state = addressBarOnTop ? .on : .off
            return true
        case #selector(toggleSidebarVisibility(_:)):
            // The hidden ⌘B item keeps its own name in the shortcut settings.
            if menuItem.tag == 0 {
                menuItem.title = sidebarMode == .docked ? String(localized: "Hide Sidebar", bundle: .chordUI) : String(localized: "Show Sidebar", bundle: .chordUI)
            }
            return true
        case #selector(toggleSplitView(_:)):
            menuItem.title = state.isSplit ? String(localized: "Exit Split View", bundle: .chordUI) : String(localized: "Split View", bundle: .chordUI)
            return state.selectedTab != nil
        case #selector(togglePinTab(_:)):
            menuItem.title = state.selectedTab?.isPinned == true ? String(localized: "Unpin Tab", bundle: .chordUI) : String(localized: "Pin Tab", bundle: .chordUI)
            return state.selectedTab != nil
        case #selector(toggleFavoriteTab(_:)):
            menuItem.title = state.selectedTab?.isFavorite == true ? String(localized: "Remove from Favorites", bundle: .chordUI) : String(localized: "Add to Favorites", bundle: .chordUI)
            return state.selectedTab != nil
        case #selector(reopenClosedTab(_:)):
            return state.canReopenClosedTab
        case #selector(selectSpaceByNumber(_:)):
            return menuItem.tag <= state.spaces.count
        case #selector(importFromArc(_:)):
            return ArcImport.isAvailable
        case #selector(importArcLogins(_:)):
            return !state.isPrivate && state.spaces.contains { ArcImport.profileFolder(forChordProfile: $0.profileID) != nil }
        case #selector(goBack(_:)), #selector(goForward(_:)):
            // ⌘← / ⌘→ belong to the text being typed, in the command bar or a field.
            if menuItem.tag == 2, window?.firstResponder is NSText { return false }
            let page = state.selectedTab?.page
            return (menuItem.action == #selector(goBack(_:)) ? page?.canGoBack : page?.canGoForward) ?? false
        case #selector(togglePictureInPicture(_:)):
            return (state.selectedTab?.page as AnyObject?)?.responds(to: #selector(ChordWebPage.togglePictureInPicture)) ?? false
        case #selector(toggleDevTools(_:)):
            return (state.selectedTab?.page as AnyObject?)?.responds(to: #selector(ChordWebPage.toggleDevTools)) ?? false
        case #selector(stopLoading(_:)):
            return state.selectedTab?.page?.isLoading ?? false
        case #selector(reloadPage(_:)), #selector(reloadPageIgnoringCache(_:)), #selector(copyURL(_:)):
            return state.selectedTab != nil
        case #selector(showFindBar(_:)), #selector(findNext(_:)), #selector(findPrevious(_:)):
            return state.selectedTab?.page?.find != nil
        case #selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(actualSize(_:)):
            return state.selectedTab?.page?.zoom != nil
        case #selector(printPage(_:)):
            return state.selectedTab?.page?.printPage != nil
        case #selector(viewSource(_:)):
            guard let url = state.selectedTab?.url else { return false }
            return !url.absoluteString.hasPrefix("view-source:") && url.scheme != "chrome"
        case #selector(toggleMuteTab(_:)):
            let page = state.selectedTab?.page
            menuItem.title = page?.isMuted == true ? String(localized: "Unmute Tab", bundle: .chordUI) : String(localized: "Mute Tab", bundle: .chordUI)
            return page?.setMuted != nil
        case #selector(closeTab(_:)):
            return state.selectedTab != nil || commandBar.isVisible || peek.isVisible
        default:
            return true
        }
    }

    // MARK: - Window

    public func windowWillClose(_ notification: Notification) {
        trafficLightObservers.forEach(NotificationCenter.default.removeObserver)
        trafficLightObservers = []
        state.saveNow()
        state.closeWindow(selection)
        onClose?(self)
    }
}

// MARK: - Sidebar

extension BrowserWindowController: SidebarDelegate {
    func sidebarGoBack() { goBack(nil) }
    func sidebarGoForward() { goForward(nil) }
    func sidebarReload() { reloadOrStop() }
    func sidebarToggle() { toggleSidebarVisibility(nil) }
    func sidebarAddressClicked() { openLocation(nil) }
    func sidebarNewTab() { newTab(nil) }

    func sidebarSelect(_ tab: Tab) {
        let interval = Perf.begin("tab.select")
        state.select(tab)
        DispatchQueue.main.async { interval.end() }
    }

    func sidebarClose(_ tab: Tab) { state.close(tab) }
    func sidebarToggleMute(_ tab: Tab) { state.toggleMute(tab) }
    func sidebarTogglePin(_ tab: Tab) { state.togglePin(tab) }
    func sidebarToggleFavorite(_ tab: Tab) { state.toggleFavorite(tab) }
    func sidebarSplit(_ tab: Tab) { state.addToSplit(tab) }
    func sidebarRemoveFromSplit(_ tab: Tab) { state.removeFromSplit(tab) }
    func sidebarCopyURL(_ tab: Tab) { copy(tab.url) }
    func sidebarCopyAddress() { copyURL(nil) }
    func sidebarShowSiteControls(from anchor: NSView) { showSiteControls(from: anchor) }
    func sidebarTab(withID id: UUID) -> Tab? { state.tab(withID: id) }
    // Drops and swipes can reach a window that is not the key one: they act with its
    // own selection.
    func sidebarMove(_ tab: Tab, to destination: TabDestination) {
        state.withWindow(selection) { state.move(tab, to: destination) }
    }
    func sidebarMove(_ tab: Tab, toSpace space: Space) {
        state.withWindow(selection) { state.move(tab, to: .today(0), in: space) }
    }
    func sidebarMove(_ folder: Folder, into parent: Folder?, at index: Int) {
        state.withWindow(selection) { state.move(folder, into: parent, at: index) }
    }

    func sidebarOpen(_ urls: [URL], at destination: TabDestination) {
        state.withWindow(selection) { openDropped(urls, at: destination) }
    }

    private func openDropped(_ urls: [URL], at destination: TabDestination) {
        for (offset, url) in urls.enumerated() {
            switch destination {
            case .favorites(let index): state.insertTab(url: url, at: .favorites(index + offset))
            case .pinned(let folder, let index): state.insertTab(url: url, at: .pinned(folder, index + offset))
            case .today(let index): state.insertTab(url: url, at: .today(index + offset))
            }
        }
    }

    func sidebarNewFolder(with tab: Tab?) {
        promptRename(state.newFolder(with: tab))
    }

    func sidebarRename(_ folder: Folder) { promptRename(folder) }
    func sidebarUngroup(_ folder: Folder) { state.ungroup(folder) }
    func sidebarDelete(_ folder: Folder) { confirmDelete(folder) }
    func sidebarSetExpanded(_ folder: Folder, _ expanded: Bool) { state.setExpanded(folder, expanded) }

    func sidebarSelectSpace(_ space: Space) { state.selectSpace(space) }
    func sidebarAddSpace() { newSpace(nil) }
    func sidebarRename(_ space: Space) { promptRename(space) }
    func sidebarSetColor(_ space: Space, hex: String) { state.setColor(space, hex: hex) }
    func sidebarDelete(_ space: Space) { confirmDelete(space) }
    /// The window's tint follows the swipe from one Space's colour to the other's.
    func sidebarSwipeProgress(toward space: Space?, fraction: CGFloat) {
        guard let space else { return }
        setTint(state.activeSpace.color.blended(withFraction: fraction, of: space.color) ?? space.color)
    }

    func sidebarSwipeWillEnd(on space: Space?, duration: TimeInterval) {
        setTint((space ?? state.activeSpace).color, duration: duration)
    }

    func sidebarSwipeEnded(on space: Space?) {
        guard let space else { return }
        isEndingSwipe = true
        state.withWindow(selection) { state.selectSpace(space) }
        isEndingSwipe = false
    }

    func sidebarResize(to width: CGFloat, finished: Bool) {
        sidebarWidth.constant = width
        if finished { settings.sidebarWidth = width }
    }

    func sidebarShowDownloads() { showDownloads(nil) }
    func sidebarMouseEntered() { pendingHide?.cancel() }
    func sidebarMouseExited() { scheduleHide() }
}
