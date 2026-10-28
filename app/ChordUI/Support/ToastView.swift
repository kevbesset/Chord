import AppKit

/// A short confirmation, like Arc's: a glass pill that rises at the bottom of the page
/// area, stays a moment, then fades. Showing it again restarts it with the new text.
/// At the top, it is a notice the page cannot cover (how to leave full screen).
final class ToastView: NSView {
    enum Edge { case top, bottom }

    private let shadowHost = ShadowHostView()
    private let glass = NSVisualEffectView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    /// What the confirmation is about (the copied address's site), quieter.
    private let detailLabel = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?
    private weak var installedHost: NSView?
    private var bottomConstraint: NSLayoutConstraint?
    private let edge: Edge
    private let visibleDuration: TimeInterval

    static let height: CGFloat = 34
    private static let restingInset: CGFloat = 24

    init(edge: Edge = .bottom, visibleDuration: TimeInterval = 1.6) {
        self.edge = edge
        self.visibleDuration = visibleDuration
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        alphaValue = 0
        isHidden = true

        shadowHost.cornerRadius = Self.height / 2
        shadowHost.configureShadow(opacity: 0.18, radius: 14, offsetY: -4)
        glass.material = .popover
        glass.blendingMode = .withinWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = Self.height / 2
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor.separatorColor.cgColor

        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        icon.wantsLayer = true
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        let stack = NSStackView(views: [icon, label, detailLabel])
        stack.orientation = .horizontal
        stack.spacing = 7

        for view in [shadowHost, glass, stack] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(shadowHost)
        shadowHost.addSubview(glass)
        glass.addSubview(stack)
        NSLayoutConstraint.activate([
            shadowHost.topAnchor.constraint(equalTo: topAnchor),
            shadowHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            shadowHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            shadowHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.topAnchor.constraint(equalTo: shadowHost.topAnchor),
            glass.leadingAnchor.constraint(equalTo: shadowHost.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: shadowHost.trailingAnchor),
            glass.bottomAnchor.constraint(equalTo: shadowHost.bottomAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
            stack.leadingAnchor.constraint(equalTo: glass.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: glass.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: glass.centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Never in the way of the page under it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        glass.layer?.borderColor = NSColor.separatorColor.cgColor
    }

    /// Shows `text` centred at the bottom of `area`, in `host` so that it floats above the
    /// page (web views draw over their siblings, hence the z position).
    func show(_ text: String, detail: String? = nil, symbol: String, in host: NSView, over area: NSView, accent: NSColor) {
        if installedHost !== host {
            removeFromSuperview()
            host.addSubview(self)
            // Above the command bar too, which may be added to `host` later.
            layer?.zPosition = 200
            let bottom = edge == .bottom
                ? bottomAnchor.constraint(equalTo: area.bottomAnchor, constant: -Self.restingInset)
                : topAnchor.constraint(equalTo: area.topAnchor, constant: Self.restingInset)
            NSLayoutConstraint.activate([centerXAnchor.constraint(equalTo: area.centerXAnchor), bottom])
            bottomConstraint = bottom
            installedHost = host
        }
        label.stringValue = text
        detailLabel.stringValue = detail ?? ""
        detailLabel.isHidden = detail == nil
        icon.image = Theme.symbol(symbol, size: 14, weight: .semibold)
        icon.contentTintColor = accent
        popIcon()
        setAccessibilityLabel(text)
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])

        let wasVisible = !isHidden && alphaValue > 0
        isHidden = false
        if !wasVisible {
            // Rises a few points while it fades in.
            bottomConstraint?.constant = restingConstant + (edge == .bottom ? 8 : -8)
            host.layoutSubtreeIfNeeded()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            animator().alphaValue = 1
            bottomConstraint?.animator().constant = restingConstant
            host.layoutSubtreeIfNeeded()
        }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visibleDuration, execute: work)
    }

    /// Where the pill rests, from the area's edge.
    private var restingConstant: CGFloat { edge == .bottom ? -Self.restingInset : Self.restingInset }

    /// The icon arrives with a small spring, so that a second confirmation still reads
    /// as new.
    private func popIcon() {
        guard let layer = icon.layer else { return }
        let center = CGPoint(x: icon.bounds.midX, y: icon.bounds.midY)
        var shrunk = CATransform3DMakeTranslation(center.x, center.y, 0)
        shrunk = CATransform3DScale(shrunk, 0.5, 0.5, 1)
        shrunk = CATransform3DTranslate(shrunk, -center.x, -center.y, 0)
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = shrunk
        spring.toValue = CATransform3DIdentity
        spring.stiffness = 280
        spring.damping = 13
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "pop")
    }

    private func hide() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.alphaValue == 0 else { return }
            self.isHidden = true
        })
    }
}
