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
        let window1Shortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Select Window 1", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder("", "window1Shortcut", Preferences.window1Shortcut, labelPosition: .right)[0]])
        let window2Shortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Select Window 2", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder("", "window2Shortcut", Preferences.window2Shortcut, labelPosition: .right)[0]])
        let window3Shortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Select Window 3", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder("", "window3Shortcut", Preferences.window3Shortcut, labelPosition: .right)[0]])
        let window4Shortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Select Window 4", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder("", "window4Shortcut", Preferences.window4Shortcut, labelPosition: .right)[0]])
        let window5Shortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Select Window 5", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder("", "window5Shortcut", Preferences.window5Shortcut, labelPosition: .right)[0]])
        let window6Shortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Select Window 6", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder("", "window6Shortcut", Preferences.window6Shortcut, labelPosition: .right)[0]])
        let window7Shortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Select Window 7", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder("", "window7Shortcut", Preferences.window7Shortcut, labelPosition: .right)[0]])
        let window8Shortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Select Window 8", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder("", "window8Shortcut", Preferences.window8Shortcut, labelPosition: .right)[0]])
        let window9Shortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Select Window 9", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder("", "window9Shortcut", Preferences.window9Shortcut, labelPosition: .right)[0]])
        let window10Shortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Select Window 10", comment: ""),
            rightViews: [LabelAndControl.makeLabelWithRecorder("", "window10Shortcut", Preferences.window10Shortcut, labelPosition: .right)[0]])
        let table = TableGroupView(title: NSLocalizedString("Shortcuts When Active", comment: ""), width: SheetWindow.width)
        _ = table.addRow(focusWindowShortcut)
        _ = table.addRow(previousWindowShortcut)
        _ = table.addRow(cancelShortcut)
        _ = table.addRow(closeWindowShortcut)
        _ = table.addRow(minDeminWindowShortcut)
        _ = table.addRow(toggleFullscreenWindowShortcut)
        _ = table.addRow(quitAppShortcut)
        _ = table.addRow(hideShowAppShortcut)
        _ = table.addRow(window1Shortcut)
        _ = table.addRow(window2Shortcut)
        _ = table.addRow(window3Shortcut)
        _ = table.addRow(window4Shortcut)
        _ = table.addRow(window5Shortcut)
        _ = table.addRow(window6Shortcut)
        _ = table.addRow(window7Shortcut)
        _ = table.addRow(window8Shortcut)
        _ = table.addRow(window9Shortcut)
        _ = table.addRow(window10Shortcut)
        return table
    }
}
