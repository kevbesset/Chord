import AppKit

/// An extension with a button, as a page sees it (badges are per tab).
struct PageExtension {
    let id: String
    let name: String
    let icon: NSImage?
    let badge: String
    let badgeColor: NSColor?
    let isPinned: Bool
    let optionsURL: URL?

    init?(_ values: [String: Any]) {
        guard let id = values["id"] as? String else { return nil }
        self.id = id
        name = values["name"] as? String ?? id
        icon = values["icon"] as? NSImage
        badge = values["badge"] as? String ?? ""
        badgeColor = values["badgeColor"] as? NSColor
        isPinned = (values["pinned"] as? Bool) ?? false
        optionsURL = (values["options"] as? String).flatMap(URL.init(string:))
    }

    /// The page's extensions, pinned ones first.
    static func all(of page: ChordWebPage?) -> [PageExtension] {
        (page?.extensions ?? []).compactMap(PageExtension.init)
    }

    /// Chromium's page for this extension (details, permissions, site access).
    var manageURL: URL? { URL(string: "chrome://extensions/?id=\(id)") }
}

/// What can be done with an extension, wherever its button is.
struct ExtensionActions {
    var run: (PageExtension, NSView) -> Void
    var setPinned: (PageExtension, Bool) -> Void
    var open: (URL) -> Void
    var uninstall: (PageExtension) -> Void

    /// The right-click menu of an extension's button, like Arc's.
    func menu(for item: PageExtension) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(closureItem(item.isPinned ? "Retirer de la barre d'adresse" : "Épingler dans la barre d'adresse") {
            setPinned(item, !item.isPinned)
        })
        if let options = item.optionsURL {
            menu.addItem(closureItem("Options") { open(options) })
        }
        if let manage = item.manageURL {
            menu.addItem(closureItem("Gérer l'extension") { open(manage) })
        }
        menu.addItem(.separator())
        menu.addItem(closureItem("Supprimer « \(item.name) »…") { uninstall(item) })
        return menu
    }
}

/// An extension's icon with its badge, as Chrome draws it: a small pill of the
/// badge's colour over the icon's bottom-right corner.
final class ExtensionIconView: NSView {
    private let image = NSImageView()
    private let badge = NSTextField(labelWithString: "")
    private let badgeBackground = NSView()

    init(size: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        image.imageScaling = .scaleProportionallyUpOrDown
        badge.font = .systemFont(ofSize: 8, weight: .bold)
        badge.textColor = .white
        badge.alignment = .center
        badgeBackground.wantsLayer = true
        badgeBackground.layer?.cornerRadius = 4
        for view in [image, badgeBackground, badge] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            image.topAnchor.constraint(equalTo: topAnchor),
            image.leadingAnchor.constraint(equalTo: leadingAnchor),
            image.trailingAnchor.constraint(equalTo: trailingAnchor),
            image.bottomAnchor.constraint(equalTo: bottomAnchor),
            badgeBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 4),
            badgeBackground.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 3),
            badgeBackground.heightAnchor.constraint(equalToConstant: 11),
            badgeBackground.widthAnchor.constraint(greaterThanOrEqualToConstant: 11),
            badge.centerXAnchor.constraint(equalTo: badgeBackground.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: badgeBackground.centerYAnchor),
            badgeBackground.widthAnchor.constraint(greaterThanOrEqualTo: badge.widthAnchor, constant: 4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ item: PageExtension) {
        image.image = item.icon ?? Theme.symbol("puzzlepiece.extension.fill", size: 13)
        image.contentTintColor = item.icon == nil ? .secondaryLabelColor : nil
        badge.stringValue = item.badge
        badge.isHidden = item.badge.isEmpty
        badgeBackground.isHidden = item.badge.isEmpty
        badgeBackground.layer?.backgroundColor = (item.badgeColor ?? .systemRed).cgColor
    }
}

/// A pinned extension's button in an address field: its icon and badge; a click runs
/// it, a right click shows its menu.
final class ExtensionButton: NSView {
    private(set) var item: PageExtension
    private let icon: ExtensionIconView
    private let actions: ExtensionActions
    private var isHovered = false

    init(item: PageExtension, actions: ExtensionActions, size: CGFloat, iconSize: CGFloat) {
        self.item = item
        self.actions = actions
        icon = ExtensionIconView(size: iconSize)
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        icon.configure(item)
        toolTip = item.name
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.badge.isEmpty ? item.name : "\(item.name) (\(item.badge))")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        layer?.cornerRadius = (bounds.height * 0.25).rounded()
        layer?.backgroundColor = isHovered
            ? (isDarkAppearance ? NSColor.white.withAlphaComponent(0.1) : NSColor.black.withAlphaComponent(0.06)).cgColor
            : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { actions.run(item, self) }
    }

    override func menu(for event: NSEvent) -> NSMenu? { actions.menu(for: item) }

    /// VoiceOver's "show menu": the same menu as a right click.
    override func accessibilityPerformShowMenu() -> Bool {
        actions.menu(for: item).popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY), in: self)
        return true
    }

    override func accessibilityPerformPress() -> Bool {
        actions.run(item, self)
        return true
    }
}

/// Frames the popup's page to the popover's content, as `PageHostView` does for pages:
/// Chromium's view does not place itself. Behind it, the background Chrome gives
/// popups.
private final class PopupContainerView: NSView {
    private let content: NSView

    init(content: NSView) {
        self.content = content
        super.init(frame: .zero)
        wantsLayer = true
        content.translatesAutoresizingMaskIntoConstraints = true
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    override func layout() {
        super.layout()
        content.frame = bounds
    }
}

/// An extension's popup in a popover from its button, sized by its content like
/// Chrome's. Closes on a click elsewhere, or when the popup closes itself.
final class ExtensionPopupController: NSObject, NSPopoverDelegate {
    var onClose: (() -> Void)?
    private let popover = NSPopover()
    private var popup: ChordExtensionPopup?
    private weak var anchor: NSView?

    var isVisible: Bool { popover.isShown }

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    /// Shows once the popup's content has loaded and knows its size.
    func show(_ popup: ChordExtensionPopup, from anchor: NSView) {
        close()
        self.popup = popup
        self.anchor = anchor
        let controller = NSViewController()
        controller.view = PopupContainerView(content: popup.view)
        popover.contentViewController = controller
        popup.onResize = { [weak self, weak popup] in
            guard let self, let popup, self.popup === popup else { return }
            self.resize(to: popup.preferredSize)
        }
        popup.onClose = { [weak self, weak popup] in
            guard let self, let popup, self.popup === popup else { return }
            self.close()
        }
        if popup.preferredSize.width > 0 { resize(to: popup.preferredSize) }
    }

    private func resize(to size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
        popover.contentSize = size
        guard !popover.isShown, let anchor, anchor.window != nil, let popup else { return }
        let interval = Perf.begin("extension.popup")
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: anchor.isFlipped ? .maxY : .minY)
        popover.contentViewController?.view.needsLayout = true
        // Typing goes to the popup (a password, a search).
        popup.view.window?.makeFirstResponder(popup.view)
        DispatchQueue.main.async { interval.end() }
    }

    func close() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            finish()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        finish()
    }

    private func finish() {
        guard let popup else { return }
        self.popup = nil
        popup.onResize = nil
        popup.onClose = nil
        popup.close()
        onClose?()
    }
}
