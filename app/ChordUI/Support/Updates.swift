import AppKit
import Sparkle

/// Chord's own updates (Sparkle), in the builds that say where to find them:
/// engine/scripts/package.sh writes the feed and its public key into Info.plist.
///
/// Like Arc: Chord checks on its own (at launch, then every hour) and, as soon as a new
/// version is found, a button above the Spaces offers it while it downloads in the
/// background. A click installs it and restarts Chord on it, waiting for the download to
/// finish if needed. Left alone, it installs at the next quit.
final class Updates: NSObject, SPUUpdaterDelegate {
    static let shared = Updates()
    /// Posted when `state` changes.
    static let stateNotification = Notification.Name("ChordUpdateState")

    enum State: Equatable {
        /// Found, downloading in the background.
        case available(version: String)
        /// Asked to install while still downloading: installs as soon as it is ready.
        case downloading(version: String)
        /// Downloaded: a click restarts Chord on it.
        case ready(version: String)
    }

    private var controller: SPUStandardUpdaterController?
    /// The new version of Chord, if there is one.
    private(set) var state: State? {
        didSet {
            guard state != oldValue else { return }
            NotificationCenter.default.post(name: Self.stateNotification, object: self)
        }
    }
    private var installNow: (() -> Void)?

    /// Starts checking; "Check for Updates…" checks now. Without a feed (development
    /// builds) the item is hidden.
    func start(menu: NSMenu) {
        let check = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        guard Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            MainMenu.items(with: [check], in: menu).forEach { $0.isHidden = true }
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        // Every hour (Sparkle's minimum) rather than every day: a new version shows
        // within the hour, and at launch when the last check is older than that.
        controller.updater.updateCheckInterval = 60 * 60
        controller.startUpdater()
        MainMenu.setTarget(controller, for: [check], in: menu)
        self.controller = controller
    }

    /// Installs the new version and relaunches Chord on it: now if it is downloaded, as
    /// soon as it is otherwise. Without a download under way (it failed, or automatic
    /// downloads are off), Sparkle's own window takes over.
    func installAndRelaunch() {
        guard let state, let controller else { return }
        switch state {
        case .ready:
            installNow?()
        case .available(let version) where controller.updater.sessionInProgress:
            self.state = .downloading(version: version)
        case .available, .downloading:
            controller.checkForUpdates(nil)
        }
    }

    // MARK: - SPUUpdaterDelegate

    /// A new version: its button shows now, before it is downloaded.
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        if case .ready = state { return }
        if case .downloading = state { return }
        state = .available(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        if case .ready = state { return }
        state = nil
    }

    /// The new version is downloaded: installs it now if asked, otherwise at the quit
    /// unless the button is clicked first.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        installNow = immediateInstallHandler
        if case .downloading = state {
            DispatchQueue.main.async(execute: immediateInstallHandler)
            return true
        }
        state = .ready(version: item.displayVersionString)
        return true
    }

    /// "Skip This Version" in Sparkle's window: no button for it.
    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                 forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        if choice == .skip, installNow == nil { self.state = nil }
    }

    /// A background download that ended without the new version ready (it failed, or it
    /// cannot install silently and Sparkle shows its own window): the button stays, and if
    /// it was clicked after a failure, Sparkle's window says what happened and can retry.
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard case .downloading(let version) = state else { return }
        state = .available(version: version)
        guard error != nil else { return }
        DispatchQueue.main.async { [weak self] in self?.controller?.checkForUpdates(nil) }
    }
}
