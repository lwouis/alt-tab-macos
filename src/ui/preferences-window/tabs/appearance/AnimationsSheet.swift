import Cocoa

class AnimationsSheet: SheetWindow {
    override func makeContentView() -> NSView {
        let table = TableGroupView(title: NSLocalizedString("Animations", comment: ""), width: SheetWindow.width)
        let slider = LabelAndControl.makeLabelWithSlider("", "windowDisplayDelay", 0, 2000, 21, true, "ms", width: 300)
        let rule = slider[1]
        let indicator = slider[2]
        indicator.fit(55, indicator.fittingSize.height)
        table.addRow(leftText: NSLocalizedString("Apparition delay", comment: ""),
                rightViews: [rule, indicator])
        table.addRow(leftText: NSLocalizedString("Fade out animation", comment: ""),
                rightViews: LabelAndControl.makeSwitch("fadeOutAnimation"))
        table.fit()
        return table
    }
}
