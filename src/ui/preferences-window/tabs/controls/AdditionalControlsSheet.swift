import Cocoa

class AdditionalControlsSheet: SheetWindow {
    override func makeContentView() -> NSView {
        let enableArrows = TableGroupView.Row(leftTitle: NSLocalizedString("Select windows using arrow keys", comment: ""),
                rightViews: [LabelAndControl.makeCheckbox("arrowKeysEnabled", extraAction: ControlsTab.arrowKeysEnabledCallback)])
        let enableVimKeys = TableGroupView.Row(leftTitle: NSLocalizedString("Select windows using vim keys", comment: ""),
                rightViews: [LabelAndControl.makeCheckbox("vimKeysEnabled", extraAction: ControlsTab.vimKeysEnabledCallback)])
        let enableMouse = TableGroupView.Row(leftTitle: NSLocalizedString("Select windows on mouse hover", comment: ""),
                rightViews: [LabelAndControl.makeCheckbox("mouseHoverEnabled")])

        ControlsTab.arrowKeysCheckbox = enableArrows.rightViews[0] as? NSButton
        ControlsTab.vimKeysCheckbox = enableVimKeys.rightViews[0] as? NSButton
        ControlsTab.arrowKeysEnabledCallback(ControlsTab.arrowKeysCheckbox)
        ControlsTab.vimKeysEnabledCallback(ControlsTab.vimKeysCheckbox)

        let table = TableGroupView(title: NSLocalizedString("Additional controls", comment: ""),
                width: PreferencesWindow.width)
        _ = table.addRow(enableArrows)
        _ = table.addRow(enableVimKeys)
        _ = table.addRow(enableMouse)
        return table
    }
}
