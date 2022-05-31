import Cocoa

class GeneralTab {
    static func initTab() -> NSView {
        let startAtLogin = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Start at login:", comment: ""), "startAtLogin", extraAction: startAtLoginCallback)
        let menubarIcon = LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Menubar icon:", comment: ""), "menubarIcon", MenubarIconPreference.allCases, extraAction: Menubar.menubarIconCallback)
        let resetPreferences = Button(NSLocalizedString("Reset preferences and restart", comment: "")) { _ in GeneralTab.resetPreferences() }
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

        return StackView([grid, resetPreferences], .vertical, bottom: GridView.padding)
    }

    static func resetPreferences() {
        Preferences.resetAll()
        App.app.restart()
    }

    // add/remove plist file in ~/Library/LaunchAgents/ depending on the checkbox state
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
            let plist: NSDictionary = [
                "Label": "com.lwouis.alt-tab-macos",
                "Program": Bundle.main.executablePath ?? "/Applications/\(App.name).app/Contents/MacOS/\(App.name)",
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua",
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
