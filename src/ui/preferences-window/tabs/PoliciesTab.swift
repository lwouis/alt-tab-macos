import Cocoa
import Sparkle

class PoliciesTab {
    static var updateButtons: [NSButton]!
    static var crashButtons: [NSButton]!
    // this helps prevent double-dipping (i.e. user updates the UI > changes the preference > updates the UI)
    static var policyLock = false

    static func initTab() -> NSView {
        let updateLabel = LabelAndControl.makeLabel(NSLocalizedString("Updates policy:", comment: ""))
        PoliciesTab.updateButtons = LabelAndControl.makeRadioButtons(UpdatePolicyPreference.allCases, "updatePolicy", extraAction: { _ in
            PoliciesTab.policyLock = true
            let policy = Preferences.updatePolicy
            SUUpdater.shared().automaticallyDownloadsUpdates = policy == .autoInstall
            SUUpdater.shared().automaticallyChecksForUpdates = policy == .autoInstall || policy == .autoCheck
            PoliciesTab.policyLock = false
        })
        let updateOptions = StackView(PoliciesTab.updateButtons, .vertical)
        let checkForUpdates = NSButton(title: NSLocalizedString("Check for updates now…", comment: ""), target: nil, action: #selector(PoliciesTab.checkForUpdatesNow))

        let crashLabel = LabelAndControl.makeLabel(NSLocalizedString("Crash reports policy:", comment: ""))
        PoliciesTab.crashButtons = LabelAndControl.makeRadioButtons(CrashPolicyPreference.allCases, "crashPolicy")
        let crashOptions = StackView(PoliciesTab.crashButtons, .vertical)
        let grid = GridView([
            [updateLabel, updateOptions],
            [NSGridCell.emptyContentView, checkForUpdates],
            [crashLabel, crashOptions],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.row(at: 2).topPadding = GridView.interPadding * 1.5
        grid.fit()

        UserDefaultsEvents.observe()

        return grid
    }

    @objc static func checkForUpdatesNow(_ sender: Any) {
        SUUpdater.shared().checkForUpdates(sender)
    }
}
