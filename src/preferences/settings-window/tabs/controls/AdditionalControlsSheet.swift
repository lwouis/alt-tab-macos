import Cocoa

class AdditionalControlsSheet: SheetWindow {
    // Localized labels live here once. `searchableStrings` and `makeContentView` both reference
    // these constants so changing a string takes one edit, and search can't silently miss a row
    // because of a typo divergence between the two paths.
    private static let title = NSLocalizedString("Additional controls", comment: "")
    private static let titleMiscellaneous = NSLocalizedString("Miscellaneous", comment: "")
    private static let labelArrows = NSLocalizedString("Select windows using arrow keys", comment: "")
    private static let labelVim = NSLocalizedString("Select windows using vim keys", comment: "")
    private static let labelMouse = NSLocalizedString("Select windows on mouse hover", comment: "")
    private static let labelCursorFollow = NSLocalizedString("Cursor follows focus", comment: "")
    private static let labelTrackpad = NSLocalizedString("Trackpad haptic feedback", comment: "")

    /// Pre-build search index for the open-button. See `SettingsSearchIndex.sheetSearchableStrings`.
    static let searchableStrings: [String] = [
        title, titleMiscellaneous,
        labelArrows, labelVim, labelMouse,
        labelCursorFollow, labelTrackpad,
    ] + CursorFollowFocus.allCases.map { $0.localizedString }

    override func makeContentView() -> NSView {
        let enableArrows = TableGroupView.Row(leftTitle: Self.labelArrows,
            rightViews: [LabelAndControl.makeSwitch("arrowKeysEnabled", extraAction: ControlsTab.arrowKeysEnabledCallback)])
        let enableVimKeys = TableGroupView.Row(leftTitle: Self.labelVim,
            rightViews: [LabelAndControl.makeSwitch("vimKeysEnabled", extraAction: ControlsTab.vimKeysEnabledCallback)])
        let enableMouse = TableGroupView.Row(leftTitle: Self.labelMouse,
            rightViews: [LabelAndControl.makeSwitch("mouseHoverEnabled")])
        let enableCursorFollowFocus = TableGroupView.Row(leftTitle: Self.labelCursorFollow,
            rightViews: [LabelAndControl.makeDropdown("cursorFollowFocus", CursorFollowFocus.allCases)])
        let enableTrackpadHapticFeedback = TableGroupView.Row(leftTitle: Self.labelTrackpad,
            rightViews: [LabelAndControl.makeSwitch("trackpadHapticFeedbackEnabled")])
        ControlsTab.arrowKeysCheckbox = enableArrows.rightViews[0] as? Switch
        ControlsTab.vimKeysCheckbox = enableVimKeys.rightViews[0] as? Switch
        ControlsTab.arrowKeysEnabledCallback(ControlsTab.arrowKeysCheckbox)
        ControlsTab.vimKeysEnabledCallback(ControlsTab.vimKeysCheckbox)
        let table1 = TableGroupView(title: Self.title, width: SheetWindow.width)
        _ = table1.addRow(enableArrows)
        _ = table1.addRow(enableVimKeys)
        _ = table1.addRow(enableMouse)
        let table2 = TableGroupView(title: Self.titleMiscellaneous, width: SheetWindow.width)
        _ = table2.addRow(enableCursorFollowFocus)
        _ = table2.addRow(enableTrackpadHapticFeedback)
        let view = TableGroupSetView(originalViews: [table1, table2], padding: 0)
        return view
    }
}
