import AppKit

/// What ChordUI needs from a browser engine.
///
/// ChordUI never talks to Chromium directly: //chord implements these protocols in
/// Objective-C++ on top of Chromium's WebContents (engine/chord/browser/chord_engine.mm).
/// They are `@objc` so that Objective-C++ classes can conform without Swift/C++
/// interop, under fixed Objective-C names that `engine/chord/browser/chord_ui.h`
/// mirrors. Keeping the engine behind them also leaves room for other engines later.
@objc(ChordWebEngine) public protocol ChordWebEngine: AnyObject {
    /// Creates an empty page. Nothing loads until `load(_:)` is called.
    func makePage() -> ChordWebPage
    /// Stops a download started by one of the engine's pages.
    @objc optional func cancelDownload(_ id: String)
    /// Receives the pages the engine opens by itself. Set once by ChordUI.
    @objc optional func setDelegate(_ delegate: ChordWebEngineDelegate?)
    /// An engine on a private profile, for private browsing windows: no history,
    /// cookies or cache kept once its last window closes.
    @objc optional func makePrivateEngine() -> ChordWebEngine
}

@objc(ChordWebEngineDelegate) public protocol ChordWebEngineDelegate: AnyObject {
    /// The engine opened a page by itself: a link to a new tab, `window.open`, an
    /// extension's tab. `opener` is the page it came from, when there is one.
    func engine(_ engine: ChordWebEngine, didOpen page: ChordWebPage, opener: ChordWebPage?, inBackground: Bool)
    /// The page closed itself (`window.close()`, an extension): its tab goes away.
    func engine(_ engine: ChordWebEngine, didClose page: ChordWebPage)
    /// The engine wants the page on screen: the "back to tab" button of a
    /// picture-in-picture window, a notification clicked.
    @objc optional func engine(_ engine: ChordWebEngine, wantsToShow page: ChordWebPage)
}

@objc(ChordWebPage) public protocol ChordWebPage: AnyObject {
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
    /// ChordUI shows this page as the selected tab: the engine makes it its active one.
    @objc optional func didBecomeActive()
    /// Opens or closes the page's developer tools (⌥⌘I).
    @objc optional func toggleDevTools()
    /// The page's playing video goes to a picture-in-picture window, if it has one
    /// (the page left the screen: another tab, another Space).
    @objc optional func enterPictureInPictureIfPlaying()
    /// The page's video comes back from its picture-in-picture window, if it is in one.
    @objc optional func exitPictureInPicture()
    /// Picture-in-picture on or off for the page's video (⌃⌘P).
    @objc optional func togglePictureInPicture()
    /// The developer tools docked in the page's area (right, left or bottom, chosen in
    /// the tools themselves), nil when they are closed or in their own window. They
    /// fill the area; the page goes where `pageFrame(withDevToolsIn:)` says.
    @objc optional var devToolsView: NSView? { get }
    /// Where the page goes in an area of `size` while its tools are docked, with a
    /// top-left origin.
    @objc optional func pageFrame(withDevToolsIn size: NSSize) -> NSRect
}

@objc(ChordWebPageDelegate) public protocol ChordWebPageDelegate: AnyObject {
    /// The URL, title, loading or navigation state changed.
    func pageDidUpdate(_ page: ChordWebPage)
    /// The page wants a link opened in a new tab (target=_blank, window.open).
    func page(_ page: ChordWebPage, wantsNewTabWith url: URL)
    /// The user clicked a link. Return false when ChordUI handled it elsewhere
    /// (a Peek, a background tab); the engine then cancels the navigation.
    @objc optional func page(_ page: ChordWebPage, shouldFollowLinkTo url: URL, modifiers: NSEvent.ModifierFlags) -> Bool

    /// A download started from the page, saved at `destination`. `id` names it in the
    /// calls that follow, and for `ChordWebEngine.cancelDownload(_:)`.
    @objc optional func page(_ page: ChordWebPage, didStartDownload id: String, destination: URL)
    /// Between 0 and 1.
    @objc optional func page(_ page: ChordWebPage, download id: String, didProgress fraction: Double)
    /// `fileURL` is nil when the download failed or was cancelled.
    @objc optional func page(_ page: ChordWebPage, download id: String, didFinishAt fileURL: URL?)
}
