import AppKit

/// The site's controls, from the button in the address field, like Arc's: the site and
/// its connection, quick actions, the few permissions that matter for this site (each a
/// switch) and a way to all of them. A card laid over the window, like the command bar;
/// the engine keeps the permissions.
final class SiteControlsController: NSObject {
    struct Permission {
        let id: String
        let title: String
        let symbol: String
    }

    /// In the order they show. Notifications always show; the others once they were
    /// chosen for the site.
    static let permissions = [
        Permission(id: "notifications", title: "Notifications", symbol: "bell.fill"),
        Permission(id: "geolocation", title: "Position", symbol: "location.fill"),
        Permission(id: "camera", title: "Caméra", symbol: "video.fill"),
        Permission(id: "microphone", title: "Micro", symbol: "mic.fill"),
        Permission(id: "autoPictureInPicture", title: "Picture-in-picture automatique", symbol: "pip.fill"),
        Permission(id: "popups", title: "Pop-ups et redirections", symbol: "macwindow.on.rectangle"),
        Permission(id: "sound", title: "Son", symbol: "speaker.wave.2.fill"),
    ]
    private static let maxPermissions = 4
    private static let width: CGFloat = 300

    var onCopy: (() -> Void)?
    /// Opens a page in a new tab (the site's full settings).
    var onOpen: ((URL) -> Void)?
    var onDismiss: (() -> Void)?
    var isGlass = true
    private(set) var isVisible = false

    private let scrim = ScrimView()
    private let panelHost = ShadowHostView()
    private let panel = NSVisualEffectView()
    private let content = KeyCatcherView()
    private var page: ChordWebPage?
    private var url: URL?

    /// Shows the controls of `page` in `host`, under `anchor` (the button that opened them).
    func present(page: ChordWebPage, url: URL, in host: NSView, below anchor: NSView) {
        let interval = Perf.begin("sitecontrols.open")
        defer { DispatchQueue.main.async { interval.end() } }
        self.page = page
        self.url = url
        install(in: host)
        rebuild()

        content.layoutSubtreeIfNeeded()
        let size = NSSize(width: Self.width, height: content.fittingSize.height)
        let rect = anchor.convert(anchor.bounds, to: host)
        let x = min(max(8, rect.minX - 12), host.bounds.width - size.width - 8)
        let gap: CGFloat = 6
        let y = host.isFlipped ? rect.maxY + gap : rect.minY - gap - size.height
        panelHost.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        panel.material = isGlass ? .popover : .windowBackground

        scrim.isHidden = false
        panelHost.isHidden = false
        isVisible = true
        host.window?.makeFirstResponder(content)
    }

    func dismiss() {
        guard isVisible else { return }
        isVisible = false
        scrim.isHidden = true
        panelHost.isHidden = true
        page = nil
        onDismiss?()
    }

    // MARK: - Building

    private func install(in host: NSView) {
        guard scrim.superview !== host else {
            // Above whatever was added since (the command bar, a Peek).
            host.addSubview(scrim)
            host.addSubview(panelHost)
            return
        }
        scrim.dims = false
        scrim.onClick = { [weak self] in self?.dismiss() }
        scrim.frame = host.bounds
        scrim.autoresizingMask = [.width, .height]

        panelHost.cornerRadius = 14
        panelHost.configureShadow(opacity: 0.2, radius: 24, offsetY: -8)
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 14
        panel.layer?.masksToBounds = true
        panel.layer?.borderWidth = 0.5
        panel.layer?.borderColor = NSColor.separatorColor.cgColor
        panel.frame = panelHost.bounds
        panel.autoresizingMask = [.width, .height]
        content.frame = panel.bounds
        content.autoresizingMask = [.width, .height]
        content.onCancel = { [weak self] in self?.dismiss() }
        panelHost.addSubview(panel)
        panel.addSubview(content)
        host.addSubview(scrim)
        host.addSubview(panelHost)
    }

