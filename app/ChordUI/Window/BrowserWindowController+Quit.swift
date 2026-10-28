import AppKit

// ⌘Q's question (see `QuitConfirmationView`).
extension BrowserWindowController {
    /// Whether the question can go over this window: on screen, with no sheet in the way.
    var canAskToQuit: Bool {
        guard let window else { return false }
        return window.isVisible && !window.isMiniaturized && window.attachedSheet == nil
    }

    /// Asks over this window whether to quit; `completion` gets the answer. Asked again
    /// while it shows (⌘Q twice), it quits.
    func askToQuit(_ completion: @escaping (QuitConfirmationView.Answer) -> Void) {
        if let shown = quitConfirmation {
            closeQuitConfirmation(shown, restoring: nil)
            completion(.quit)
            return
        }
        let interval = Perf.begin("quit.confirm")
        let previousResponder = window?.firstResponder
        let view = QuitConfirmationView(accent: state.activeSpace.accent)
        view.onAnswer = { [weak self, weak view] answer in
            guard let self, let view else { return }
            self.closeQuitConfirmation(view, restoring: answer == .cancel ? previousResponder : nil)
            completion(answer)
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: rootView.topAnchor),
            view.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
        quitConfirmation = view
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(view)
        rootView.layoutSubtreeIfNeeded()
        view.appear()
        DispatchQueue.main.async { interval.end() }
    }

    private func closeQuitConfirmation(_ view: QuitConfirmationView, restoring responder: NSResponder?) {
        quitConfirmation = nil
        view.removeFromSuperview()
        // Cancelled: the focus goes back where it was (the page, the command bar…).
        if let previous = responder as? NSView, previous.window === window {
            window?.makeFirstResponder(previous)
        } else if responder != nil {
            focusPage()
        }
    }
}
