import AppKit

/// A short confirmation, like Arc's: a glass pill that rises at the bottom of the page
/// area, stays a moment, then fades. Showing it again restarts it with the new text.
final class ToastView: NSView {
    private let shadowHost = ShadowHostView()
    private let glass = NSVisualEffectView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?
    private weak var installedHost: NSView?
    private var bottomConstraint: NSLayoutConstraint?

    static let height: CGFloat = 34
    private static let restingInset: CGFloat = 24
    private static let visibleDuration: TimeInterval = 1.6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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
        let stack = NSStackView(views: [icon, label])
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
    func show(_ text: String, symbol: String, in host: NSView, over area: NSView, accent: NSColor) {
        if installedHost !== host {
            removeFromSuperview()
            host.addSubview(self)
            // Above the command bar too, which may be added to `host` later.
            layer?.zPosition = 200
            let bottom = bottomAnchor.constraint(equalTo: area.bottomAnchor, constant: -Self.restingInset)
            NSLayoutConstraint.activate([centerXAnchor.constraint(equalTo: area.centerXAnchor), bottom])
            bottomConstraint = bottom
            installedHost = host
        }
        label.stringValue = text
        icon.image = Theme.symbol(symbol, size: 14, weight: .semibold)
        icon.contentTintColor = accent
        setAccessibilityLabel(text)
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])

        let wasVisible = !isHidden && alphaValue > 0
        isHidden = false
        if !wasVisible {
            // Rises a few points while it fades in.
            bottomConstraint?.constant = -Self.restingInset + 8
            host.layoutSubtreeIfNeeded()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            animator().alphaValue = 1
            bottomConstraint?.animator().constant = -Self.restingInset
            host.layoutSubtreeIfNeeded()
        }

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration, execute: work)
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
