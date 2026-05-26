import Cocoa

class AnimationsSheet: SheetWindow {
    private static let title = NSLocalizedString("Animations", comment: "")
    private static let labelDelay = NSLocalizedString("Apparition delay of Switcher", comment: "")
    private static let labelFadeOut = NSLocalizedString("Fade out animation of Switcher", comment: "")
    private static let labelFadeIn = NSLocalizedString("Fade in animation of Preview", comment: "")

    /// Pre-build search index for the open-button. See `SettingsSearchIndex.sheetSearchableStrings`.
    static let searchableStrings: [String] = [title, labelDelay, labelFadeOut, labelFadeIn]

    override func makeContentView() -> NSView {
        let table = TableGroupView(title: Self.title, width: SheetWindow.width)
        let slider = LabelAndControl.makeLabelWithSlider("", "windowDisplayDelay", 0, 900, 19, true, "ms", width: 180)
        let rule = slider[1]
        let indicator = slider[2] as! NSTextField
        indicator.alignment = .right
        indicator.fit(56, indicator.fittingSize.height)
        table.addRow(leftText: Self.labelDelay, rightViews: [rule, indicator])
        table.addRow(leftText: Self.labelFadeOut, rightViews: LabelAndControl.makeSwitch("fadeOutAnimation"))
        table.addRow(leftText: Self.labelFadeIn, rightViews: LabelAndControl.makeSwitch("previewFadeInAnimation"))
        return table
    }
}
