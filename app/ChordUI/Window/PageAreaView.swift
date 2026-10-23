import AppKit

/// Where pages are shown: one card, or two to four side by side in a split view.
///
/// Panes are laid out by hand from width fractions, so that dragging a divider costs a
/// single frame pass and stays at 120 frames per second.
final class PageAreaView: NSView {
    var onAction: ((PageBarAction) -> Void)? {
        didSet { toolbar.onAction = onAction }
    }
    var moreMenu: (() -> NSMenu)? {
        didSet { toolbar.moreMenu = moreMenu }
    }

    let toolbar = PageToolbarView()
    private var panes: [PaneView] = []
    private var dividers: [SplitDividerView] = []
    private var fractions: [CGFloat] = [1]
    private var tabs: [Tab] = []
    private var activeID: UUID?
    private var edgeless = false
    private var toolbarOnTop = false
    private var accent = NSColor.controlAccentColor
    private var clickMonitor: Any?

    static let minimumPaneWidth: CGFloat = 240

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        panes = [makePane()]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    // MARK: - Content

    /// Shows the given tabs with their page views. An empty list shows the empty state.
    func show(tabs: [Tab], views: [NSView], activeID: UUID?) {
        let count = max(1, tabs.count)
        if count != panes.count || tabs.map(\.id) != self.tabs.map(\.id) {
            if count != fractions.count { fractions = Array(repeating: 1 / CGFloat(count), count: count) }
        }
        self.tabs = tabs
        self.activeID = activeID

        while panes.count < count { panes.append(makePane()) }
        while panes.count > count { panes.removeLast().removeFromSuperview() }
        while dividers.count < count - 1 { dividers.append(makeDivider()) }
        while dividers.count > count - 1 { dividers.removeLast().removeFromSuperview() }

        let split = tabs.count > 1
        for (index, pane) in panes.enumerated() {
            let tab = tabs.indices.contains(index) ? tabs[index] : nil
            pane.card.show(views.indices.contains(index) ? views[index] : nil)
            if split, let tab {
                pane.header.update(tab: tab)
                pane.card.setAccessory(pane.header)
            } else {
                pane.card.setAccessory(toolbarOnTop ? toolbar : nil)
            }
            pane.isActivePane = split && tab?.id == activeID
        }
        toolbar.update(tab: tabs.first { $0.id == activeID } ?? tabs.first)
        updateClickMonitor()
        needsLayout = true
    }

    /// The URL or navigation state of a shown tab changed.
    func refresh(tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        if tabs.count > 1 { panes[index].header.update(tab: tab) }
        if tab.id == activeID || tabs.count == 1 { toolbar.update(tab: tab) }
    }

    func setStyle(edgeless: Bool, toolbarOnTop: Bool, accent: NSColor) {
        self.edgeless = edgeless
        self.toolbarOnTop = toolbarOnTop
        self.accent = accent
        for pane in panes { pane.setStyle(edgeless: edgeless, accent: accent) }
        if tabs.count <= 1 { panes.first?.card.setAccessory(toolbarOnTop ? toolbar : nil) }
        needsLayout = true
    }

    // MARK: - Layout

    private var gap: CGFloat { edgeless ? 2 : 8 }

    override func layout() {
        super.layout()
        let count = panes.count
        let gaps = gap * CGFloat(count - 1)
        let available = max(0, bounds.width - gaps)
        var x: CGFloat = 0
        for (index, pane) in panes.enumerated() {
            let width = index == count - 1 ? bounds.width - x : (available * fractions[index]).rounded()
            pane.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
            x += width
            if index < dividers.count {
                dividers[index].frame = NSRect(x: x, y: 0, width: gap, height: bounds.height)
                x += gap
            }
        }
    }

    private func makePane() -> PaneView {
        let pane = PaneView()
        pane.setStyle(edgeless: edgeless, accent: accent)
        pane.header.onAction = { [weak self] action in self?.onAction?(action) }
        addSubview(pane)
        return pane
    }

