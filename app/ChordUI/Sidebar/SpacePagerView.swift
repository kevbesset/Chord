import AppKit

/// One Space's content in the sidebar: its favorites, then its tabs.
final class SpacePageView: NSView {
    let favorites = FavoritesView()
    let tabList = TabListView()
    private var listTop: NSLayoutConstraint!

    /// Room above the favorites so that the pager's clipping spares their shadows.
    static let topInset: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for view in [favorites, tabList] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        listTop = tabList.topAnchor.constraint(equalTo: favorites.bottomAnchor)
        NSLayoutConstraint.activate([
            favorites.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset),
            favorites.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            favorites.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            listTop,
            tabList.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            tabList.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            tabList.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }

    /// Empty areas still move the window, like the rest of the sidebar.
    override func mouseDown(with event: NSEvent) {
        window?.handleChromeMouseDown(event)
    }

    func update(space: Space, spaces: [Space], favorites tabs: [Tab], selectedID: UUID?, splitIDs: Set<UUID>) {
        favorites.update(favorites: tabs, selectedID: selectedID, splitIDs: splitIDs, accent: space.accent)
        listTop.constant = tabs.isEmpty ? 0 : 12
        tabList.update(space: space, spaces: spaces, selectedID: selectedID, splitIDs: splitIDs)
    }
}

/// The active Space's page and, during a two-finger swipe, the next or previous one beside
/// it. Like Arc, the sidebar moves with the fingers, as a horizontal scroll view would,
/// and the release finishes or undoes the move at the speed of the swipe.
final class SpacePagerView: NSView {
    let current = SpacePageView()
    /// The Space coming in, shown only during a swipe.
    let neighbor = SpacePageView()
    /// How far the current page has moved: negative when it leaves to the left, which
    /// brings the next Space in from the right.
    private(set) var offset: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        neighbor.isHidden = true
        addSubview(current)
        addSubview(neighbor)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        place()
    }

    private func place() {
        current.frame = bounds.offsetBy(dx: offset, dy: 0)
        neighbor.frame = neighborFrame(for: offset)
    }

    private func neighborFrame(for offset: CGFloat) -> NSRect {
        bounds.offsetBy(dx: offset + (offset <= 0 ? bounds.width : -bounds.width), dy: 0)
    }

    /// Follows the fingers, without animation.
    func setOffset(_ offset: CGFloat) {
        self.offset = offset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        place()
        CATransaction.commit()
    }

    /// Glides to `target` (0, or a full width either way) in `duration`, then calls back.
    func animateOffset(to target: CGFloat, duration: TimeInterval, completion: @escaping () -> Void) {
        let neighborTarget = neighborFrame(for: offset).offsetBy(dx: target - offset, dy: 0)
        offset = target
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = Theme.motionCurve
            current.animator().frame = bounds.offsetBy(dx: target, dy: 0)
            neighbor.animator().frame = neighborTarget
        }, completionHandler: completion)
    }

    /// Back to the active Space alone.
    func reset() {
        neighbor.isHidden = true
        setOffset(0)
    }

    /// Without a swipe (⌃1…⌃9, ⌥⌘← →): the new Space pushes the old one aside.
    func slide(forward: Bool) {
        let transition = CATransition()
        transition.type = .push
        transition.subtype = forward ? .fromRight : .fromLeft
        transition.duration = 0.22
        transition.timingFunction = Theme.motionCurve
        current.layer?.add(transition, forKey: "spaceSwitch")
    }
}
