import Cocoa

class ShortcutsWhenActiveSheet: SheetWindow {
    override func makeContentView() -> NSView {
        let focusWindowShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Focus selected window", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Focus selected window", comment: ""), "focusWindowShortcut", Preferences.focusWindowShortcut, labelPosition: .right)[0]])
        let previousWindowShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Select previous window", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select previous window", comment: ""), "previousWindowShortcut", Preferences.previousWindowShortcut, labelPosition: .right)[0]])
        let cancelShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Cancel and hide", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Cancel and hide", comment: ""), "cancelShortcut", Preferences.cancelShortcut, labelPosition: .right)[0]])
        let closeWindowShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Close window", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Close window", comment: ""), "closeWindowShortcut", Preferences.closeWindowShortcut, labelPosition: .right)[0]])
        let minDeminWindowShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Minimize/Deminimize window", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Minimize/Deminimize window", comment: ""), "minDeminWindowShortcut", Preferences.minDeminWindowShortcut, labelPosition: .right)[0]])
        let toggleFullscreenWindowShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Fullscreen/Defullscreen window", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Fullscreen/Defullscreen window", comment: ""), "toggleFullscreenWindowShortcut", Preferences.toggleFullscreenWindowShortcut, labelPosition: .right)[0]])
        let quitAppShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Quit app", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Quit app", comment: ""), "quitAppShortcut", Preferences.quitAppShortcut, labelPosition: .right)[0]])
        let hideShowAppShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Hide/Show app", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hide/Show app", comment: ""), "hideShowAppShortcut", Preferences.hideShowAppShortcut, labelPosition: .right)[0]])
        let table = TableGroupView(title: NSLocalizedString("Shortcuts When Active", comment: ""), width: SheetWindow.width)
        _ = table.addRow(focusWindowShortcut)
        _ = table.addRow(previousWindowShortcut)
        _ = table.addRow(cancelShortcut)
        _ = table.addRow(closeWindowShortcut)
        _ = table.addRow(minDeminWindowShortcut)
        _ = table.addRow(toggleFullscreenWindowShortcut)
        _ = table.addRow(quitAppShortcut)
        _ = table.addRow(hideShowAppShortcut)
        return table
    }
}
