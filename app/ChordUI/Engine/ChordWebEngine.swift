import AppKit

/// What ChordUI needs from a browser engine.
///
/// ChordUI never talks to WebKit or Chromium directly. The development app (ChordDev)
/// implements these protocols with WebKit; the real browser implements them in
/// Objective-C++ on top of Chromium's WebContents. They are `@objc` so that
/// Objective-C++ classes can conform without Swift/C++ interop.
@objc public protocol ChordWebEngine: AnyObject {
    /// Creates an empty page. Nothing loads until `load(_:)` is called.
    func makePage() -> ChordWebPage
}

@objc public protocol ChordWebPage: AnyObject {
    /// The view that renders the page. ChordUI places it inside the content card.
    var view: NSView { get }
    var url: URL? { get }
    var title: String? { get }
    var isLoading: Bool { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    /// The page's own icon, as declared by the page (best size for the sidebar), once known.
    @objc optional var faviconURL: URL? { get }
    /// Held weakly by implementations.
    var delegate: ChordWebPageDelegate? { get set }

    func load(_ url: URL)
    func goBack()
    func goForward()
    func reload()
    /// Reloads without the cache (⇧⌘R): every resource comes from the network again.
    @objc optional func reloadIgnoringCache()
    func stopLoading()
}

@objc public protocol ChordWebPageDelegate: AnyObject {
    /// The URL, title, loading or navigation state changed.
    func pageDidUpdate(_ page: ChordWebPage)
    /// The page wants a link opened in a new tab (target=_blank, window.open).
    func page(_ page: ChordWebPage, wantsNewTabWith url: URL)
    /// The user clicked a link. Return false when ChordUI handled it elsewhere
    /// (a Peek, a background tab); the engine then cancels the navigation.
    @objc optional func page(_ page: ChordWebPage, shouldFollowLinkTo url: URL, modifiers: NSEvent.ModifierFlags) -> Bool
}
