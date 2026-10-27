import AppKit
import Combine

// Site questions (permissions, passwords) and extensions.
extension BrowserWindowController {
    // MARK: - Permission prompts

    /// A site's question, from the window that shows its page. For the selected page it
    /// hangs from the site controls, like Arc's, and a closed sidebar comes back floating
    /// to hold it; for another page (a split pane, a Peek), from the top of the page.
    func presentPermission(_ ask: PermissionAsk) {
        if let little = littleWindows.first(where: { $0.shows(ask.page) }) {
            little.presentPermission(ask.request)
            return
        }
        guard let window, ask.page.view.window === window else { return }
        if ask.page === state.selectedTab?.page, !addressBarOnTop, sidebarMode == .hidden {
            setSidebarMode(.floating, animated: true)
            // Once the sidebar has slid in, so that the question appears where it stays.
            DispatchQueue.main.asyncAfter(deadline: .now() + Theme.motionDuration) { [weak self] in
                self?.showPermission(ask)
            }
            return
        }
        showPermission(ask)
    }

    func showPermission(_ ask: PermissionAsk) {
        let anchor = permissionAnchor(for: ask.page)
        permissionPrompt.present(ask.request, for: ask.page, from: anchor.view, rect: anchor.rect)
    }

    /// The selected page's site controls when they are on screen, else the top of the page.
    func permissionAnchor(for page: ChordWebPage) -> (view: NSView, rect: NSRect?) {
        if page === state.selectedTab?.page {
            if addressBarOnTop {
                let button = pageArea.toolbar.siteControlsAnchor
                if button.window != nil, !button.isHiddenOrHasHiddenAncestor { return (button, nil) }
            } else if sidebarMode != .hidden {
                sidebar.pinsAddressButtons = true
                sidebar.layoutSubtreeIfNeeded()
                return (sidebar.siteControlsAnchor, nil)
            }
        }
        return (page.view, PermissionPromptController.pageTop(of: page.view))
    }

    /// The question follows its anchor when the sidebar or the address bar moves.
    func reanchorPermissionPrompt() {
        guard permissionPrompt.isVisible else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.motionDuration) { [weak self] in
            guard let self, self.permissionPrompt.isVisible, let page = self.permissionPrompt.page else { return }
            let anchor = self.permissionAnchor(for: page)
            // The page may have left this window while the layout moved.
            guard anchor.view.window === self.window else { return }
            self.permissionPrompt.reanchor(to: anchor.view, rect: anchor.rect)
        }
    }

    func resumePermissionPrompt() {
        guard permissionPrompt.isSuspended, let page = permissionPrompt.page else { return }
        let anchor = permissionAnchor(for: page)
        permissionPrompt.resume(from: anchor.view, rect: anchor.rect)
    }

    func permissionPromptClosed() {
        sidebar.pinsAddressButtons = false
        // A sidebar that came out for the question goes away again, unless the pointer is in it.
        if sidebarMode == .floating, let window,
           !sidebar.bounds.contains(sidebar.convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
            scheduleHide()
        }
    }

    // MARK: - Extensions

    /// What extensions' buttons do, in the address fields and the site card: always on
    /// the selected page.
    func makeExtensionActions() -> ExtensionActions {
        ExtensionActions(
            run: { [weak self] item, anchor in self?.runExtension(item, from: anchor) },
            setPinned: { [weak self] item, pinned in self?.state.selectedTab?.page?.setExtension?(item.id, pinned: pinned) },
            open: { [weak self] url in self?.state.openTab(url: url) },
            uninstall: { [weak self] item in self?.confirmUninstall(item) }
        )
    }

    /// The pinned extensions of the selected page, with its badges, in the address.
    func updateExtensions() {
        let pinned = PageExtension.all(of: state.selectedTab?.page).filter(\.isPinned)
        sidebar.setExtensions(pinned)
        pageArea.toolbar.setExtensions(pinned)
    }

    /// Like a click on the extension's button in Chrome: it acts on the selected page,
    /// and its popup, if it has one, hangs from `anchor`.
    func runExtension(_ item: PageExtension, from anchor: NSView) {
        guard let page = state.selectedTab?.page else { return }
        page.didBecomeActive?()
        guard let popup = page.runExtension?(item.id) else { return }
        // The sidebar's buttons stay while the popup hangs from one of them.
        if anchor.isDescendant(of: sidebar) { sidebar.pinsAddressButtons = true }
        pendingHide?.cancel()
        extensionPopup.show(popup, from: anchor)
    }

    func extensionPopupClosed() {
        if !permissionPrompt.isVisible { sidebar.pinsAddressButtons = false }
        if sidebarMode == .floating, let window,
           !sidebar.bounds.contains(sidebar.convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
            scheduleHide()
        }
        focusPage()
    }

    func confirmUninstall(_ item: PageExtension) {
        guard let window, let page = state.selectedTab?.page else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Remove “\(item.name)”?", bundle: .chordUI)
        alert.informativeText = String(localized: "The extension and its data are removed from this profile.", bundle: .chordUI)
        alert.addButton(withTitle: String(localized: "Remove", bundle: .chordUI))
        alert.addButton(withTitle: String(localized: "Cancel", bundle: .chordUI))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            page.uninstallExtension?(item.id)
        }
    }
}
