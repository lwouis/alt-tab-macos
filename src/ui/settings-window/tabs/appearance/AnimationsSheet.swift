import Cocoa

class AnimationsSheet: SheetWindow {
    override func makeContentView() -> NSView {
        let table = TableGroupView(title: NSLocalizedString("Animations", comment: ""), width: SheetWindow.width)
        let slider = LabelAndControl.makeLabelWithSlider("", "windowDisplayDelay", 0, 900, 19, true, "ms", width: 180)
        let rule = slider[1]
        let indicator = slider[2] as! NSTextField
        indicator.alignment = .right
        indicator.fit(56, indicator.fittingSize.height)
        table.addRow(leftText: NSLocalizedString("Apparition delay of Switcher", comment: ""),
            rightViews: [rule, indicator])
        table.addRow(leftText: NSLocalizedString("Fade out animation of Switcher", comment: ""),
            rightViews: LabelAndControl.makeSwitch("fadeOutAnimation"))
        table.addRow(leftText: NSLocalizedString("Fade in animation of Preview", comment: ""),
            rightViews: LabelAndControl.makeSwitch("previewFadeInAnimation"))
        return table
    }
}