    private func rebuild() {
        guard let page, let url else { return }
        content.subviews.forEach { $0.removeFromSuperview() }

        var sections: [NSView] = [header(for: url), actions()]
        let shown = Self.shownPermissions(of: page)
        if !shown.isEmpty {
            sections.append(Rule())
            sections += shown.map { permission, state in
                PermissionRow(permission: permission, state: state) { [weak self] allowed in
                    self?.page?.setPermission?(permission.id, state: allowed ? "allow" : "block")
                    self?.rebuild()
                }
            }
        }
        if let settingsURL = Self.siteSettingsURL(for: url) {
            sections.append(Rule())
            sections.append(LinkRow(symbol: "gearshape", title: "Réglages du site") { [weak self] in
                self?.dismiss()
                self?.onOpen?(settingsURL)
            })
        }

        // Each section spans the card; the rules get their own insets.
        var previous: NSView?
        for view in sections {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
            let inset: CGFloat = view is Rule ? 14 : 8
            var constraints = [
                view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
                view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            ]
            if let previous {
                constraints.append(view.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: view is Rule || previous is Rule ? 6 : 2))
            } else {
                constraints.append(view.topAnchor.constraint(equalTo: content.topAnchor, constant: 8))
            }
            NSLayoutConstraint.activate(constraints)
            previous = view
        }
        // At most: the card's height comes from its content.
        previous?.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -8).isActive = true
    }

    /// Notifications, then what was chosen for the site, a few at most.
    private static func shownPermissions(of page: ChordWebPage) -> [(Permission, String)] {
        var shown: [(Permission, String)] = []
        for permission in permissions where shown.count < maxPermissions {
            guard let state = page.permissionState?(permission.id) else { continue }
            if permission.id == "notifications" || page.permissionIsSiteSpecific?(permission.id) == true {
                shown.append((permission, state))
            }
        }
        return shown
    }

    /// Chromium's page with every permission of the site.
    private static func siteSettingsURL(for url: URL) -> URL? {
        guard let scheme = url.scheme, scheme == "http" || scheme == "https", let host = url.host else { return nil }
        let origin = "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
        var components = URLComponents(string: "chrome://settings/content/siteDetails")
        components?.queryItems = [URLQueryItem(name: "site", value: origin)]
        return components?.url
    }

    private func header(for url: URL) -> NSView {
        let site = NSTextField(labelWithString: url.displayHost)
        site.font = .systemFont(ofSize: 14, weight: .semibold)
        site.lineBreakMode = .byTruncatingMiddle
        let secure = url.scheme == "https"
        let lock = NSImageView(image: Theme.symbol(secure ? "lock.fill" : "lock.open.fill", size: 9) ?? NSImage())
        lock.contentTintColor = .secondaryLabelColor
        let connection = NSTextField(labelWithString: secure ? "Connexion sécurisée" : "Connexion non sécurisée")
        connection.font = .systemFont(ofSize: 11)
        connection.textColor = .secondaryLabelColor

        let view = NSView()
        for subview in [site, lock, connection] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            site.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            site.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            site.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -8),
            lock.leadingAnchor.constraint(equalTo: site.leadingAnchor),
            lock.centerYAnchor.constraint(equalTo: connection.centerYAnchor),
            connection.topAnchor.constraint(equalTo: site.bottomAnchor, constant: 2),
            connection.leadingAnchor.constraint(equalTo: lock.trailingAnchor, constant: 4),
            connection.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
        return view
    }

    private func actions() -> NSView {
        let copy = ActionTile(symbol: "link", title: "Copier le lien") { [weak self] _ in
            self?.dismiss()
            self?.onCopy?()
        }
        let share = ActionTile(symbol: "square.and.arrow.up", title: "Partager") { [weak self] tile in
            guard let url = self?.url else { return }
            NSSharingServicePicker(items: [url]).show(relativeTo: tile.bounds, of: tile, preferredEdge: .minY)
        }
        let row = NSStackView(views: [copy, share])
        row.distribution = .fillEqually
        row.spacing = 6
        return row
    }
}

/// The card's content: first responder while it shows, so that Escape closes it.
private final class KeyCatcherView: NSView {
    var onCancel: (() -> Void)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// A thin separator between the card's sections.
private final class Rule: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = NSColor.separatorColor.cgColor }
}

/// A row that lights up under the pointer.
private class HoverRow: NSView {
    private(set) var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        isHovered = hovered
        needsDisplay = true
    }

    /// The background at rest; the hover darkens it a little.
    var restingAlpha: CGFloat { 0 }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func updateLayer() {
        let alpha = restingAlpha + (isHovered ? (isDarkAppearance ? 0.08 : 0.05) : 0)
        layer?.backgroundColor = alpha > 0 ? NSColor.labelColor.withAlphaComponent(alpha).cgColor : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // Clicks act on mouse up, inside the row, like buttons.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { press() }
    }

    override func accessibilityPerformPress() -> Bool {
        press()
        return true
    }

    func press() {}
}

/// A quick action: a symbol over a short title, in a rounded tile.
private final class ActionTile: HoverRow {
    private let handler: (ActionTile) -> Void

    init(symbol: String, title: String, handler: @escaping (ActionTile) -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        layer?.cornerRadius = 10
        let icon = NSImageView(image: Theme.symbol(symbol, size: 15) ?? NSImage())
        icon.contentTintColor = .labelColor
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        for view in [icon, label] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var restingAlpha: CGFloat { isDarkAppearance ? 0.07 : 0.045 }
    override func press() { handler(self) }
}

/// One permission: its icon, its name and state, and a switch (on: allowed). A click
/// anywhere on the row flips it.
private final class PermissionRow: HoverRow {
    private let toggle = NSSwitch()
    private let onChange: (Bool) -> Void

    private static let names = ["allow": "Autorisé", "block": "Bloqué", "ask": "Demander"]

    init(permission: SiteControlsController.Permission, state: String, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        let isAllowed = state == "allow"

        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 13
        badge.layer?.backgroundColor = isAllowed
            ? NSColor.controlAccentColor.cgColor
            : NSColor.labelColor.withAlphaComponent(0.1).cgColor
        let icon = NSImageView(image: Theme.symbol(permission.symbol, size: 11) ?? NSImage())
        icon.contentTintColor = isAllowed ? .white : .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(icon)

        let title = NSTextField(labelWithString: permission.title)
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let subtitle = NSTextField(labelWithString: Self.names[state] ?? state)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor

        toggle.controlSize = .mini
        toggle.state = isAllowed ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggled)
        toggle.setAccessibilityLabel(permission.title)

        for view in [badge, title, subtitle, toggle] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 42),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 26),
            badge.heightAnchor.constraint(equalToConstant: 26),
            icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            title.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            title.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func press() {
        toggle.state = toggle.state == .on ? .off : .on
        toggled()
    }

    @objc private func toggled() { onChange(toggle.state == .on) }
}

/// A link to another page: a symbol, a title and a chevron.
private final class LinkRow: HoverRow {
    private let handler: () -> Void

    init(symbol: String, title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        let icon = NSImageView(image: Theme.symbol(symbol, size: 12) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        let chevron = NSImageView(image: Theme.symbol("chevron.right", size: 10) ?? NSImage())
        chevron.contentTintColor = .tertiaryLabelColor
        for view in [icon, label, chevron] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            icon.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 21),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 44),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func press() { handler() }
}
