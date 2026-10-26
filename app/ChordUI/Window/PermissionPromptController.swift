import AppKit

/// A site's question (camera, notifications…), like Arc's: a popover from the site
/// controls button with a round badge, the question, "Bloquer" and "Autoriser", and a
/// quieter "Pas maintenant". The page
/// stays usable while it is up. It stays until answered, or until the engine takes
/// it back (another tab selected, the tab closed), and asks again later.
final class PermissionPromptController: NSObject, NSPopoverDelegate {
    /// Called once the question is gone, answered or not.
    var onClose: (() -> Void)?

    private let popover = NSPopover()
    private var request: ChordPermissionRequest?
    private(set) weak var page: ChordWebPage?
    /// Closed by Chord itself (answered, taken back): nothing more to tell the engine.
    private var closingQuietly = false
    /// Out of the way for a moment (the site controls opened), still unanswered.
    private(set) var isSuspended = false

    var isVisible: Bool { popover.isShown }

    override init() {
        super.init()
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
    }

    /// Shows the question for `page`, hanging from `anchor`: under it, or under `rect`
    /// of it when given.
    func present(_ request: ChordPermissionRequest, for page: ChordWebPage, from anchor: NSView, rect: NSRect? = nil) {
        let interval = Perf.begin("permission.prompt")
        if self.request != nil { takeDown() }
        self.request = request
        self.page = page
        request.onCancel = { [weak self, weak request] in
            guard let self, let request, self.request === request else { return }
            self.takeDown()
        }
        popover.contentViewController = PermissionPromptViewController(request: request) { [weak self] answer in
            self?.answer(answer)
        }
        show(from: anchor, rect: rect)
        DispatchQueue.main.async { interval.end() }
    }

    /// Moves the open question to another anchor (the sidebar came or went).
    func reanchor(to anchor: NSView, rect: NSRect? = nil) {
        guard isVisible else { return }
        show(from: anchor, rect: rect)
    }

    /// Steps aside while another card takes its place (the site controls), keeping the
    /// question for later.
    func suspend() {
        guard isVisible else { return }
        isSuspended = true
        closingQuietly = true
        popover.performClose(nil)
    }

    /// Back after `suspend()`, if the question is still open.
    func resume(from anchor: NSView, rect: NSRect? = nil) {
        guard isSuspended else { return }
        isSuspended = false
        if request != nil { show(from: anchor, rect: rect) }
    }

    private func show(from anchor: NSView, rect: NSRect?) {
        popover.show(relativeTo: rect ?? anchor.bounds, of: anchor, preferredEdge: anchor.isFlipped ? .maxY : .minY)
    }

    enum Answer { case allow, block, notNow }

    /// "Autoriser" and "Bloquer" are kept for the site; "Pas maintenant" decides
    /// nothing, like Arc's "Not Now": the site may ask again.
    private func answer(_ answer: Answer) {
        guard let request else { return }
        takeDown()
        switch answer {
        case .allow: request.allow()
        case .block: request.block()
        case .notNow: request.dismiss()
        }
    }

    /// Closes the question without answering it.
    private func takeDown() {
        request?.onCancel = nil
        request = nil
        isSuspended = false
        closingQuietly = true
        popover.performClose(nil)
        if !popover.isShown { finishClosing() }
    }

    func popoverDidClose(_ notification: Notification) {
        finishClosing()
    }

    private func finishClosing() {
        // Closed by AppKit (its window went away): the site gets no decision.
        if !closingQuietly, let request {
            self.request = nil
            request.onCancel = nil
            request.dismiss()
        }
        closingQuietly = false
        if !isSuspended { onClose?() }
    }

    /// Where a question hangs from when it has no button to come from: just under the
    /// top edge of the page, near its left corner.
    static func pageTop(of view: NSView) -> NSRect {
        let top = view.isFlipped ? view.bounds.minY : view.bounds.maxY - 1
        return NSRect(x: view.bounds.minX + 28, y: top, width: 1, height: 1)
    }

    /// The question in French, from what the engine says is asked: "Autoriser
    /// webcamtoy.com à utiliser vos caméras ?"
    static func question(site: String, asks: [String]) -> String {
        let parts = asks.map { $0.prefix(1).lowercased() + $0.dropFirst() }
        guard let last = parts.last else { return "\(site) demande une autorisation." }
        let what = parts.count == 1 ? last : parts.dropLast().joined(separator: ", ") + " et " + last
        return "Autoriser \(site) à \(what)\u{202F}?"
    }
}

