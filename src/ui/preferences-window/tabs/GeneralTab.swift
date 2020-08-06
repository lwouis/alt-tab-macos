import Cocoa
import Preferences

class GeneralTab: NSViewController, PreferencePane {
    let preferencePaneIdentifier = PreferencePane.Identifier("General")
    let preferencePaneTitle = NSLocalizedString("General", comment: "")
    let toolbarItemIcon = NSImage(named: "general")!

    override func loadView() {
        let startAtLogin = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Start at login:", comment: ""), "startAtLogin", extraAction: startAtLoginCallback)
        let menubarIcon = LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Menubar icon:", comment: ""), "menubarIcon", MenubarIconPreference.allCases, extraAction: Menubar.menubarIconCallback)
        let menubarIconDropdown = menubarIcon[1] as! NSPopUpButton
        for i in 0...1 {
            let image = NSImage(named: "menubar-icon-" + String(i + 1))!
            image.isTemplate = true
            menubarIconDropdown.item(at: i)!.image = image
        }
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

        setView(grid)

        startAtLoginCallback(startAtLogin[1] as! NSControl)
    }

    // adding/removing login item depending on the checkbox state
    @available(OSX, deprecated: 10.11)
    func startAtLoginCallback(_ sender: NSControl) {
        let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue()
        let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItems, nil).takeRetainedValue() as! [LSSharedFileListItem]
        let itemName = Bundle.main.bundleURL.lastPathComponent as CFString
        let itemUrl = URL(fileURLWithPath: Bundle.main.bundlePath) as CFURL
        loginItemsSnapshot.forEach {
            if (LSSharedFileListItemCopyDisplayName($0)?.takeRetainedValue() == itemName) ||
                   (LSSharedFileListItemCopyResolvedURL($0, 0, nil)?.takeRetainedValue() == itemUrl) {
                LSSharedFileListItemRemove(loginItems, $0)
            }
        }
        if (sender as! NSButton).state == .on {
            let _ = LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemBeforeFirst.takeRetainedValue(), nil, nil, itemUrl, nil, nil).takeRetainedValue()
        }
    }
}
