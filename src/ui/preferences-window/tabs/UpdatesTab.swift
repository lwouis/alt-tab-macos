import Cocoa
import Sparkle
import Preferences

class UpdatesTab: NSViewController, PreferencePane {
    let preferencePaneIdentifier = PreferencePane.Identifier("Updates")
    let preferencePaneTitle = NSLocalizedString("Updates", comment: "")
    let toolbarItemIcon = NSImage(named: NSImage.refreshTemplateName)!

    static var policyObserver: PolicyObserver!
    var dontPeriodicallyCheck: NSButton!
    var periodicallyCheck: NSButton!
    var periodicallyInstall: NSButton!
    // this helps prevent double-dipping (i.e. user updates the UI > changes the preference > updates the UI)
    var policyLock = false

    override func loadView() {
        UpdatesTab.policyObserver = PolicyObserver(self)
        dontPeriodicallyCheck = NSButton(radioButtonWithTitle: NSLocalizedString("Don't check for updates periodically", comment: ""), target: self, action: #selector(updatePolicyCallback))
        dontPeriodicallyCheck.fit()
        periodicallyCheck = NSButton(radioButtonWithTitle: NSLocalizedString("Check for updates periodically", comment: ""), target: self, action: #selector(updatePolicyCallback))
        periodicallyCheck.fit()
        periodicallyInstall = NSButton(radioButtonWithTitle: NSLocalizedString("Auto-install updates periodically", comment: ""), target: self, action: #selector(updatePolicyCallback))
        periodicallyInstall.fit()
        let policyLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("Updates policy:", comment: ""))
        let policies = NSStackView(views: [dontPeriodicallyCheck, periodicallyCheck, periodicallyInstall])
        policies.alignment = .left
        policies.orientation = .vertical
        policies.spacing = GridView.interPadding / 2
        let grid = GridView([
            [policyLabel, policies],
            [NSButton(title: NSLocalizedString("Check for updates now…", comment: ""), target: nil, action: #selector(UpdatesTab.checkForUpdatesNow))],
        ])
        grid.cell(atColumnIndex: 0, rowIndex: 0).xPlacement = .trailing
        let row1 = grid.row(at: 1)
        row1.mergeCells(in: NSRange(location: 0, length: 2))
        row1.topPadding = GridView.interPadding
        row1.cell(at: 0).xPlacement = .center
        grid.fit()
        view = grid
    }

    static func observeUserDefaults() {
        UserDefaults.standard.addObserver(UpdatesTab.policyObserver, forKeyPath: "SUAutomaticallyUpdate", options: [.initial, .new], context: nil)
        UserDefaults.standard.addObserver(UpdatesTab.policyObserver, forKeyPath: "SUEnableAutomaticChecks", options: [.initial, .new], context: nil)
    }

    @objc static func checkForUpdatesNow(_ sender: Any) {
        SUUpdater.shared().checkForUpdates(sender)
    }

    @objc func updatePolicyCallback() {
        policyLock = true
        SUUpdater.shared().automaticallyDownloadsUpdates = periodicallyInstall.state == .on
        SUUpdater.shared().automaticallyChecksForUpdates = periodicallyInstall.state == .on || periodicallyCheck.state == .on
        policyLock = false
    }
}

class PolicyObserver: NSObject {
    var updatesTab: UpdatesTab

    init(_ updatesTab: UpdatesTab) {
        self.updatesTab = updatesTab
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard !updatesTab.policyLock else { return }
        if SUUpdater.shared().automaticallyDownloadsUpdates {
            updatesTab.periodicallyInstall.state = .on
            // Sparkle UI "Automatically download and install updates in the future" doesn't activate periodical checks; we do it manually
            SUUpdater.shared().automaticallyChecksForUpdates = true
        } else if SUUpdater.shared().automaticallyChecksForUpdates {
            updatesTab.periodicallyCheck.state = .on
        } else {
            updatesTab.dontPeriodicallyCheck.state = .on
        }
    }
}