private final class PermissionPromptViewController: NSViewController {
    private let request: ChordPermissionRequest
    private let onAnswer: (PermissionPromptController.Answer) -> Void

    init(request: ChordPermissionRequest, onAnswer: @escaping (PermissionPromptController.Answer) -> Void) {
        self.request = request
        self.onAnswer = onAnswer
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let badge = SymbolBadgeView(symbol: request.symbol)
        let question = NSTextField(wrappingLabelWithString: PermissionPromptController.question(site: request.site, asks: request.asks))
        question.font = .systemFont(ofSize: 15, weight: .medium)
        question.textColor = .labelColor
        question.preferredMaxLayoutWidth = 214
        let block = PromptButton(title: "Bloquer", style: .secondary) { [weak self] in self?.onAnswer(.block) }
        let allow = PromptButton(title: "Autoriser", style: .primary) { [weak self] in self?.onAnswer(.allow) }
        let notNow = PromptButton(title: "Pas maintenant", style: .quiet) { [weak self] in self?.onAnswer(.notNow) }

        let view = NSView()
        for subview in [badge, question, block, allow, notNow] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 300),
            badge.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            badge.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            question.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
            question.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            question.topAnchor.constraint(equalTo: view.topAnchor, constant: 15),
            question.centerYAnchor.constraint(greaterThanOrEqualTo: badge.centerYAnchor),
            block.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            block.topAnchor.constraint(greaterThanOrEqualTo: badge.bottomAnchor, constant: 16),
            block.topAnchor.constraint(greaterThanOrEqualTo: question.bottomAnchor, constant: 16),
            allow.leadingAnchor.constraint(equalTo: block.trailingAnchor, constant: 8),
            allow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            allow.topAnchor.constraint(equalTo: block.topAnchor),
            allow.widthAnchor.constraint(equalTo: block.widthAnchor),
            notNow.topAnchor.constraint(equalTo: block.bottomAnchor, constant: 6),
            notNow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            notNow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            notNow.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(question.stringValue)
        self.view = view
    }
}

/// What is asked, as a symbol in a soft round badge.
private final class SymbolBadgeView: NSView {
    private let icon = NSImageView()

    init(symbol: String) {
        super.init(frame: .zero)
        wantsLayer = true
        icon.image = Theme.symbol(symbol, size: 16)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 38),
            heightAnchor.constraint(equalToConstant: 38),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 19
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(isDarkAppearance ? 0.1 : 0.07).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A wide rounded button: white for the answer that goes ahead, a soft fill for the
/// other, and no fill at all for the one that decides nothing.
private final class PromptButton: NSView {
    enum Style { case primary, secondary, quiet }

    private let style: Style
    private let action: () -> Void
    private let label: NSTextField
    private var isHovered = false
    private var isPressed = false

    init(title: String, style: Style, action: @escaping () -> Void) {
        self.style = style
        self.action = action
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        label.font = .systemFont(ofSize: style == .quiet ? 12 : 13, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: style == .quiet ? 28 : 34),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        guard let layer else { return }
        let dark = isDarkAppearance
        layer.cornerRadius = 9
        let background: NSColor
        switch style {
        case .primary:
            background = dark
                ? NSColor.white.withAlphaComponent(isPressed ? 0.78 : isHovered ? 0.98 : 0.92)
                : NSColor(white: isPressed ? 0.9 : isHovered ? 0.98 : 1, alpha: 1)
            label.textColor = NSColor.black.withAlphaComponent(0.85)
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = dark ? 0 : 0.12
            layer.shadowRadius = 2
            layer.shadowOffset = CGSize(width: 0, height: -1)
        case .secondary:
            let alpha: CGFloat = (dark ? 0.12 : 0.07) + (isPressed ? 0.08 : isHovered ? 0.04 : 0)
            background = NSColor.labelColor.withAlphaComponent(alpha)
            label.textColor = .labelColor
        case .quiet:
            let alpha: CGFloat = isPressed ? 0.08 : isHovered ? 0.05 : 0
            background = NSColor.labelColor.withAlphaComponent(alpha)
            label.textColor = isHovered ? .labelColor : .secondaryLabelColor
        }
        layer.backgroundColor = background.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
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

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
    }

    // Acts on mouse up, inside the button.
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }
}
