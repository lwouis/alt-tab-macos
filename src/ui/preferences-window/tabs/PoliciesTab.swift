import Cocoa
import Sparkle

class PoliciesTab {
    static var updatesPolicyDropdown: NSPopUpButton!
    static var crashPolicyDropdown: NSPopUpButton!
    // this helps prevent double-dipping (i.e. user updates the UI > changes the preference > updates the UI)
    static var policyLock = false

    static func initTab() -> NSView {
        PoliciesTab.updatesPolicyDropdown = LabelAndControl.makeDropdown("updatePolicy", UpdatePolicyPreference.allCases, extraAction: { _ in
            PoliciesTab.policyLock = true
            let policy = Preferences.updatePolicy
            SUUpdater.shared().automaticallyDownloadsUpdates = policy == .autoInstall
            SUUpdater.shared().automaticallyChecksForUpdates = policy == .autoInstall || policy == .autoCheck
            PoliciesTab.policyLock = false
        })
        PoliciesTab.crashPolicyDropdown = LabelAndControl.makeDropdown("crashPolicy", CrashPolicyPreference.allCases)

        let table = TableGroupView(width: PreferencesWindow.width)
        table.addRow(leftText: NSLocalizedString("Updates policy", comment: ""), rightViews: [PoliciesTab.updatesPolicyDropdown])
        table.addRow(leftText: NSLocalizedString("Crash reports policy", comment: ""), rightViews: [PoliciesTab.crashPolicyDropdown])
        table.fit()
        let checkForUpdates = NSButton(title: NSLocalizedString("Check for updates now…", comment: ""), target: nil, action: #selector(PoliciesTab.checkForUpdatesNow))

        UserDefaultsEvents.observe()

        let view = TableGroupSetView(originalViews: [table, checkForUpdates])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        return view
    }

    @objc static func checkForUpdatesNow(_ sender: Any) {
        SUUpdater.shared().checkForUpdates(sender)
    }
}
