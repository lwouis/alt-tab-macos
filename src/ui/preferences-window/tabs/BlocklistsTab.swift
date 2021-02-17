import Cocoa
import Sparkle

class BlocklistsTab {
    static func initTab() -> NSView {
        let dontShowBlocklistLabel = NSTextField(labelWithString: NSLocalizedString("Don’t show windows from these apps", comment: ""))
        let dontShowBlocklist = LabelAndControl.makeTextArea(50, 6, Preferences.dontShowBlocklist.joined(separator: "\n"), "dontShowBlocklist")
        let disableShortcutsBlocklistLabel = NSTextField(labelWithString: NSLocalizedString("Ignore shortcuts while a window from these apps is active", comment: ""))
        let disableShortcutsBlocklistCheckbox = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Only if the window is fullscreen", comment: ""), "disableShortcutsBlocklistOnlyFullscreen", labelPosition: .right)
        let disableShortcutsBlocklist = LabelAndControl.makeTextArea(50, 6, Preferences.disableShortcutsBlocklist.joined(separator: "\n"), "disableShortcutsBlocklist")

        let grid = GridView([
            [dontShowBlocklistLabel],
            dontShowBlocklist,
            [disableShortcutsBlocklistLabel],
            disableShortcutsBlocklistCheckbox,
            disableShortcutsBlocklist,
        ])
        grid.row(at: 2).topPadding = GridView.interPadding * 1.5
        grid.fit()

        return grid
    }
}
