import AppKit

// The first launch's welcome (see `WelcomeView`).
extension BrowserWindowController {
    func showWelcome() {
        guard welcomeView == nil else { return }
        settings.welcomeShown = true
        settings.arcImportOffered = true
        let welcome = WelcomeView()
        welcome.onImportArc = { [weak self] in
            self?.closeWelcome(thenOpenTab: false)
            self?.importFromArc(nil)
        }
        welcome.onImportBrowser = { [weak self] source in
            self?.closeWelcome(thenOpenTab: false)
            self?.importBrowser(source)
        }
        welcome.onDone = { [weak self] in self?.closeWelcome(thenOpenTab: true) }
        welcome.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(welcome)
        NSLayoutConstraint.activate([
            welcome.topAnchor.constraint(equalTo: rootView.topAnchor),
            welcome.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            welcome.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            welcome.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
        // No fade: an animation that does not run (a window in the background) would
        // leave a transparent panel catching every click.
        welcomeView = welcome
    }

    /// Closes the welcome; with nothing open, the command bar comes next.
    func closeWelcome(thenOpenTab: Bool) {
        guard let welcome = welcomeView else { return }
        welcomeView = nil
        welcome.removeFromSuperview()
        if thenOpenTab, state.activeSpace.allTabs.isEmpty, state.favorites.isEmpty { newTab(nil) }
    }
}
