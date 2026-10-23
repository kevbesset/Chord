import AppKit
import ChordUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: BrowserState?
    private var windowController: BrowserWindowController?
    /// Links that arrived before the window existed.
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launch = Perf.begin("app.launch")
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenu.build(appName: "Chord Dev")

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chord Dev", isDirectory: true)
        let state = BrowserState(engine: WebKitEngine(), store: SessionStore(directory: support))
        let controller = BrowserWindowController(state: state, settings: ChordSettings())
        self.state = state
        self.windowController = controller

        controller.showWindow(nil)
        NSApp.activate()
        pendingURLs.forEach { controller.openLittleWindow(url: $0) }
        pendingURLs = []
        DispatchQueue.main.async { launch.end() }
    }

    /// A link opened from another app (Chord set as the default browser) goes to a little
    /// window, like Little Arc.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller = windowController else {
            pendingURLs += urls
            return
        }
        urls.forEach { controller.openLittleWindow(url: $0) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        state?.saveNow()
    }
}
