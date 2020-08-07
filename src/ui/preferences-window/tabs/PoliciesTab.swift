import Cocoa
import Sparkle
import Preferences

class PoliciesTab: NSViewController, PreferencePane {
    let preferencePaneIdentifier = PreferencePane.Identifier("Policies")
    let preferencePaneTitle = NSLocalizedString("Policies", comment: "")
    let toolbarItemIcon = NSImage.initTemplate("policies")

    static var updateButtons: [NSButton]!
    static var crashButtons: [NSButton]!
    // this helps prevent double-dipping (i.e. user updates the UI > changes the preference > updates the UI)
    static var policyLock = false

    override func loadView() {
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

        setView(grid)

        UserDefaultsEvents.observe()
    }

    @objc static func checkForUpdatesNow(_ sender: Any) {
        SUUpdater.shared().checkForUpdates(sender)
    }
}
