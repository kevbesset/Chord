import AppKit

// A page element in full screen (a video): the engine puts the window in full screen,
// and the window shows that page alone, without sidebar, toolbar or margins, until the
// page leaves full screen.
extension BrowserWindowController {
    func updatePageFullscreen() {
        let tab = state.visibleTabs.first { $0.page?.isFullscreen == true }
        guard tab !== fullscreenTab else { return }
        fullscreenTab = tab
        if tab != nil {
            if sidebarModeBeforeFullscreen == nil { sidebarModeBeforeFullscreen = sidebarMode }
            commandBar.dismiss()
            if peek.isVisible { peek.dismiss() }
            setSidebarMode(.hidden, animated: false)
            // No floating sidebar from the screen's edge while the video plays.
            edgeHover.isHidden = true
        } else if let previous = sidebarModeBeforeFullscreen {
            sidebarModeBeforeFullscreen = nil
            // A sidebar floating when the video went full screen comes back hidden.
            setSidebarMode(previous == .docked ? .docked : .hidden, animated: false)
            edgeHover.isHidden = sidebarMode != .hidden
        }
        applyAppearanceSettings(animated: false)
    }

    /// The engine's words for leaving full screen ("Press esc to exit full screen").
    func showNotice(_ text: String) {
        notice.show(text, symbol: "escape", in: rootView, over: pageArea, accent: .secondaryLabelColor)
    }
}
