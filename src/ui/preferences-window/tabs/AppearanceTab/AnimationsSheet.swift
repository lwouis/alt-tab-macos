import Cocoa

class AnimationsSheet: SheetWindow {
    override func makeContentView() -> NSView {
        let table = TableGroupView(title: NSLocalizedString("Animations", comment: ""), width: SheetWindow.width)
        _ = table.addRow(leftText: NSLocalizedString("Apparition delay", comment: ""),
                rightViews: Array(LabelAndControl.makeLabelWithSlider("", "windowDisplayDelay", 0, 2000, 21, true, "ms", width: 300)[1...2]))
        _ = table.addRow(leftText: NSLocalizedString("Fade out animation", comment: ""),
                rightViews: LabelAndControl.makeCheckbox("fadeOutAnimation"))
        table.fit()
        return table
    }
}
