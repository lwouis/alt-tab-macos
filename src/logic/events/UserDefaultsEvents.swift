import Cocoa
import Sparkle

class UserDefaultsEvents: NSObject {
    private static var policyObserver = UserDefaultsEvents()

    static func observe() {
        UserDefaults.standard.addObserver(policyObserver, forKeyPath: "SUAutomaticallyUpdate", options: [.initial, .new], context: nil)
        UserDefaults.standard.addObserver(policyObserver, forKeyPath: "SUEnableAutomaticChecks", options: [.initial, .new], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard !PoliciesTab.policyLock else { return }
        let buttons = PoliciesTab.updateButtons!
        let id = buttonIdToUpdate()
        if id == 2 {
            // Sparkle UI "Automatically download and install updates in the future" doesn't activate periodical checks; we do it manually
            SUUpdater.shared().automaticallyChecksForUpdates = true
        }
        buttons[id].state = .on
        Preferences.set("updatePolicy", String(id))
    }

    private func buttonIdToUpdate() -> Int {
        if SUUpdater.shared().automaticallyDownloadsUpdates {
            return 2
        } else if SUUpdater.shared().automaticallyChecksForUpdates {
            return 1
        }
        return 0
    }
}
