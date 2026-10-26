import AppKit

/// The site's controls, from the button in the address field, like Arc's: quick actions
/// in tiles, the extensions, the site's permissions (notifications, and every one chosen
/// for this site), then the connection and a way to all of the site's settings. A card laid over the
/// window, like the command bar; the engine keeps the permissions.
final class SiteControlsController: NSObject {
    private static let width: CGFloat = 300

    var onCopy: (() -> Void)?
    /// Opens a page in a new tab (the site's full settings).
    var onOpen: ((URL) -> Void)?
    var onDismiss: (() -> Void)?
    /// What the extensions' tiles do. A tile's popup hangs from the button that
    /// opened the card, as the card closes.
    var extensionActions: ExtensionActions?
    var isGlass = true
    private(set) var isVisible = false

    private let scrim = ScrimView()
    private let panelHost = ShadowHostView()
    private let panel = NSVisualEffectView()
    private let content = KeyCatcherView()
    private var page: ChordWebPage?
    private var url: URL?
    private weak var anchor: NSView?
    private weak var host: NSView?

    /// Shows the controls of `page` in `host`, under `anchor` (the button that opened them).
    func present(page: ChordWebPage, url: URL, in host: NSView, below anchor: NSView) {
        let interval = Perf.begin("sitecontrols.open")
        defer { DispatchQueue.main.async { interval.end() } }
        self.page = page
        self.url = url
        self.anchor = anchor
        self.host = host
        install(in: host)
        rebuild()
        place()
        panel.material = isGlass ? .popover : .windowBackground

        scrim.isHidden = false
        panelHost.isHidden = false
        isVisible = true
        host.window?.makeFirstResponder(content)
    }

    /// Draws the card again (an extension's badge or pin changed), where it is.
    func refresh() {
        guard isVisible else { return }
        rebuild()
        place()
    }

