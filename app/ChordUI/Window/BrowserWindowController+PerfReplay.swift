import AppKit

/// The latency gate's replay (`engine/scripts/perf-gate.sh`): launched with
/// `CHORD_PERF_REPORT=<file>`, Chord plays every measured interaction a number of times,
/// writes how long each took next to its budget, and quits.
enum PerfReplay {
    static var reportURL: URL? {
        ProcessInfo.processInfo.environment["CHORD_PERF_REPORT"].map { URL(fileURLWithPath: $0) }
    }

    static var isActive: Bool { reportURL != nil }
}

extension BrowserWindowController {
    private typealias Step = (pause: TimeInterval, run: () -> Void)

    /// Plays the interactions one after the other, with a pause after each so that its
    /// interval ends and the window settles, as a person's actions would.
    func runPerfReplay(report: URL) {
        if commandBar.isVisible { commandBar.dismiss() }
        let page = URL(string: "data:text/html,<title>Chord</title><h1>Chord</h1><p>" + String(repeating: "Lorem ipsum dolor sit amet. ", count: 200) + "</p>")!
        var steps: [Step] = []
        func repeatStep(_ times: Int, pause: TimeInterval = 0.25, _ run: @escaping () -> Void) {
            steps += Array(repeating: (pause, run), count: times)
        }

        // A few tabs to move between, and time for their pages to load.
        repeatStep(5, pause: 0.3) { [weak self] in self?.state.openTab(url: page) }
        steps.append((2, {}))
        repeatStep(10) { [weak self] in
            guard let self else { return }
            if self.commandBar.isVisible { self.commandBar.dismiss() } else { self.newTab(nil) }
        }
        repeatStep(10) { [weak self] in self?.toggleSidebarVisibility(nil) }
        var tabIndex = 0
        repeatStep(10) { [weak self] in
            guard let self else { return }
            let tabs = self.state.activeSpace.today
            guard !tabs.isEmpty else { return }
            tabIndex += 1
            self.sidebarSelect(tabs[tabIndex % tabs.count])
        }
        repeatStep(6, pause: 0.6) { [weak self] in self?.nextSpace(nil) }
        repeatStep(6, pause: 0.6) { [weak self] in
            guard let self else { return }
            if self.peek.isVisible { self.peek.dismiss() } else { self.presentPeek(page) }
        }
        repeatStep(6, pause: 0.4) { [weak self] in
            guard let self else { return }
            if self.commandBar.isVisible { self.commandBar.dismiss() } else { self.toggleSplitView(nil) }
        }
        repeatStep(6) { [weak self] in
            guard let self else { return }
            if self.pageArea.findBar.isHidden { self.showFindBar(nil) } else { self.closeFindBar(focusPage: true) }
        }
        repeatStep(6, pause: 0.6) { [weak self] in
            guard let self else { return }
            if let little = self.littleWindows.last { little.window?.close() } else { self.openLittleWindow(url: page) }
        }

        func next(_ index: Int) {
            guard index < steps.count else {
                finishPerfReplay(report: report)
                return
            }
            steps[index].run()
            DispatchQueue.main.asyncAfter(deadline: .now() + steps[index].pause) { next(index + 1) }
        }
        // After the launch's own work.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { next(0) }
    }

    private func finishPerfReplay(report: URL) {
        let result: [String: Any] = ["budgets": Perf.budgets, "measurements": Perf.recorded ?? [:]]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: report)
        }
        Perf.recorded = nil
        NSApp.terminate(nil)
    }
}
