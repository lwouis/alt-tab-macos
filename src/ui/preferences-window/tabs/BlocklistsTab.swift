import Cocoa
import Sparkle
import Preferences

class BlocklistsTab: NSViewController, PreferencePane {
    let preferencePaneIdentifier = PreferencePane.Identifier("Blocklists")
    let preferencePaneTitle = NSLocalizedString("Blocklists", comment: "")
    let toolbarItemIcon = NSImage(named: "NSScriptTemplate")!

    override func loadView() {
        let dontShowBlocklistLabel = NSTextField(labelWithString: NSLocalizedString("Don’t show windows from these apps", comment: ""))
        let dontShowBlocklist = LabelAndControl.makeTextArea(50, 3, ["com.apple.Safari", "com.apple.TextEdit"].joined(separator: "\n"), "dontShowBlocklist")
        let disableShortcutsBlocklistLabel = NSTextField(labelWithString: NSLocalizedString("Ignore shortcuts while a window from these apps is active", comment: ""))
        let disableShortcutsBlocklistCheckbox = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Only if the window is fullscreen", comment: ""), "disableShortcutsBlocklistOnlyFullscreen", labelPosition: .right)
        let disableShortcutsBlocklist = LabelAndControl.makeTextArea(50, 3, ["com.apple.Safari", "com.apple.TextEdit"].joined(separator: "\n"), "disableShortcutsBlocklist")

        let grid = GridView([
            [dontShowBlocklistLabel],
            dontShowBlocklist,
            [disableShortcutsBlocklistLabel],
            disableShortcutsBlocklistCheckbox,
            disableShortcutsBlocklist,
        ])
        grid.row(at: 2).topPadding = GridView.interPadding * 1.5
        grid.fit()
        view = grid
    }
}
