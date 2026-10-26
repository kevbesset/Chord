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

    private init(page: ChordWebPage) {
        self.page = page
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

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
