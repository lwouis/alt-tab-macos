import Cocoa

class GeneralTab {
    private static var menubarIsVisibleObserver: NSKeyValueObservation?

    static func initTab() -> NSView {
        let startAtLogin = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Start at login:", comment: ""), "startAtLogin", extraAction: startAtLoginCallback)
        let menubarIcon = LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Menubar icon:", comment: ""), "menubarIcon", MenubarIconPreference.allCases, extraAction: App.app.menubar.menubarIconCallback)
        let resetPreferences = Button(NSLocalizedString("Reset preferences and restart…", comment: "")) { _ in GeneralTab.resetPreferences() }
        if #available(OSX 11, *) { resetPreferences.hasDestructiveAction = true }
        let menubarIconDropdown = menubarIcon[1] as! NSPopUpButton
        for i in 0...2 {
            let image = NSImage.initCopy("menubar-" + String(i + 1))
            image.isTemplate = i < 2
            menubarIconDropdown.item(at: i)!.image = image
        }
        menubarIconDropdown.item(at: 3)!.image = NSImage(size: NSSize(width: 1, height: menubarIconDropdown.item(at: 0)!.image!.size.height))
        let cell = menubarIconDropdown.cell! as! NSPopUpButtonCell
        cell.bezelStyle = .regularSquare
        cell.arrowPosition = .arrowAtBottom
        cell.imagePosition = .imageOverlaps

        let grid = GridView([
            startAtLogin,
            menubarIcon,
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.fit()

        startAtLoginCallback(startAtLogin[1] as! NSControl)
        enableDraggingOffMenubarIcon(menubarIconDropdown)

        return StackView([grid, resetPreferences], .vertical, bottom: GridView.padding)
    }

    private static func enableDraggingOffMenubarIcon(_ menubarIconDropdown: NSPopUpButton) {
        App.app.menubar.statusItem.behavior = .removalAllowed
        menubarIsVisibleObserver = App.app.menubar.statusItem.observe(\.isVisible, options: [.old, .new]) { _, change in
            if change.oldValue == true && change.newValue == false {
                let hiddenIndex = Int(MenubarIconPreference.hidden.rawValue)!
                menubarIconDropdown.selectItem(at: hiddenIndex)
                LabelAndControl.controlWasChanged(menubarIconDropdown, "menubarIcon")
            }
        }
    }

    static func resetPreferences() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = ""
        alert.informativeText = NSLocalizedString("You can’t undo this action.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        let resetButton = alert.addButton(withTitle: NSLocalizedString("Reset preferences and restart", comment: ""))
        if #available(OSX 11, *) { resetButton.hasDestructiveAction = true }
        if alert.runModal() == .alertSecondButtonReturn {
            Preferences.resetAll()
            App.app.restart()
        }
    }

    /// add/remove plist file in ~/Library/LaunchAgents/ depending on the checkbox state
    static func startAtLoginCallback(_ sender: NSControl) {
        var launchAgentsPath = (try? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)) ?? URL.init(fileURLWithPath: "~/Library", isDirectory: true)
        launchAgentsPath.appendPathComponent("LaunchAgents", isDirectory: true)
        if !FileManager.default.fileExists(atPath: launchAgentsPath.path) {
            do {
                try FileManager.default.createDirectory(at: launchAgentsPath, withIntermediateDirectories: false)
            } catch let error {
                debugPrint("Failed to create LaunchAgent directory at '\(launchAgentsPath.path)'", error)
            }
        }
        launchAgentsPath.appendPathComponent("com.lwouis.alt-tab-macos.plist", isDirectory: false)
        if (sender as! NSButton).state == .on {
            // docs: https://developer.apple.com/library/archive/technotes/tn2083/_index.html#//apple_ref/doc/uid/DTS10003794-CH1-SECTION23
            // docs: man launchd.plist
            let plist: NSDictionary = [
                "Label": App.id,
                "Program": Bundle.main.executablePath ?? "/Applications/\(App.name).app/Contents/MacOS/\(App.name)",
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua",
                // starting from macOS 13, AssociatedBundleIdentifiers is required, otherwise the UI in
                // System Settings > General > Login Items, will show "Louis Pontoise" instead of "AltTab.app"
                "AssociatedBundleIdentifiers": App.id,
                // "ProcessType: If left unspecified, the system will apply light resource limits to the job,
                //               throttling its CPU usage and I/O bandwidth"
                "ProcessType": "Interactive",
                // "LegacyTimers": If this key is set to true, timers created by the job will opt into less
                //                 efficient but more precise behavior and not be coalesced with other timers.
                "LegacyTimers": true,
            ]
            plist.write(to: launchAgentsPath, atomically: true)
        } else {
            do {
                try FileManager.default.removeItem(at: launchAgentsPath)
            } catch let error {
                debugPrint("Failed to remove LaunchAgent", error)
            }
        }
    }
}
