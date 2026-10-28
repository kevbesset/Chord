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

    let rootView = NSVisualEffectView()
    let frostView = GlassFrostView()
    let tintView = SpaceTintView()
    let sidebar = SidebarView()
    let pageArea = PageAreaView()
    let edgeHover = EdgeHoverView()
    lazy var commandBar = CommandBarController(state: state, settings: settings)
    let siteControls = SiteControlsController()
    var siteControlsTabID: UUID?
    let permissionPrompt = PermissionPromptController()
    let extensionPopup = ExtensionPopupController()
    let toast = ToastView()
    /// The page searched with ⌘F while the find bar is up.
    weak var findPage: ChordWebPage?
    /// True while a swipe hands its Space to the state, which needs no slide of its own.
    var isEndingSwipe = false
    lazy var peek = makePeek()
    var settingsWindow: SettingsWindowController?
    var littleWindows: [LittleWindowController] = []
    lazy var downloadsPopover = makeDownloadsPopover()
    lazy var archivePopover = makeArchivePopover()

    var sidebarWidth: NSLayoutConstraint!
    var sidebarLeading: NSLayoutConstraint!
    var sidebarTop: NSLayoutConstraint!
    var sidebarBottom: NSLayoutConstraint!
    var cardLeadingDocked: NSLayoutConstraint!
    var cardLeadingFree: NSLayoutConstraint!
    var cardTop: NSLayoutConstraint!
    var cardTrailing: NSLayoutConstraint!
    var cardBottom: NSLayoutConstraint!

    var sidebarMode = SidebarMode.docked
    /// The tab whose page is in full screen (a video), shown alone; and the sidebar's
    /// mode to go back to when it leaves full screen.
    var fullscreenTab: Tab?
    /// The first launch's welcome, while it shows.
    var welcomeView: WelcomeView?
    /// ⌘Q's question, while it is on screen.
    var quitConfirmation: QuitConfirmationView?
    var sidebarModeBeforeFullscreen: SidebarMode?
    var pendingReveal: DispatchWorkItem?
    var pendingHide: DispatchWorkItem?
    var lastSpaceIndex = 0
    /// The pages this window showed last, to know which ones just left the screen.
    let shownPages = NSHashTable<AnyObject>.weakObjects()
    /// The address bar's place as last laid out, to move it only when the Space's
    /// profile wants another one.
    var shownAddressBarOnTop: Bool?
    /// One per pane, for the pages another window shows.
    var elsewhereViews: [PageElsewhereView] = []
    var cancellables = Set<AnyCancellable>()
    /// The title bar's views being watched, and a placing waiting for the next turn.
    var trafficLightObservers: [NSObjectProtocol] = []
    var trafficLightsPending = false

    static let frameName = "ChordMainWindow"

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
        } else if PerfReplay.isActive {
            // The latency gate's replay drives the window itself.
        } else if !settings.welcomeShown, state.isPristine {
            // First launch: the welcome, which offers Arc's import among the rest.
            DispatchQueue.main.async { [weak self] in self?.showWelcome() }
        } else if !settings.arcImportOffered, state.isPristine, ArcImport.isAvailable {
            // First launch with Arc on this Mac: offer to bring its sidebar over.
            DispatchQueue.main.async { [weak self] in self?.offerArcImport() }
        } else if state.activeSpace.allTabs.isEmpty && state.favorites.isEmpty {
            // An empty Space: go straight to the command bar.
            DispatchQueue.main.async { [weak self] in self?.newTab(nil) }
        }
    }

    // MARK: - Layout

    func buildLayout() {
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

    func applyAppearanceSettings(animated: Bool) {
        // A page in full screen fills the window: no margins, corners or toolbar.
        let edgeless = settings.edgeless || fullscreenTab != nil
        let inset = edgeless ? 0 : Theme.contentInset
        cardTop.constant = inset
        cardTrailing.constant = inset
        cardBottom.constant = inset
        cardLeadingFree.constant = inset
        sidebarWidth.constant = settings.sidebarWidth
        if sidebarMode == .hidden { sidebarLeading.constant = -(settings.sidebarWidth + 32) }
        let onTop = addressBarOnTop
        shownAddressBarOnTop = onTop
        pageArea.setStyle(edgeless: edgeless, toolbarOnTop: onTop && fullscreenTab == nil, accent: state.activeSpace.accent)
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

    func layoutChanges(animated: Bool) {
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
    func setTint(_ color: NSColor, duration: TimeInterval = 0) {
        tintView.setColor(color, duration: duration)
        sidebar.setTint(color, duration: duration)
    }

    func updateTint(animated: Bool) {
        setTint(state.activeSpace.color, duration: animated ? Theme.motionDuration : 0)
        pageArea.setStyle(edgeless: settings.edgeless || fullscreenTab != nil, toolbarOnTop: addressBarOnTop && fullscreenTab == nil,
                          accent: state.activeSpace.accent)
    }

    /// Where the address bar sits in this window: the choice of its Space's profile, else
    /// the default of the settings.
    var addressBarOnTop: Bool {
        state.addressBarOnTop(for: state.activeSpace) ?? settings.addressBarOnTop
    }

    /// Moves the address bar when the Space now shown, or its profile, wants it elsewhere.
    func updateAddressBarPosition(animated: Bool) {
        let onTop = addressBarOnTop
        guard onTop != shownAddressBarOnTop else { return }
        shownAddressBarOnTop = onTop
        pageArea.setStyle(edgeless: settings.edgeless || fullscreenTab != nil, toolbarOnTop: onTop && fullscreenTab == nil,
                          accent: state.activeSpace.accent)
        sidebar.setAddressBarOnTop(onTop)
        layoutChanges(animated: animated)
        reanchorPermissionPrompt()
    }

    // MARK: - Sidebar modes

    func setSidebarMode(_ mode: SidebarMode, animated: Bool) {
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
    func positionTrafficLights() {
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
    func schedulePositionTrafficLights() {
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

    func setTrafficLightsHidden(_ hidden: Bool) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    /// Waits a little so that brushing past the edge does not open the sidebar.
    func scheduleReveal() {
        guard sidebarMode == .hidden, fullscreenTab == nil else { return }
        pendingReveal?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.sidebarMode == .hidden else { return }
            self.setSidebarMode(.floating, animated: true)
        }
        pendingReveal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func scheduleHide() {
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

    func bindState() {
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
        // A new version of Chord, downloaded: its button above the Spaces.
        NotificationCenter.default.publisher(for: Updates.readyNotification)
            .sink { [weak self] _ in self?.sidebar.updateAvailableVersion(Updates.shared.readyVersion) }
            .store(in: &cancellables)
        sidebar.updateAvailableVersion(Updates.shared.readyVersion)
        commandBar.actionsProvider = { [weak self] in self?.commandActions() ?? [] }
        commandBar.onDismiss = { [weak self] in self?.focusPage() }
        permissionPrompt.onClose = { [weak self] in self?.permissionPromptClosed() }
        let extensionActions = makeExtensionActions()
        sidebar.extensionActions = extensionActions
        pageArea.toolbar.extensionActions = extensionActions
        siteControls.extensionActions = extensionActions
        extensionPopup.onClose = { [weak self] in self?.extensionPopupClosed() }
    }

    func handle(_ key: ChordSettings.Key) {
        switch key {
        case .sidebarWidth:
            sidebarWidth.constant = settings.sidebarWidth
        case .shortcuts:
            MainMenu.apply(settings.shortcutOverrides, to: NSApp.mainMenu)
        case .searchTemplate:
            break
        case .pictureInPicture, .quit:
            break
        case .archive:
            state.archiveIdleTabs()
        case .edgeless, .appearance, .addressBar, .commandBar:
            applyAppearanceSettings(animated: key == .edgeless || key == .addressBar)
        }
    }

    func handle(_ change: StateChange) {
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
            sidebar.updateMedia(state: state)
            if (tab.page?.isFullscreen == true) != (fullscreenTab === tab) {
                showSelectedPage(focus: false)
            }
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
        case .archive:
            if archivePopover.isShown { archivePanel?.reload() }
        }
    }

    func refreshAll() {
        updateTint(animated: false)
        updateAddressBarPosition(animated: false)
        sidebar.update(state: state)
        showSelectedPage(focus: false)
    }

    func showSelectedPage(focus: Bool) {
        updatePageFullscreen()
        // A page in full screen is shown alone, even from a split.
        let tabs = fullscreenTab.map { [$0] } ?? state.visibleTabs
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

    func elsewhereView(at index: Int) -> PageElsewhereView {
        while elsewhereViews.count <= index { elsewhereViews.append(PageElsewhereView()) }
        return elsewhereViews[index]
    }

    /// A page moved between windows: this window takes back a page of its selection
    /// that is free again, or says where one went.
    func pagesDidMove() {
        guard pageArea.isMissingPage else { return }
        state.withWindow(selection) { showSelectedPage(focus: false) }
    }

    /// Like Arc: a video playing in a page that leaves the screen carries on in a
    /// picture-in-picture window, and a page back on screen takes its video back.
    func updatePictureInPicture(showing pages: [ChordWebPage]) {
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

    func focusPage() {
        if let view = state.selectedTab?.page?.view {
            window?.makeFirstResponder(view)
        }
    }

    /// Every way of copying an address ends here, so that each one shows the toast.
    func copy(_ url: URL?) {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        toast.show(String(localized: "URL copied", bundle: .chordUI), detail: url.displayHost, symbol: "checkmark.circle.fill", in: rootView, over: pageArea, accent: state.activeSpace.accent)
    }

    func handle(_ action: PageBarAction) {
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

    func moreMenu() -> NSMenu {
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

    // MARK: - Window

    public func windowWillClose(_ notification: Notification) {
        trafficLightObservers.forEach(NotificationCenter.default.removeObserver)
        trafficLightObservers = []
        state.saveNow()
        state.closeWindow(selection)
        onClose?(self)
    }
}
