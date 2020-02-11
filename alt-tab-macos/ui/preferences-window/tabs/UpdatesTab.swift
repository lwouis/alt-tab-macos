import Cocoa
import Sparkle

class UpdatesTab: NSObject {
    static var dontPeriodicallyCheck: NSButton!
    static var periodicallyCheck: NSButton!
    static var periodicallyInstall: NSButton!
    static var policyObserver = PolicyObserver()

    static func make() -> NSTabViewItem {
        return TabViewItem.make(NSLocalizedString("Updates", comment: ""), NSImage.refreshTemplateName, makeView())
    }

    static func makeView() -> NSGridView {
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
        observePolicy()
        let view = GridView.make([
            [policyLabel, policies],
            [NSButton(title: NSLocalizedString("Check for updates now…", comment: ""), target: self, action: #selector(checkForUpdatesNow))],
        ])
        view.cell(atColumnIndex: 0, rowIndex: 0).xPlacement = .trailing
        let row1 = view.row(at: 1)
        row1.mergeCells(in: NSRange(location: 0, length: 2))
        row1.topPadding = GridView.interPadding
        row1.cell(at: 0).xPlacement = .center
        view.fit()
        return view
    }

    private static func observePolicy() {
        UserDefaults.standard.addObserver(UpdatesTab.policyObserver, forKeyPath: "SUAutomaticallyUpdate", options: [.initial, .new], context: nil)
        UserDefaults.standard.addObserver(UpdatesTab.policyObserver, forKeyPath: "SUEnableAutomaticChecks", options: [.initial, .new], context: nil)
    }

    @objc
    static func checkForUpdatesNow(_ sender: Any) {
        SUUpdater.shared().checkForUpdates(sender)
    }

    @objc
    static func updatePolicyCallback() {
        SUUpdater.shared().automaticallyDownloadsUpdates = periodicallyInstall.state == .on
        SUUpdater.shared().automaticallyChecksForUpdates = periodicallyInstall.state == .on || periodicallyCheck.state == .on
    }
}

class PolicyObserver: NSObject {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if SUUpdater.shared().automaticallyDownloadsUpdates {
            UpdatesTab.periodicallyInstall.state = .on
            // Sparkle UI "Automatically download and install updates in the future" doesn't activate periodical checks; we do it manually
            SUUpdater.shared().automaticallyChecksForUpdates = true
        } else if SUUpdater.shared().automaticallyChecksForUpdates {
            UpdatesTab.periodicallyCheck.state = .on
        } else {
            UpdatesTab.dontPeriodicallyCheck.state = .on
        }
    }
}