    private func makeDivider() -> SplitDividerView {
        let divider = SplitDividerView()
        divider.onDrag = { [weak self, weak divider] delta in
            guard let self, let divider, let index = self.dividers.firstIndex(where: { $0 === divider }) else { return }
            self.resize(at: index, by: delta)
        }
        addSubview(divider)
        return divider
    }

    /// Moves the divider after pane `index`, keeping both neighbours above their minimum.
    private func resize(at index: Int, by delta: CGFloat) {
        let available = bounds.width - gap * CGFloat(panes.count - 1)
        guard available > 0 else { return }
        let minimum = Self.minimumPaneWidth / available
        let change = delta / available
        let left = fractions[index] + change
        let right = fractions[index + 1] - change
        guard left >= minimum, right >= minimum else { return }
        fractions[index] = left
        fractions[index + 1] = right
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    /// In a split, clicking inside a page makes its pane active. The page keeps the click.
    private func updateClickMonitor() {
        if tabs.count > 1, clickMonitor == nil {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.activatePane(at: event)
                return event
            }
        } else if tabs.count <= 1, let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    private func activatePane(at event: NSEvent) {
        guard event.window === window, tabs.count > 1 else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let index = panes.firstIndex(where: { $0.frame.contains(point) }), tabs.indices.contains(index),
              tabs[index].id != activeID else { return }
        // Only the page itself: the sidebar or the command bar may sit above the area.
        guard let hit = window?.contentView?.hitTest(event.locationInWindow), hit.isDescendant(of: panes[index]) else { return }
        onAction?(.activate(tabs[index]))
    }
}

/// One pane: a shadowed card, ringed with the Space colour when it is the active pane.
final class PaneView: NSView {
    let host = ShadowHostView()
    let card = ContentCardView()
    let header = PaneHeaderView()
    private let ring = CALayer()
    private var edgeless = false

    var isActivePane = false {
        didSet { ring.isHidden = !isActivePane }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        ring.borderWidth = 2
        ring.isHidden = true
        layer?.addSublayer(ring)
        host.translatesAutoresizingMaskIntoConstraints = false
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        host.addSubview(card)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: topAnchor),
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.topAnchor.constraint(equalTo: host.topAnchor),
            card.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }

    func setStyle(edgeless: Bool, accent: NSColor) {
        self.edgeless = edgeless
        card.setEdgeless(edgeless)
        host.cornerRadius = edgeless ? 0 : Theme.cardRadius
        host.showsShadow = !edgeless
        ring.borderColor = accent.withAlphaComponent(0.45).cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let inset: CGFloat = edgeless ? 0 : -2
        ring.frame = bounds.insetBy(dx: inset, dy: inset)
        ring.cornerRadius = edgeless ? 0 : Theme.cardRadius + 2
        CATransaction.commit()
    }
}

/// The gap between two panes, with a small grip. Dragging it resizes both panes.
final class SplitDividerView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private let grip = CALayer()
    private var lastX: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        grip.cornerRadius = 2
        layer?.addSublayer(grip)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("Redimensionner les volets")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        grip.frame = NSRect(x: bounds.midX - 2, y: bounds.midY - 18, width: 4, height: 36)
        grip.backgroundColor = (isDarkAppearance ? NSColor.white.withAlphaComponent(0.22) : NSColor.black.withAlphaComponent(0.18)).cgColor
        grip.isHidden = bounds.width < 4
        CATransaction.commit()
    }

    override func resetCursorRects() {
        addCursorRect(bounds.insetBy(dx: -3, dy: 0), cursor: .resizeLeftRight)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // A wider grab area than the gap, so that edgeless splits stay easy to resize.
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        return bounds.insetBy(dx: -3, dy: 0).contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        lastX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        let x = event.locationInWindow.x
        onDrag?(x - lastX)
        lastX = x
    }
}
