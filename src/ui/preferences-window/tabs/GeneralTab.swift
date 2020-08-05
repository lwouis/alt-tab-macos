import Cocoa
import Preferences

class GeneralTab: NSViewController, PreferencePane {
    let preferencePaneIdentifier = PreferencePane.Identifier("General")
    let preferencePaneTitle = NSLocalizedString("General", comment: "")
    let toolbarItemIcon = NSImage(named: "general")!

    override func loadView() {
        let startAtLogin = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Start at login:", comment: ""), "startAtLogin", extraAction: startAtLoginCallback)
        let hideMenubarIcon = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide menubar icon:", comment: ""), "hideMenubarIcon", extraAction: hideMenubarIconCallback)

        let grid = GridView([
            startAtLogin,
            hideMenubarIcon,
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.fit()

        setView(grid)

        startAtLoginCallback(startAtLogin[1] as! NSControl)
        hideMenubarIconCallback(hideMenubarIcon[1] as! NSControl)
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

    private func hideMenubarIconCallback(_ sender: NSControl) {
        App.statusItem.isVisible = (sender as! NSButton).state == .off
    }
}
