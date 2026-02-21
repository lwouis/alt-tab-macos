import Cocoa
import Sparkle

class GeneralTab {
    static var menubarIconDropdown: NSPopUpButton?
    static var updatesPolicyDropdown: NSPopUpButton?
    static var crashPolicyDropdown: NSPopUpButton?
    static var policyLock = false
    private static var menubarIsVisibleObserver: NSKeyValueObservation?

    static func initTab() -> NSView {
        let startAtLogin = TableGroupView.Row(leftTitle: NSLocalizedString("Start at login", comment: ""),
            rightViews: [LabelAndControl.makeSwitch("startAtLogin")])
        menubarIconDropdown = LabelAndControl.makeDropdown("menubarIcon", MenubarIconPreference.allCases)
        let menuIconShownToggle = LabelAndControl.makeSwitch("menubarIconShown")
        let menubarIcon = TableGroupView.Row(leftTitle: NSLocalizedString("Menubar icon", comment: ""),
            rightViews: [
                menubarIconDropdown!,
                menuIconShownToggle,
            ])
        let language = TableGroupView.Row(leftTitle: NSLocalizedString("Language", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("language", LanguagePreference.allCases, extraAction: setLanguageCallback)])
        updatesPolicyDropdown = LabelAndControl.makeDropdown("updatePolicy", UpdatePolicyPreference.allCases)
        let updatesPolicy = TableGroupView.Row(leftTitle: NSLocalizedString("Updates policy", comment: ""),
            rightViews: [updatesPolicyDropdown!])
        crashPolicyDropdown = LabelAndControl.makeDropdown("crashPolicy", CrashPolicyPreference.allCases)
        let crashPolicy = TableGroupView.Row(leftTitle: NSLocalizedString("Crash reports policy", comment: ""),
            rightViews: [crashPolicyDropdown!])
        for i in 0..<MenubarIconPreference.allCases.count {
            let image = NSImage.initCopy("menubar-\(i)")
            image.isTemplate = i < 2
            menubarIconDropdown!.item(at: i)!.image = image
        }
        let cell = menubarIconDropdown!.cell! as! NSPopUpButtonCell
        cell.bezelStyle = .regularSquare
        cell.arrowPosition = .arrowAtBottom
        cell.imagePosition = .imageOverlaps
        enableDraggingOffMenubarIcon(menuIconShownToggle)
        let table = TableGroupView(width: SettingsWindow.contentWidth)
        table.addRow(startAtLogin)
        table.addRow(menubarIcon)
        table.addNewTable()
        table.addRow(language)
        table.addNewTable()
        table.addRow(updatesPolicy)
        table.addRow(crashPolicy)
        let exportButton = NSButton(title: NSLocalizedString("Export settings…", comment: ""), target: nil, action: nil)
        exportButton.onAction = { _ in exportSettings() }
        let importButton = NSButton(title: NSLocalizedString("Import settings…", comment: ""), target: nil, action: nil)
        importButton.onAction = { _ in importSettings() }
        let checkForUpdates = NSButton(title: NSLocalizedString("Check for updates now…", comment: ""), target: nil, action: nil)
        checkForUpdates.onAction = { control in checkForUpdatesNow(control) }
        let tools = StackView([exportButton, importButton, checkForUpdates], .horizontal)
        let view = TableGroupSetView(originalViews: [table, tools], bottomPadding: 0)
        return view
    }

    static func refreshControlsFromPreferences() {
        menubarIconDropdown?.selectItem(at: CachedUserDefaults.intFromMacroPref("menubarIcon", MenubarIconPreference.allCases))
        menubarIconDropdown?.isEnabled = Preferences.menubarIconShown
        updatesPolicyDropdown?.selectItem(at: CachedUserDefaults.intFromMacroPref("updatePolicy", UpdatePolicyPreference.allCases))
        crashPolicyDropdown?.selectItem(at: CachedUserDefaults.intFromMacroPref("crashPolicy", CrashPolicyPreference.allCases))
    }

    private static func enableDraggingOffMenubarIcon(_ menuIconShownToggle: Switch) {
        Menubar.statusItem.behavior = .removalAllowed
        menubarIsVisibleObserver = Menubar.statusItem.observe(\.isVisible, options: [.old, .new]) { _, change in
            if change.oldValue == true && change.newValue == false {
                menuIconShownToggle.state = .off
                LabelAndControl.controlWasChanged(menuIconShownToggle, nil)
            }
        }
    }

    @objc static func resetPreferences() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = ""
        alert.informativeText = NSLocalizedString("You can’t undo this action.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        let resetButton = alert.addButton(withTitle: NSLocalizedString("Reset settings and restart", comment: ""))
        if #available(macOS 11.0, *) { resetButton.hasDestructiveAction = true }
        if alert.runModal() == .alertSecondButtonReturn {
            Preferences.resetAll()
            App.restart()
        }
    }

    @objc static func checkForUpdatesNow(_ sender: Any?) {
        SUUpdater.shared().checkForUpdates(sender)
    }

    private static func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(App.bundleIdentifier).plist"
        panel.allowedFileTypes = ["plist"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        NSDictionary(dictionary: Preferences.all).write(to: url, atomically: true)
    }

    private static func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["plist"]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = NSLocalizedString("Failed to import settings", comment: "")
            alert.runModal()
            return
        }
        UserDefaults.standard.setPersistentDomain(dict, forName: App.bundleIdentifier)
        CachedUserDefaults.cache.withLock { $0.removeAll() }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Settings imported", comment: "")
        alert.informativeText = NSLocalizedString("The application needs to restart to apply the imported settings.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Restart Now", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            App.restart()
        }
    }

    static func setLanguageCallback(_ sender: NSControl) {
        if Preferences.language == .systemDefault {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([Preferences.language.appleLanguageCode!], forKey: "AppleLanguages")
        }
        // Inform the user that the app needs to restart to apply the language change
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Language Change", comment: "")
        alert.informativeText = NSLocalizedString("The application needs to restart to apply the language change.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Restart Now", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Later", comment: ""))
        if alert.runModal() == .alertFirstButtonReturn {
            App.restart()
        }
    }
}
