import Cocoa
import Sparkle

class UserDefaultsEvents: NSObject {
    private static var policyObserver = UserDefaultsEvents()
    private static var updatesTab: UpdatesTab!

    static func observe(_ updatesTab: UpdatesTab) {
        UserDefaultsEvents.updatesTab = updatesTab
        UserDefaults.standard.addObserver(policyObserver, forKeyPath: "SUAutomaticallyUpdate", options: [.initial, .new], context: nil)
        UserDefaults.standard.addObserver(policyObserver, forKeyPath: "SUEnableAutomaticChecks", options: [.initial, .new], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard !UserDefaultsEvents.updatesTab.policyLock else { return }
        if SUUpdater.shared().automaticallyDownloadsUpdates {
            UserDefaultsEvents.updatesTab.periodicallyInstall.state = .on
            // Sparkle UI "Automatically download and install updates in the future" doesn't activate periodical checks; we do it manually
            SUUpdater.shared().automaticallyChecksForUpdates = true
        } else if SUUpdater.shared().automaticallyChecksForUpdates {
            UserDefaultsEvents.updatesTab.periodicallyCheck.state = .on
        } else {
            UserDefaultsEvents.updatesTab.dontPeriodicallyCheck.state = .on
        }
    }
}