    /// Under the anchor, as tall as its content.
    private func place() {
        guard let anchor, let host else { return }
        content.layoutSubtreeIfNeeded()
        let size = NSSize(width: Self.width, height: content.fittingSize.height)
        let rect = anchor.convert(anchor.bounds, to: host)
        let x = min(max(8, rect.midX - 40), host.bounds.width - size.width - 8)
        let gap: CGFloat = 6
        let y = host.isFlipped ? rect.maxY + gap : rect.minY - gap - size.height
        panelHost.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
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

        panelHost.cornerRadius = 16
        panelHost.configureShadow(opacity: 0.2, radius: 24, offsetY: -8)
        panel.blendingMode = .withinWindow
        panel.state = .active
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 16
        panel.layer?.masksToBounds = true
        panel.layer?.borderWidth = 0.5
        panel.layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
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

        var sections: [(view: NSView, gap: CGFloat)] = [(actions(), 0)]
        if let extensionActions {
            sections.append((SectionTitle("Extensions"), 14))
            sections.append((extensionsGrid(PageExtension.all(of: page), actions: extensionActions), 6))
        }
        let permissions = page.sitePermissions ?? []
        if !permissions.isEmpty {
            sections.append((SectionTitle("Autorisations"), 14))
            for (index, permission) in permissions.enumerated() {
                guard let id = permission["id"], let state = permission["state"] else { continue }
                let row = PermissionRow(title: permission["title"] ?? id, symbol: Self.symbol(for: id), state: state) { [weak self] in
                    // Like Arc, a click flips it: allowed, or blocked.
                    self?.page?.setPermission?(id, state: state == "allow" ? "block" : "allow")
                    self?.rebuild()
                }
                sections.append((row, index == 0 ? 4 : 0))
            }
        }
        sections.append((Rule(), 10))
        sections.append((footer(for: url), 8))

        var previous: NSView?
        for (view, gap) in sections {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
            let inset: CGFloat = view is Rule ? 16 : (view is SectionTitle ? 16 : 10)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
                view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
                view.topAnchor.constraint(equalTo: previous?.bottomAnchor ?? content.topAnchor, constant: previous == nil ? 10 : gap),
            ])
            previous = view
        }
        // At most: the card's height comes from its content.
        previous?.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -10).isActive = true
    }

    /// Chromium's page with every permission of the site.
    private static func siteSettingsURL(for url: URL) -> URL? {
        guard let scheme = url.scheme, scheme == "http" || scheme == "https", let host = url.host else { return nil }
        let origin = "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
        var components = URLComponents(string: "chrome://settings/content/siteDetails")
        components?.queryItems = [URLQueryItem(name: "site", value: origin)]
        return components?.url
    }

    /// A symbol for each permission, by the engine's name for it.
    private static func symbol(for id: String) -> String {
        [
            "notifications": "bell.fill",
            "geolocation": "location.fill",
            "media-stream-camera": "video.fill",
            "camera-pan-tilt-zoom": "move.3d",
            "media-stream-mic": "mic.fill",
            "sensors": "gyroscope",
            "javascript": "curlybraces",
            "images": "photo.fill",
            "popups": "macwindow.on.rectangle",
            "window-placement": "rectangle.3.group.fill",
            "background-sync": "arrow.triangle.2.circlepath",
            "sound": "speaker.wave.2.fill",
            "automatic-downloads": "arrow.down.circle.fill",
            "midi-sysex": "pianokeys",
            "clipboard": "doc.on.clipboard.fill",
            "usb-guard": "cable.connector",
            "hid-guard": "gamecontroller.fill",
            "serial-guard": "cable.connector.horizontal",
            "file-system-write-guard": "folder.fill",
            "local-fonts": "textformat",
            "bluetooth-guard": "dot.radiowaves.left.and.right",
            "bluetooth-scanning": "dot.radiowaves.left.and.right",
            "hand-tracking": "hand.raised.fill",
            "vr": "visionpro",
            "ar": "arkit",
            "idle-detection": "moon.zzz.fill",
            "auto-picture-in-picture": "pip.fill",
            "captured-surface-control": "rectangle.dashed",
            "automatic-fullscreen": "arrow.up.left.and.arrow.down.right",
            "keyboard-lock": "keyboard.fill",
            "pointer-lock": "cursorarrow",
            "web-app-installation": "square.and.arrow.down.fill",
            "local-network": "network",
            "loopback-network": "network",
        ][id] ?? "switch.2"
    }

    /// Quick actions, as Arc's: icon tiles, named on hover.
    private func actions() -> NSView {
        let share = ActionTile(symbol: "square.and.arrow.up", title: "Partager") { [weak self] tile in
            guard let url = self?.url else { return }
            NSSharingServicePicker(items: [url]).show(relativeTo: tile.bounds, of: tile, preferredEdge: .minY)
        }
        let copy = ActionTile(symbol: "link", title: "Copier le lien") { [weak self] _ in
            self?.dismiss()
            self?.onCopy?()
        }
        let devTools = ActionTile(symbol: "hammer", title: "Outils de développement (⌥⌘I)") { [weak self] _ in
            let page = self?.page
            self?.dismiss()
            page?.toggleDevTools?()
        }
        let row = NSStackView(views: [share, copy, devTools])
        row.distribution = .fillEqually
        row.spacing = 8
        return row
    }

    /// The extensions in tiles, four to a row, then one to manage them all. A click runs
    /// one (its popup comes from the card's button), a right click shows its menu.
    private func extensionsGrid(_ items: [PageExtension], actions: ExtensionActions) -> NSView {
        var tiles: [NSView] = items.map { item in
            ExtensionTile(item: item, menu: { actions.menu(for: item) }) { [weak self] in
                guard let self, let anchor = self.anchor else { return }
                self.dismiss()
                actions.run(item, anchor)
            }
        }
        tiles.append(ExtensionTile(symbol: "plus", title: "Gérer les extensions") { [weak self] in
            self?.dismiss()
            if let url = URL(string: "chrome://extensions") { actions.open(url) }
        })
        let columns = 4
        let rows = stride(from: 0, to: tiles.count, by: columns).map { start -> NSView in
            var row = Array(tiles[start..<min(start + columns, tiles.count)])
            // Empty cells keep the tiles of a short last row at their size.
            while row.count < columns { row.append(NSView()) }
            let stack = NSStackView(views: row)
            stack.distribution = .fillEqually
            stack.spacing = 8
            return stack
        }
        let grid = NSStackView(views: rows)
        grid.orientation = .vertical
        grid.alignment = .width
        grid.spacing = 8
        for row in rows { row.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true }
        return grid
    }

    /// The connection, then every setting of the site.
    private func footer(for url: URL) -> NSView {
        let connection: (symbol: String, title: String)
        if url.scheme == "https" {
            connection = ("lock.fill", "Sécurisée")
        } else if url.isLocal {
            connection = ("desktopcomputer", "Locale")
        } else {
            connection = ("lock.open.fill", "Non sécurisée")
        }
        let pill = ConnectionPill(symbol: connection.symbol, title: connection.title)
        let view = NSView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pill)
        var constraints = [
            pill.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pill.topAnchor.constraint(equalTo: view.topAnchor),
            pill.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        if let settingsURL = Self.siteSettingsURL(for: url) {
            let more = RoundButton(symbol: "ellipsis", title: "Tous les réglages du site") { [weak self] in
                self?.dismiss()
                self?.onOpen?(settingsURL)
            }
            more.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(more)
            constraints += [
                more.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                more.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        return view
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

/// A faint separator above the card's footer.
private final class Rule: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A section's name, like Arc's "Extensions" or "Settings".
private final class SectionTitle: NSTextField {
    convenience init(_ title: String) {
        self.init(labelWithString: title)
        font = .systemFont(ofSize: 13, weight: .semibold)
        textColor = .labelColor
    }
}

/// A view that lights up under the pointer and acts on mouse up, like a button.
private class HoverRow: NSView {
    private(set) var isHovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
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

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func updateLayer() {
        let alpha: CGFloat = isHovered ? (isDarkAppearance ? 0.08 : 0.05) : 0
        layer?.backgroundColor = alpha > 0 ? NSColor.labelColor.withAlphaComponent(alpha).cgColor : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

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

/// A quick action: a symbol in a raised tile, like Arc's, named by its tooltip.
private final class ActionTile: HoverRow {
    private let handler: (ActionTile) -> Void

    init(symbol: String, title: String, handler: @escaping (ActionTile) -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        let icon = NSImageView(image: Theme.symbol(symbol, size: 16) ?? NSImage())
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = title
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateLayer() {
        guard let layer else { return }
        let dark = isDarkAppearance
        layer.cornerRadius = 11
        layer.backgroundColor = (dark
            ? NSColor.white.withAlphaComponent(isHovered ? 0.16 : 0.1)
            : NSColor.white.withAlphaComponent(isHovered ? 1 : 0.85)).cgColor
        layer.borderWidth = 0.5
        layer.borderColor = NSColor.black.withAlphaComponent(dark ? 0.25 : 0.08).cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = dark ? 0 : 0.06
        layer.shadowRadius = 1.5
        layer.shadowOffset = CGSize(width: 0, height: -1)
    }

    override func press() { handler(self) }
}

/// An extension in the card: its icon and badge on a raised tile like the actions', a
/// pin when it is pinned in the address. Or, without one, a symbol (manage them all).
private final class ExtensionTile: HoverRow {
    private let handler: () -> Void
    private let contextMenu: (() -> NSMenu?)?

    init(item: PageExtension, menu: @escaping () -> NSMenu?, handler: @escaping () -> Void) {
        self.handler = handler
        contextMenu = menu
        super.init(frame: .zero)
        let icon = ExtensionIconView(size: 20)
        icon.configure(item)
        addSubview(icon)
        var constraints = [
            heightAnchor.constraint(equalToConstant: 46),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        if item.isPinned {
            let pin = PinMark()
            pin.translatesAutoresizingMaskIntoConstraints = false
            addSubview(pin)
            constraints += [
                pin.centerXAnchor.constraint(equalTo: icon.trailingAnchor, constant: 2),
                pin.centerYAnchor.constraint(equalTo: icon.bottomAnchor, constant: 1),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        toolTip = item.name
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.name)
    }

    init(symbol: String, title: String, handler: @escaping () -> Void) {
        self.handler = handler
        contextMenu = nil
        super.init(frame: .zero)
        let icon = NSImageView(image: Theme.symbol(symbol, size: 15) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = title
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateLayer() {
        guard let layer else { return }
        let dark = isDarkAppearance
        layer.cornerRadius = 11
        let alpha: CGFloat = dark ? (isHovered ? 0.12 : 0.07) : (isHovered ? 0.1 : 0.06)
        layer.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
    }

    override func menu(for event: NSEvent) -> NSMenu? { contextMenu?() }
    override func press() { handler() }

    /// VoiceOver's "show menu": the same menu as a right click.
    override func accessibilityPerformShowMenu() -> Bool {
        guard let menu = contextMenu?() else { return false }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
        return true
    }
}

/// The small pin on a pinned extension's tile, like Arc's.
private final class PinMark: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let icon = NSImageView(image: Theme.symbol("pin.fill", size: 6, weight: .bold) ?? NSImage())
        icon.contentTintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 13),
            heightAnchor.constraint(equalToConstant: 13),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.cornerRadius = 6.5
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.white.withAlphaComponent(isDarkAppearance ? 0.2 : 0.9).cgColor
    }
}

/// One permission, like Arc's settings: a round badge, filled when allowed, the name and
/// the state below it. A click flips it.
private final class PermissionRow: HoverRow {
    private let onToggle: () -> Void

    private static let names = ["allow": "Autorisé", "block": "Bloqué", "ask": "Demander"]

    init(title: String, symbol: String, state: String, onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        super.init(frame: .zero)
        let badge = PermissionBadge(symbol: symbol, isOn: state == "allow")
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stateLabel = NSTextField(labelWithString: Self.names[state] ?? state)
        stateLabel.font = .systemFont(ofSize: 12)
        stateLabel.textColor = .secondaryLabelColor

        for view in [badge, titleLabel, stateLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            stateLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            stateLabel.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(title) : \(Self.names[state] ?? state)")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func press() { onToggle() }
}

/// A permission's symbol in a circle: solid when allowed, faint otherwise.
private final class PermissionBadge: NSView {
    private let icon = NSImageView()
    private let isOn: Bool

    init(symbol: String, isOn: Bool) {
        self.isOn = isOn
        super.init(frame: .zero)
        wantsLayer = true
        icon.image = Theme.symbol(symbol, size: 13)
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(equalToConstant: 32),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = isDarkAppearance
        layer?.cornerRadius = 16
        if isOn {
            layer?.backgroundColor = (dark ? NSColor.white : NSColor.black.withAlphaComponent(0.85)).cgColor
            icon.contentTintColor = dark ? .black : .white
        } else {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(dark ? 0.14 : 0.1).cgColor
            icon.contentTintColor = .secondaryLabelColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// The connection, in a soft pill, like Arc's "Secure".
private final class ConnectionPill: NSView {
    init(symbol: String, title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        let icon = NSImageView(image: Theme.symbol(symbol, size: 11) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Connexion : \(title)")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(isDarkAppearance ? 0.1 : 0.06).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A round button with a symbol, like Arc's "…".
private final class RoundButton: HoverRow {
    private let handler: () -> Void

    init(symbol: String, title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
        let icon = NSImageView(image: Theme.symbol(symbol, size: 13, weight: .semibold) ?? NSImage())
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 30),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = title
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateLayer() {
        layer?.cornerRadius = 15
        let alpha: CGFloat = (isDarkAppearance ? 0.1 : 0.06) + (isHovered ? 0.05 : 0)
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
    }

    override func press() { handler() }
}
