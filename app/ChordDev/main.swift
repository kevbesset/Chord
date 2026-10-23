import AppKit

// ChordDev hosts ChordUI on a WebKit stand-in engine, for fast UI work.
// In the real browser, Chromium owns NSApplication and ChordUI is loaded into it.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = app.setActivationPolicy(.regular)
app.run()
