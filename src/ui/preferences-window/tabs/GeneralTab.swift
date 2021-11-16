import Cocoa
import OSAKit

class GeneralTab {
    static func initTab() -> NSView {
        let startAtLogin = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Start at login:", comment: ""), "startAtLogin", extraAction: startAtLoginCallback)
        let menubarIcon = LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Menubar icon:", comment: ""), "menubarIcon", MenubarIconPreference.allCases, extraAction: Menubar.menubarIconCallback)
        let menubarIconDropdown = menubarIcon[1] as! NSPopUpButton
        for i in 0...2 {
            let image = NSImage.initCopy("menubar-" + String(i + 1))
            image.isTemplate = false
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

        return grid
    }

    // adding/removing login item depending on the checkbox state
    static func startAtLoginCallback(_ sender: NSControl) {
        let shouldLaunchAtLogin = (sender as! NSButton).state == .on
        let script = OSAScript(contentsOf: Bundle.main.url(forResource: "test", withExtension: "scpt")!, error: nil)!
        var error: NSDictionary?
        script.executeHandler(withName: "handler", arguments: [shouldLaunchAtLogin, Bundle.main.bundlePath], error: &error)
        if let error = error {
            debugPrint(error)
            if error["OSAScriptErrorNumberKey"] as? Int32 == -1743 {
                debugPrint("Missing permission in System Preferences > Security & Privacy > Privacy > Automation")
                let stdout = Bash.command("tccutil reset AppleEvents com.lwouis.alt-tab-macos")
                debugPrint(stdout)
                App.app.restart()
            }
        }
    }
}
