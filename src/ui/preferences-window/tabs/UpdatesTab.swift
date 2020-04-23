import Cocoa
import Sparkle
import Preferences

class UpdatesTab: NSViewController, PreferencePane {
    let preferencePaneIdentifier = PreferencePane.Identifier("Updates")
    let preferencePaneTitle = NSLocalizedString("Updates", comment: "")
    let toolbarItemIcon = NSImage(named: NSImage.refreshTemplateName)!

    var dontPeriodicallyCheck: NSButton!
    var periodicallyCheck: NSButton!
    var periodicallyInstall: NSButton!
    // this helps prevent double-dipping (i.e. user updates the UI > changes the preference > updates the UI)
    var policyLock = false

    override func loadView() {
        dontPeriodicallyCheck = NSButton(radioButtonWithTitle: NSLocalizedString("Don’t check for updates periodically", comment: ""), target: self, action: #selector(updatePolicyCallback))
        dontPeriodicallyCheck.fit()
        periodicallyCheck = NSButton(radioButtonWithTitle: NSLocalizedString("Check for updates periodically", comment: ""), target: self, action: #selector(updatePolicyCallback))
        periodicallyCheck.fit()
        periodicallyInstall = NSButton(radioButtonWithTitle: NSLocalizedString("Auto-install updates periodically", comment: ""), target: self, action: #selector(updatePolicyCallback))
        periodicallyInstall.fit()
        let policyLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("Updates policy:", comment: ""))
        policyLabel.isSelectable = false
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
        UserDefaultsEvents.observe(self)
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
