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
    /// The engine of another of ChordUI's profiles, made on first use. Like Arc's
    /// profiles, each keeps its own session (cookies, storage, history, extensions);
    /// this engine's own profile is ChordUI's default one. Its pages may load a moment
    /// later, while the profile opens.
    @objc optional func engine(forProfile profileID: String) -> ChordWebEngine
    /// Deletes another profile no Space uses any more, its data and its folder (some of
    /// it at the next launch, for a profile that was open). Its pages are closed.
    @objc optional func deleteProfile(_ profileID: String)
    /// Deletes ChordUI's other profiles that are not among `profileIDs`.
    @objc(deleteProfilesExcept:) optional func deleteProfiles(except profileIDs: [String])
    /// Deletes everything the browser keeps (every profile, ChordUI's session, settings
    /// and caches) and restarts it as new. The deletion happens as it starts again.
    @objc optional func resetAllDataAndRelaunch()
    /// Pages from this engine's profile history and bookmarks for what is typed in the
    /// command bar, best first: "url", "title", and "isTopHit" ("1" when it completes the
    /// text, like the omnibox's inline completion). `completion` may come several times
    /// as more arrive, until the next call. An empty text ends the search.
    @objc optional func suggest(_ text: String, completion: @escaping ([[String: String]]) -> Void)
    /// Brings one of Arc's profiles ("…/Arc/User Data/Profile 1") into this engine's
    /// profile: logins (cookies), passwords, history and the values typed in forms now,
    /// site storage at the next launch, its extensions from the Chrome Web Store
    /// (installed again, their data at the next launch). macOS asks the user for Arc's
    /// key. `completion` gets the counts: "cookies", "passwords", "pages",
    /// "formValues", "extensions", "siteStorage" (1 when
    /// some comes next launch) and "keyDenied" (1 when macOS did not give Arc's key).
    @objc optional func importFromArc(_ arcProfile: String, completion: @escaping ([String: Int]) -> Void)
    /// Whether the page belongs to this engine's profile.
    @objc optional func ownsPage(_ page: ChordWebPage) -> Bool
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
    /// The page's site asks for permissions (camera, notifications…). ChordUI shows the
    /// question while the page is on screen and answers it once.
    @objc optional func engine(_ engine: ChordWebEngine, page: ChordWebPage, requests request: ChordPermissionRequest)
    /// The engine's extensions changed: added, removed, pinned, a badge or an icon.
    @objc optional func engineExtensionsDidChange(_ engine: ChordWebEngine)
}

/// An extension's popup, from its button. ChordUI shows `view` at `preferredSize`,
/// which the popup's content decides.
@objc(ChordExtensionPopup) public protocol ChordExtensionPopup: AnyObject {
    var view: NSView { get }
    var preferredSize: NSSize { get }
    /// The content loaded, or changed size.
    var onResize: (() -> Void)? { get set }
    /// The popup closed itself (`window.close()`).
    var onClose: (() -> Void)? { get set }
    /// ChordUI closed it.
    func close()
}

/// A site's request for permissions, answered once with `allow()`, `block()` or
/// `dismiss()` (no decision: the site may ask again later).
@objc(ChordPermissionRequest) public protocol ChordPermissionRequest: AnyObject {
    /// The site's host.
    var site: String { get }
    /// What the site asks for, as the engine words it ("Use your cameras").
    var asks: [String] { get }
    /// An SF Symbol for the first thing asked.
    var symbol: String { get }
    /// A question of the browser's own rather than a site's permission (save a
    /// password), worded in full: shown instead of "Allow
    /// <site> to …?".
    @objc optional var question: String? { get }
    /// A quieter line under the question: the account a password is for.
    @objc optional var detail: String? { get }
    /// The buttons' titles when they are not "Allow", "Block" and "Not Now". An empty
    /// block title leaves that button out.
    @objc optional var allowTitle: String? { get }
    @objc optional var blockTitle: String? { get }
    @objc optional var dismissTitle: String? { get }
    /// Set by ChordUI: the request went away unanswered (another tab was selected, the
    /// tab closed). The engine asks again when it comes back.
    var onCancel: (() -> Void)? { get set }
    func allow()
    func block()
    func dismiss()
}

