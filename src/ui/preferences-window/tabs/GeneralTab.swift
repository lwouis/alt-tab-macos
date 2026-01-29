import Cocoa

class GeneralTab {
    // docs: https://developer.apple.com/library/archive/technotes/tn2083/_index.html#//apple_ref/doc/uid/DTS10003794-CH1-SECTION23
    // docs: man launchd.plist
    private static let launchAgentPlist: NSDictionary = [
        "Label": App.bundleIdentifier,
        "Program": Bundle.main.executablePath ?? "/Applications/\(App.name).app/Contents/MacOS/\(App.name)",
        "RunAtLoad": true,
        "LimitLoadToSessionType": "Aqua",
        // starting from macOS 13, AssociatedBundleIdentifiers is required, otherwise the UI in
        // System Settings > General > Login Items, will show "Louis Pontoise" instead of "AltTab.app"
        "AssociatedBundleIdentifiers": App.bundleIdentifier,
        // "ProcessType: If left unspecified, the system will apply light resource limits to the job,
        //               throttling its CPU usage and I/O bandwidth"
        "ProcessType": "Interactive",
        // "LegacyTimers": If this key is set to true, timers created by the job will opt into less
        //                 efficient but more precise behavior and not be coalesced with other timers.
        "LegacyTimers": true,
    ]
    static var menubarIconDropdown: NSPopUpButton?
    private static var menubarIsVisibleObserver: NSKeyValueObservation?
    private static var startAtLoginToggle: NSControl?

    static func initTab() -> NSView {
        let startAtLogin = TableGroupView.Row(leftTitle: NSLocalizedString("Start at login", comment: ""),
            rightViews: [LabelAndControl.makeSwitch("startAtLogin", extraAction: startAtLoginCallback)])
        menubarIconDropdown = LabelAndControl.makeDropdown("menubarIcon", MenubarIconPreference.allCases, extraAction: Menubar.menubarIconCallback)
        let menuIconShownToggle = LabelAndControl.makeSwitch("menubarIconShown", extraAction: Menubar.menubarIconCallback)
        let menubarIcon = TableGroupView.Row(leftTitle: NSLocalizedString("Menubar icon", comment: ""),
            rightViews: [
                menubarIconDropdown!,
                menuIconShownToggle,
            ])
        let language = TableGroupView.Row(leftTitle: NSLocalizedString("Language", comment: ""),
            rightViews: [LabelAndControl.makeDropdown("language", LanguagePreference.allCases, extraAction: setLanguageCallback)])
        let resetPreferences = NSButton(title: NSLocalizedString("Reset settings and restart…", comment: ""), target: self, action: #selector(GeneralTab.resetPreferences))
        if #available(macOS 11.0, *) { resetPreferences.hasDestructiveAction = true }
        for i in 0..<MenubarIconPreference.allCases.count {
            let image = NSImage.initCopy("menubar-\(i)")
            image.isTemplate = i < 2
            menubarIconDropdown!.item(at: i)!.image = image
        }
        let cell = menubarIconDropdown!.cell! as! NSPopUpButtonCell
        cell.bezelStyle = .regularSquare
        cell.arrowPosition = .arrowAtBottom
        cell.imagePosition = .imageOverlaps
        startAtLoginToggle = startAtLogin.rightViews[0] as? NSControl
        Menubar.menubarIconCallback(nil)
        enableDraggingOffMenubarIcon(menuIconShownToggle)
        let table = TableGroupView(width: PreferencesWindow.width)
        table.addRow(startAtLogin)
        table.addRow(menubarIcon)
        table.addNewTable()
        table.addRow(language)
        let view = TableGroupSetView(originalViews: [table], toolsViews: [resetPreferences], toolsAlignment: .trailing)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        return view
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
            App.app.restart()
        }
    }

    /// add/remove plist file in ~/Library/LaunchAgents/ depending on the checkbox state
    static func startAtLoginCallback(_: NSControl? = nil) {
        let sender = startAtLoginToggle as! Switch
        // if the user has added AltTab manually as a LoginItem, we remove it, and add AltTab as a LaunchAgent
        // LaunchAgent are the recommended method for open-at-login in recent versions of macos
        if (GeneralTab.self as AvoidDeprecationWarnings.Type).removeLoginItemIfPresent() && sender.state == .off {
            sender.state = .on
            LabelAndControl.controlWasChanged(sender, sender.identifier!.rawValue)
        }
        do {
            try writePlistToDisk(sender)
        } catch let error {
            Logger.error { "Failed to write plist file to disk. error:\(error)" }
        }
    }

    private static func writePlistToDisk(_ sender: Switch) throws {
        var launchAgentsPath = (try? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)) ?? URL(fileURLWithPath: "~/Library", isDirectory: true)
        launchAgentsPath.appendPathComponent("LaunchAgents", isDirectory: true)
        if !FileManager.default.fileExists(atPath: launchAgentsPath.path) {
            try FileManager.default.createDirectory(at: launchAgentsPath, withIntermediateDirectories: false)
            Logger.debug { launchAgentsPath.absoluteString + " created" }
        }
        launchAgentsPath.appendPathComponent("com.lwouis.alt-tab-macos.plist", isDirectory: false)
        if sender.state == .on {
            let data = try PropertyListSerialization.data(fromPropertyList: launchAgentPlist, format: .xml, options: 0)
            try data.write(to: launchAgentsPath, options: [.atomic])
            Logger.debug { launchAgentsPath.absoluteString + " written" }
        } else {
            if FileManager.default.fileExists(atPath: launchAgentsPath.path) {
                try FileManager.default.removeItem(at: launchAgentsPath)
                Logger.debug { launchAgentsPath.absoluteString + " removed" }
            }
        }
    }

    @available(OSX, deprecated: 10.11)
    static func removeLoginItemIfPresent() -> Bool {
        var removed = false
        if let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil)?.takeRetainedValue(),
           let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] {
            let appUrl = URL(fileURLWithPath: Bundle.main.bundlePath)
            for item in loginItemsSnapshot {
                let itemUrl = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as? URL
                // example: itemUrl="file:///Applications/AltTab.app/"; lastPathComponent="AltTab.app"
                if (itemUrl?.lastPathComponent == appUrl.lastPathComponent) {
                    LSSharedFileListItemRemove(loginItems, item)
                    removed = true
                }
            }
        }
        return removed
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
            App.app.restart()
        }
    }
}

private protocol AvoidDeprecationWarnings {
    static func removeLoginItemIfPresent() -> Bool
}

extension GeneralTab: AvoidDeprecationWarnings {}
