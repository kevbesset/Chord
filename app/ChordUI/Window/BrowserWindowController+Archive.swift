import AppKit

// The archive of today's tabs: its panel, from the sidebar or the Tabs menu.
extension BrowserWindowController {
    /// Opens the archive's panel above its button in the sidebar, or at the window's
    /// bottom left corner when the sidebar is hidden. Again, it closes.
    @objc public func showArchive(_ sender: Any?) {
        if archivePopover.isShown {
            archivePopover.performClose(nil)
            return
        }
        if sidebarMode == .hidden {
            let corner = NSRect(x: 12, y: 12, width: 1, height: 1)
            archivePopover.show(relativeTo: corner, of: rootView, preferredEdge: .maxY)
        } else {
            let anchor = sidebar.archiveAnchor
            archivePopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        }
    }

    var archivePanel: ArchivePanelController? {
        archivePopover.contentViewController as? ArchivePanelController
    }

    func makeArchivePopover() -> NSPopover {
        let panel = ArchivePanelController(state: state)
        panel.onRestore = { [weak self] archived in
            self?.archivePopover.performClose(nil)
            self?.state.restore(archived)
        }
        panel.onClear = { [weak self] in self?.state.clearArchive() }
        let popover = NSPopover()
        popover.contentViewController = panel
        popover.behavior = .transient
        popover.animates = true
        return popover
    }
}
