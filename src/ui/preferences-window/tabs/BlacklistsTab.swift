import Cocoa
import Sparkle

class BlacklistsTab {
    static func initTab() -> NSView {
        let dontShowBlacklistLabel = NSTextField(labelWithString: NSLocalizedString("Don’t show windows from these apps", comment: ""))
        let dontShowBlacklist = LabelAndControl.makeTextArea(50, 3, Preferences.dontShowBlacklist.joined(separator: "\n"), "dontShowBlacklist")
        let disableShortcutsBlacklistLabel = NSTextField(labelWithString: NSLocalizedString("Ignore shortcuts while a window from these apps is active", comment: ""))
        let disableShortcutsBlacklistCheckbox = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Only if the window is fullscreen", comment: ""), "disableShortcutsBlacklistOnlyFullscreen", labelPosition: .right)
        let disableShortcutsBlacklist = LabelAndControl.makeTextArea(50, 3, Preferences.disableShortcutsBlacklist.joined(separator: "\n"), "disableShortcutsBlacklist")

        let grid = GridView([
            [dontShowBlacklistLabel],
            dontShowBlacklist,
            [disableShortcutsBlacklistLabel],
            disableShortcutsBlacklistCheckbox,
            disableShortcutsBlacklist,
        ])
        grid.row(at: 2).topPadding = GridView.interPadding * 1.5
        grid.fit()

        return grid
    }
}
