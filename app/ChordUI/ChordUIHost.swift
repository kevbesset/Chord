import AppKit

/// ChordUI's entry point for the app that hosts it: Chromium (engine/chord).
///
/// The host owns `NSApplication` and its delegate; it hands ChordUI an engine and
/// forwards the few app events ChordUI cares about. Objective-C++ reaches it by name
/// (`NSClassFromString(@"ChordUIHost")`), so Chromium never links against Swift.
@objc(ChordUIHost)
public final class ChordUIHost: NSObject {
    private static var state: BrowserState?
    private static var windowController: BrowserWindowController?
    /// Links that arrived before the window existed.
    private static var pendingURLs: [URL] = []

    /// Installs the menu and opens the browser window. `supportDirectory` keeps the
    /// session (Spaces, tabs, folders).
    @objc(startWithEngine:appName:supportDirectory:)
    public static func start(engine: ChordWebEngine, appName: String, supportDirectory: URL) {
        guard windowController == nil else { return }
        let launch = Perf.begin("app.launch")
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenu.build(appName: appName)

        let state = BrowserState(engine: engine, store: SessionStore(directory: supportDirectory))
        let controller = BrowserWindowController(state: state, settings: ChordSettings())
        self.state = state
        windowController = controller
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            saveNow()
        }

        controller.showWindow(nil)
        NSApp.activate()
        pendingURLs.forEach { controller.openLittleWindow(url: $0) }
        pendingURLs = []
        DispatchQueue.main.async { launch.end() }
    }

    /// A link opened from another app (Chord set as the default browser) goes to a little
    /// window, like Little Arc.
    @objc(openURLs:)
    public static func open(_ urls: [URL]) {
        guard let controller = windowController else {
            pendingURLs += urls
            return
        }
        urls.forEach { controller.openLittleWindow(url: $0) }
    }

    /// The Dock icon was clicked: brings the browser window back.
    @objc public static func reopen() {
        windowController?.showWindow(nil)
        NSApp.activate()
    }

    /// The menu the host must keep installed (Chromium rebuilds its own at times).
    @objc public static var mainMenu: NSMenu? { NSApp.mainMenu }

    /// The browser window, which the engine's dialogs and file pickers attach to.
    @objc public static var mainWindow: NSWindow? { windowController?.window }

    @objc public static func saveNow() {
        state?.saveNow()
    }
}
