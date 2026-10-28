import AppKit
import Sparkle

/// Chord's own updates (Sparkle), in the builds that say where to find them:
/// engine/scripts/package.sh writes the feed and its public key into Info.plist.
///
/// Like Arc: updates are checked and downloaded in the background, then a button above
/// the Spaces offers to restart into the new version. Left alone, it installs at the
/// next quit.
final class Updates: NSObject, SPUUpdaterDelegate {
    static let shared = Updates()
    /// Posted when a downloaded update is ready to install (`readyVersion` is set).
    static let readyNotification = Notification.Name("ChordUpdateReady")

    private var controller: SPUStandardUpdaterController?
    /// The version downloaded and waiting to be installed, if any.
    private(set) var readyVersion: String?
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
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        MainMenu.setTarget(controller, for: [check], in: menu)
        self.controller = controller
    }

    /// Installs the waiting update and relaunches Chord on it.
    func installAndRelaunch() {
        installNow?()
    }

    // MARK: - SPUUpdaterDelegate

    /// A silent update is downloaded: Chord offers it rather than waiting for the quit.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        readyVersion = item.displayVersionString
        installNow = immediateInstallHandler
        NotificationCenter.default.post(name: Self.readyNotification, object: self)
        return true
    }
}
