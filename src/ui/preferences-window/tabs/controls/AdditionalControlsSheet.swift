import Cocoa

class AdditionalControlsSheet: SheetWindow {
    override func makeContentView() -> NSView {
        let enableArrows = TableGroupView.Row(leftTitle: NSLocalizedString("Select windows using arrow keys", comment: ""),
                rightViews: [LabelAndControl.makeSwitch("arrowKeysEnabled", extraAction: ControlsTab.arrowKeysEnabledCallback)])
        let enableVimKeys = TableGroupView.Row(leftTitle: NSLocalizedString("Select windows using vim keys", comment: ""),
                rightViews: [LabelAndControl.makeSwitch("vimKeysEnabled", extraAction: ControlsTab.vimKeysEnabledCallback)])
        let enableMouse = TableGroupView.Row(leftTitle: NSLocalizedString("Select windows on mouse hover", comment: ""),
                rightViews: [LabelAndControl.makeSwitch("mouseHoverEnabled")])
        let enableCursorFollowFocus = TableGroupView.Row(leftTitle: NSLocalizedString("Cursor follows focus", comment: ""),
                rightViews: [LabelAndControl.makeSwitch("cursorFollowFocusEnabled")])

        ControlsTab.arrowKeysCheckbox = enableArrows.rightViews[0] as? Switch
        ControlsTab.vimKeysCheckbox = enableVimKeys.rightViews[0] as? Switch
        ControlsTab.arrowKeysEnabledCallback(ControlsTab.arrowKeysCheckbox)
        ControlsTab.vimKeysEnabledCallback(ControlsTab.vimKeysCheckbox)

        let table1 = TableGroupView(title: NSLocalizedString("Additional controls", comment: ""),
                width: PreferencesWindow.width)
        _ = table1.addRow(enableArrows)
        _ = table1.addRow(enableVimKeys)
        _ = table1.addRow(enableMouse)

        let table2 = TableGroupView(title: NSLocalizedString("Miscellaneous", comment: ""),
                width: PreferencesWindow.width)
        _ = table2.addRow(enableCursorFollowFocus)

        let view = TableGroupSetView(originalViews: [table1, table2], padding: 0)
        return view
    }
}
