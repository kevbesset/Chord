import AppKit
import Sparkle

/// ChordUI's entry point for the app that hosts it: Chromium (engine/chord).
///
/// The host owns `NSApplication` and its delegate; it hands ChordUI an engine and
/// forwards the few app events ChordUI cares about. Objective-C++ reaches it by name
/// (`NSClassFromString(@"ChordUIHost")`), so Chromium never links against Swift.
@objc(ChordUIHost)
public final class ChordUIHost: NSObject {
    private static var engine: ChordWebEngine?
    private static var state: BrowserState?
    /// The browser windows, normal and private, in the order they opened.
    private static var windowControllers: [BrowserWindowController] = []
    /// The target of the menu items that work without any window (⌘N, ⇧⌘N).
    private static let appActions = AppActions()
    /// Links that arrived before the window existed.
    private static var pendingURLs: [URL] = []
    /// Chord's own updates, in the builds that say where to find them:
    /// engine/scripts/package.sh writes the feed and its public key into Info.plist.
    private static var updater: SPUStandardUpdaterController?

    /// Installs the menu and opens the browser window. `supportDirectory` keeps the
    /// session (Spaces, tabs, folders).
    @objc(startWithEngine:appName:supportDirectory:)
    public static func start(engine: ChordWebEngine, appName: String, supportDirectory: URL) {
        guard state == nil else { return }
        let launch = Perf.begin("app.launch")
        NSWindow.allowsAutomaticWindowTabbing = false
        let menu = MainMenu.build(appName: appName)
        MainMenu.setTarget(appActions, for: [#selector(AppActions.newWindow(_:)), #selector(AppActions.newPrivateWindow(_:)),
                                          #selector(AppActions.makeDefaultBrowser(_:))], in: menu)
        startUpdater(menu: menu)
        NSApp.mainMenu = menu

        self.engine = engine
        state = BrowserState(engine: engine, store: SessionStore(directory: supportDirectory))
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            saveNow()
        }

        let controller = openWindow()
        NSApp.activate()
        // After a crash: a readable report in ~/Library/Logs/Chord, offered to the user.
        CrashReports.checkForCrash(appName: appName, over: controller.window)
        pendingURLs.forEach { controller.openLittleWindow(url: $0) }
        pendingURLs = []
        DispatchQueue.main.async { launch.end() }
    }

    /// Checks for updates in the background and installs them at the next launch, as Arc
    /// does; "Check for Updates…" checks now. Without a feed (development
    /// builds) the item is hidden.
    private static func startUpdater(menu: NSMenu) {
        let check = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        guard Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            MainMenu.items(with: [check], in: menu).forEach { $0.isHidden = true }
            return
        }
        let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        MainMenu.setTarget(updater, for: [check], in: menu)
        self.updater = updater
    }

    /// A new browser window on the shared Spaces (⌘N), next to the current one.
    @discardableResult
    static func openWindow() -> BrowserWindowController {
        guard let state else { fatalError("ChordUIHost.start(engine:…) comes first") }
        let controller = BrowserWindowController(state: state, settings: ChordSettings(), cascadingFrom: currentWindow?.window)
        show(controller)
        return controller
    }

    /// A private browsing window (⇧⌘N): the engine's private profile, its own tabs,
    /// nothing saved.
    static func openPrivateWindow() {
        guard let privateEngine = engine?.makePrivateEngine?() else { return }
        let state = BrowserState(engine: privateEngine, store: nil, isPrivate: true)
        show(BrowserWindowController(state: state, settings: ChordSettings(), cascadingFrom: currentWindow?.window))
    }

    private static func show(_ controller: BrowserWindowController) {
        controller.onClose = { closed in
            // Let it go once AppKit is done closing it.
            DispatchQueue.main.async { windowControllers.removeAll { $0 === closed } }
        }
        windowControllers.append(controller)
        controller.showWindow(nil)
    }

    /// The window the user is in, else the last one opened.
    private static var currentWindow: BrowserWindowController? {
        windowControllers.first { $0.window?.isMainWindow == true }
            ?? windowControllers.last { $0.window?.isVisible == true }
    }

    /// A link opened from another app (Chord set as the default browser) goes to a little
    /// window, like Little Arc.
    @objc(openURLs:)
    public static func open(_ urls: [URL]) {
        guard let controller = currentWindow ?? windowControllers.last else {
            pendingURLs += urls
            return
        }
        urls.forEach { controller.openLittleWindow(url: $0) }
    }

    /// The Dock icon was clicked: brings the browser window back, or opens one.
    @objc public static func reopen() {
        guard state != nil else { return }
        if let controller = currentWindow ?? windowControllers.last {
            controller.showWindow(nil)
        } else {
            openWindow()
        }
        NSApp.activate()
    }

    /// The menu the host must keep installed (Chromium rebuilds its own at times).
    @objc public static var mainMenu: NSMenu? { NSApp.mainMenu }

    /// The browser window, which the engine's dialogs and file pickers attach to.
    @objc public static var mainWindow: NSWindow? { currentWindow?.window }

    @objc public static func saveNow() {
        state?.saveNow()
    }
}

/// Menu actions that need no window: they open one.
private final class AppActions: NSObject, NSMenuItemValidation {
    @objc func newWindow(_ sender: Any?) { ChordUIHost.openWindow() }
    @objc func newPrivateWindow(_ sender: Any?) { ChordUIHost.openPrivateWindow() }
    @objc func makeDefaultBrowser(_ sender: Any?) { DefaultBrowser.makeChord { _ in } }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(makeDefaultBrowser(_:)) || !DefaultBrowser.isChord
    }
}
