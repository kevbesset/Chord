import AppKit
import Combine

// MARK: - Sidebar

extension BrowserWindowController: SidebarDelegate {
    func sidebarGoBack() { goBack(nil) }
    func sidebarGoForward() { goForward(nil) }
    func sidebarReload() { reloadOrStop() }
    func sidebarToggle() { toggleSidebarVisibility(nil) }
    func sidebarAddressClicked() { openLocation(nil) }
    func sidebarNewTab() { newTab(nil) }

    func sidebarSelect(_ tab: Tab) {
        let interval = Perf.begin("tab.select")
        state.select(tab)
        DispatchQueue.main.async { interval.end() }
    }

    func sidebarClose(_ tab: Tab) { state.close(tab) }
    func sidebarToggleMute(_ tab: Tab) { state.toggleMute(tab) }
    func sidebarTogglePin(_ tab: Tab) { state.togglePin(tab) }
    func sidebarToggleFavorite(_ tab: Tab) { state.toggleFavorite(tab) }
    func sidebarSplit(_ tab: Tab) { state.addToSplit(tab) }
    func sidebarRemoveFromSplit(_ tab: Tab) { state.removeFromSplit(tab) }
    func sidebarCopyURL(_ tab: Tab) { copy(tab.url) }
    func sidebarCopyAddress() { copyURL(nil) }
    func sidebarShowSiteControls(from anchor: NSView) { showSiteControls(from: anchor) }
    func sidebarTab(withID id: UUID) -> Tab? { state.tab(withID: id) }
    // Drops and swipes can reach a window that is not the key one: they act with its
    // own selection.
    func sidebarMove(_ tab: Tab, to destination: TabDestination) {
        state.withWindow(selection) { state.move(tab, to: destination) }
    }
    func sidebarMove(_ tab: Tab, toSpace space: Space) {
        state.withWindow(selection) { state.move(tab, to: .today(0), in: space) }
    }
    func sidebarMove(_ folder: Folder, into parent: Folder?, at index: Int) {
        state.withWindow(selection) { state.move(folder, into: parent, at: index) }
    }

    func sidebarOpen(_ urls: [URL], at destination: TabDestination) {
        state.withWindow(selection) { openDropped(urls, at: destination) }
    }

    func openDropped(_ urls: [URL], at destination: TabDestination) {
        for (offset, url) in urls.enumerated() {
            switch destination {
            case .favorites(let index): state.insertTab(url: url, at: .favorites(index + offset))
            case .pinned(let folder, let index): state.insertTab(url: url, at: .pinned(folder, index + offset))
            case .today(let index): state.insertTab(url: url, at: .today(index + offset))
            }
        }
    }

    func sidebarNewFolder(with tab: Tab?) {
        promptRename(state.newFolder(with: tab))
    }

    func sidebarRename(_ folder: Folder) { promptRename(folder) }
    func sidebarUngroup(_ folder: Folder) { state.ungroup(folder) }
    func sidebarDelete(_ folder: Folder) { confirmDelete(folder) }
    func sidebarSetExpanded(_ folder: Folder, _ expanded: Bool) { state.setExpanded(folder, expanded) }

    func sidebarSelectSpace(_ space: Space) { state.selectSpace(space) }
    func sidebarAddSpace() { newSpace(nil) }
    func sidebarRename(_ space: Space) { promptRename(space) }
    func sidebarSetColor(_ space: Space, hex: String) { state.setColor(space, hex: hex) }
    func sidebarDelete(_ space: Space) { confirmDelete(space) }
    /// The window's tint follows the swipe from one Space's colour to the other's.
    func sidebarSwipeProgress(toward space: Space?, fraction: CGFloat) {
        guard let space else { return }
        setTint(state.activeSpace.color.blended(withFraction: fraction, of: space.color) ?? space.color)
    }

    func sidebarSwipeWillEnd(on space: Space?, duration: TimeInterval) {
        setTint((space ?? state.activeSpace).color, duration: duration)
    }

    func sidebarSwipeEnded(on space: Space?) {
        guard let space else { return }
        isEndingSwipe = true
        state.withWindow(selection) { state.selectSpace(space) }
        isEndingSwipe = false
    }

    func sidebarResize(to width: CGFloat, finished: Bool) {
        sidebarWidth.constant = width
        if finished { settings.sidebarWidth = width }
    }

    func sidebarShowDownloads() { showDownloads(nil) }
    func sidebarInstallUpdate() { Updates.shared.installAndRelaunch() }
    func sidebarSetIcon(_ space: Space, icon: String?) { state.setIcon(space, icon: icon) }
    func sidebarChooseIcon(_ space: Space) { promptIcon(for: space) }
    func sidebarToggleMediaPlayback(_ tab: Tab) { state.toggleMediaPlayback(tab) }
    func sidebarMouseEntered() { pendingHide?.cancel() }
    func sidebarMouseExited() { scheduleHide() }
}
