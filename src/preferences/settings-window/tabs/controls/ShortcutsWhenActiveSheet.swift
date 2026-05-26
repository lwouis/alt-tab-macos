import Cocoa

class ShortcutsWhenActiveSheet: SheetWindow {
    private static let title = NSLocalizedString("Shortcuts When Active", comment: "")
    private static let labelFocus = NSLocalizedString("Focus selected window", comment: "")
    private static let labelPrevious = NSLocalizedString("Select previous window", comment: "")
    private static let labelCancel = NSLocalizedString("Cancel", comment: "")
    private static let labelSearch = NSLocalizedString("Search", comment: "")
    private static let labelLockSearch = NSLocalizedString("Lock search", comment: "")
    private static let labelClose = NSLocalizedString("Close window", comment: "")
    private static let labelMinDemin = NSLocalizedString("Minimize/Deminimize window", comment: "")
    private static let labelFullscreen = NSLocalizedString("Fullscreen/Defullscreen window", comment: "")
    private static let labelQuit = NSLocalizedString("Quit app", comment: "")
    private static let labelHideShow = NSLocalizedString("Hide/Show app", comment: "")

    /// Pre-build search index for the open-button. See `SettingsSearchIndex.sheetSearchableStrings`.
    /// `ProBadgeView.proLabel` contributes the "Pro" tag rendered on the search/lock-search rows.
    static let searchableStrings: [String] = [
        title,
        labelFocus, labelPrevious, labelCancel,
        labelSearch, labelLockSearch,
        labelClose, labelMinDemin, labelFullscreen, labelQuit, labelHideShow,
        ProBadgeView.proLabel,
    ]

    override func makeContentView() -> NSView {
        let focusWindowShortcut = TableGroupView.Row(leftTitle: Self.labelFocus,
            rightViews: [LabelAndControl.makeLabelWithRecorder(Self.labelFocus, "focusWindowShortcut", Preferences.focusWindowShortcut, labelPosition: .right)[0]])
        let previousWindowShortcut = TableGroupView.Row(leftTitle: Self.labelPrevious,
            rightViews: [LabelAndControl.makeLabelWithRecorder(Self.labelPrevious, "previousWindowShortcut", Preferences.previousWindowShortcut, labelPosition: .right)[0]])
        let cancelShortcut = TableGroupView.Row(leftTitle: Self.labelCancel,
            rightViews: [LabelAndControl.makeLabelWithRecorder(Self.labelCancel, "cancelShortcut", Preferences.cancelShortcut, labelPosition: .right)[0]])
        let closeWindowShortcut = TableGroupView.Row(leftTitle: Self.labelClose,
            rightViews: [LabelAndControl.makeLabelWithRecorder(Self.labelClose, "closeWindowShortcut", Preferences.closeWindowShortcut, labelPosition: .right)[0]])
        let minDeminWindowShortcut = TableGroupView.Row(leftTitle: Self.labelMinDemin,
            rightViews: [LabelAndControl.makeLabelWithRecorder(Self.labelMinDemin, "minDeminWindowShortcut", Preferences.minDeminWindowShortcut, labelPosition: .right)[0]])
        let toggleFullscreenWindowShortcut = TableGroupView.Row(leftTitle: Self.labelFullscreen,
            rightViews: [LabelAndControl.makeLabelWithRecorder(Self.labelFullscreen, "toggleFullscreenWindowShortcut", Preferences.toggleFullscreenWindowShortcut, labelPosition: .right)[0]])
        let quitAppShortcut = TableGroupView.Row(leftTitle: Self.labelQuit,
            rightViews: [LabelAndControl.makeLabelWithRecorder(Self.labelQuit, "quitAppShortcut", Preferences.quitAppShortcut, labelPosition: .right)[0]])
        let hideShowAppShortcut = TableGroupView.Row(leftTitle: Self.labelHideShow,
            rightViews: [LabelAndControl.makeLabelWithRecorder(Self.labelHideShow, "hideShowAppShortcut", Preferences.hideShowAppShortcut, labelPosition: .right)[0]])
        let table = TableGroupView(title: Self.title, width: SheetWindow.width)
        _ = table.addRow(focusWindowShortcut)
        _ = table.addRow(previousWindowShortcut)
        _ = table.addRow(cancelShortcut)
        let searchRow = table.addRow(leftText: Self.labelSearch,
            rightViews: [LabelAndControl.makeLabelWithRecorder(Self.labelSearch, "searchShortcut", Preferences.searchShortcut, labelPosition: .right)[0]])
        addProBadgeToLeftLabel(searchRow)
        let lockSearchRow = table.addRow(leftText: Self.labelLockSearch,
            rightViews: [LabelAndControl.makeLabelWithRecorder(Self.labelLockSearch, "lockSearchShortcut", Preferences.lockSearchShortcut, labelPosition: .right)[0]])
        addProBadgeToLeftLabel(lockSearchRow)
        _ = table.addRow(closeWindowShortcut)
        _ = table.addRow(minDeminWindowShortcut)
        _ = table.addRow(toggleFullscreenWindowShortcut)
        _ = table.addRow(quitAppShortcut)
        _ = table.addRow(hideShowAppShortcut)
        return table
    }

    private func addProBadgeToLeftLabel(_ rowInfo: TableGroupView.RowInfo) {
        guard let label = rowInfo.leftViews?.first as? NSTextField else { return }
        let badge = ProBadgeView()
        label.superview?.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            badge.centerYAnchor.constraint(equalTo: label.centerYAnchor, constant: 1),
        ])
    }
}
