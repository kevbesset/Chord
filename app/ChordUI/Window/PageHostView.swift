import AppKit
import ObjectiveC

/// What a card shows for a page: the page, and its developer tools when they are
/// docked, as in Chrome and Arc. The tools fill the area and the page takes the part
/// they leave it, on the side and at the size chosen in the tools.
///
/// One host per page, kept with the page, so that the page and its tools move
/// together between the main window, a Peek and a little window.
final class PageHostView: NSView {
    private weak var page: ChordWebPage?
    private weak var devTools: NSView?
    private static var hostKey: UInt8 = 0

    static func host(for page: ChordWebPage) -> PageHostView {
        if let host = objc_getAssociatedObject(page, &hostKey) as? PageHostView { return host }
        let host = PageHostView(page: page)
        objc_setAssociatedObject(page, &hostKey, host, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return host
    }

    /// The tools opened, closed, moved to another side or were resized.
    static func pageDidUpdate(_ page: ChordWebPage) {
        (objc_getAssociatedObject(page, &hostKey) as? PageHostView)?.needsLayout = true
    }

    /// A page moved to another window, or left its window. A page has a single view, so
    /// the windows whose selected tab shows it look again at which of them has it.
    static let didMoveNotification = Notification.Name("ChordPageHostDidMove")
    private static var moveNotificationPending = false

    private init(page: ChordWebPage) {
        self.page = page
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !Self.moveNotificationPending else { return }
        Self.moveNotificationPending = true
        // Once the moves of this pass are over: a card often lets a page go just before
        // another one takes it.
        DispatchQueue.main.async {
            Self.moveNotificationPending = false
            NotificationCenter.default.post(name: Self.didMoveNotification, object: nil)
        }
    }

    override func layout() {
        super.layout()
        guard let page else { return }
        let pageView = page.view
        if pageView.superview !== self {
            pageView.removeFromSuperview()
            pageView.translatesAutoresizingMaskIntoConstraints = true
            addSubview(pageView)
        }
        let tools = page.devToolsView ?? nil
        if tools !== devTools {
            if devTools?.superview === self { devTools?.removeFromSuperview() }
            if let tools {
                tools.translatesAutoresizingMaskIntoConstraints = true
                addSubview(tools, positioned: .below, relativeTo: pageView)
            }
            devTools = tools
        }
        tools?.frame = bounds
        pageView.frame = tools == nil ? bounds : (page.pageFrame?(withDevToolsIn: bounds.size) ?? bounds)
    }
}

/// What a window shows for a selected tab that another window shows: the page has a
/// single view, which goes to the window the user acts in. Clicking here makes this
/// window that one, and the page comes over.
final class PageElsewhereView: NSView {
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let icon = NSImageView(image: NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 28, weight: .light)
        icon.contentTintColor = .tertiaryLabelColor
        let title = NSTextField(labelWithString: String(localized: "This tab is shown in another window", bundle: .chordUI))
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = .secondaryLabelColor
        let detail = NSTextField(labelWithString: String(localized: "Click to show it here", bundle: .chordUI))
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .tertiaryLabelColor
        for view in [icon, title, detail] { stack.addArrangedSubview(view) }
        stack.orientation = .vertical
        stack.spacing = 6
        stack.setCustomSpacing(12, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }
}