@objc(ChordWebPage) public protocol ChordWebPage: AnyObject {
    /// The view that renders the page. ChordUI places it inside the content card.
    var view: NSView { get }
    var url: URL? { get }
    var title: String? { get }
    var isLoading: Bool { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    /// The page's own icon (PNG), as declared by the page and rendered by the engine
    /// (best size for the sidebar), once known. Nil while another page loads.
    @objc optional var faviconData: Data? { get }
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
    /// What the page's site may do for a permission, by the engine's name for it
    /// ("notifications", "media_stream_camera"…): "allow", "block" or "ask"; nil when
    /// the engine does not know it for this page.
    @objc optional func permissionState(_ permission: String) -> String?
    /// Changes what the page's site may do; "default" goes back to the browser's choice.
    @objc optional func setPermission(_ permission: String, state: String)
    /// The site's permissions worth showing: notifications, then every one chosen for
    /// this site rather than left to the browser's default. Each has an "id" (as above),
    /// a "title" in the browser's language and a "state".
    @objc optional var sitePermissions: [[String: String]] { get }
    /// The extensions with a button (a toolbar button in Chrome), as this page sees
    /// them (badges are per tab), pinned ones first. Each: "id", "name", "icon"
    /// (NSImage), "badge", "badgeColor" (NSColor), "pinned" (Bool), "options" (a URL).
    @objc optional var extensions: [[String: Any]] { get }
    /// Runs the extension's action on this page, as a click on its button: returns its
    /// popup for ChordUI to show, or nil when the action shows none.
    @objc optional func runExtension(_ id: String) -> ChordExtensionPopup?
    /// Pins the extension's button in the address field, or takes it out.
    @objc optional func setExtension(_ id: String, pinned: Bool)
    @objc optional func uninstallExtension(_ id: String)

    /// Finds `text` in the page (⌘F), highlighting every match: the next match, or the
    /// previous one when `forward` is false. The same text again moves to the next
    /// match. Results come through `page(_:didFindMatches:activeMatch:isFinal:)`.
    @objc(find:forward:) optional func find(_ text: String, forward: Bool)
    /// Ends the search; the current match stays selected.
    @objc optional func stopFinding()

    /// Zooms the page in (1), out (-1) or back to its actual size (0). The engine keeps
    /// the level for the site.
    @objc optional func zoom(_ direction: Int)
    /// The page's zoom, in percent.
    @objc optional var zoomPercent: Int { get }
    /// Shows the system's print dialog for the page (⌘P).
    @objc optional func printPage()

    /// The page plays sound right now.
    @objc optional var isAudible: Bool { get }
    @objc optional var isMuted: Bool { get }
    @objc optional func setMuted(_ muted: Bool)
    /// The page uses the camera or the microphone, or records the screen.
    @objc optional var isCapturingMedia: Bool { get }

    /// Puts the page to sleep: its process goes, its history, scroll position and form
    /// state stay, and it loads again where it was on `wake()`. False when it could not
    /// (its video is in picture in picture, its developer tools are open).
    @objc optional func sleep() -> Bool
    /// The page sleeps (put to sleep by ChordUI or by the engine, short of memory).
    @objc optional var isAsleep: Bool { get }
    @objc optional func wake()
}

@objc(ChordWebPageDelegate) public protocol ChordWebPageDelegate: AnyObject {
    /// The URL, title, loading or navigation state changed.
    func pageDidUpdate(_ page: ChordWebPage)
    /// The page wants a link opened in a new tab (target=_blank, window.open).
    func page(_ page: ChordWebPage, wantsNewTabWith url: URL)
    /// The user clicked a link. Return false when ChordUI handled it elsewhere
    /// (a Peek, a background tab); the engine then cancels the navigation.
    @objc optional func page(_ page: ChordWebPage, shouldFollowLinkTo url: URL, modifiers: NSEvent.ModifierFlags) -> Bool
    /// What a search found: `count` matches, the `activeMatch`th selected (from 1, 0
    /// when none). `isFinal` once the count is complete.
    @objc(page:didFindMatches:activeMatch:isFinal:) optional func page(_ page: ChordWebPage, didFindMatches count: Int, activeMatch: Int, isFinal: Bool)

    /// A download started from the page, saved at `destination`. `id` names it in the
    /// calls that follow, and for `ChordWebEngine.cancelDownload(_:)`.
    @objc optional func page(_ page: ChordWebPage, didStartDownload id: String, destination: URL)
    /// Between 0 and 1.
    @objc optional func page(_ page: ChordWebPage, download id: String, didProgress fraction: Double)
    /// `fileURL` is nil when the download failed or was cancelled.
    @objc optional func page(_ page: ChordWebPage, download id: String, didFinishAt fileURL: URL?)
}
