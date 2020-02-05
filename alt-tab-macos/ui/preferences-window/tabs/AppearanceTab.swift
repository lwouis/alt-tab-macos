import Cocoa
import Foundation

class AppearanceTab {
    private static let rowHeight = CGFloat(20)

    static func make() -> NSTabViewItem {
        return TabViewItem.make("Shortcuts", NSImage.colorPanelName, makeView())
    }

    private static func makeView() -> NSGridView {
        let view = GridView.make([
            LabelAndControl.makeLabelWithDropdown("Theme", "theme", Preferences.themeMacro.labels),
            LabelAndControl.makeLabelWithSlider("Max size on screen", "maxScreenUsage", 10, 100, 10, true, "%"),
            LabelAndControl.makeLabelWithSlider("Min windows per row", "minCellsPerRow", 1, 20, 20, true),
            LabelAndControl.makeLabelWithSlider("Max windows per row", "maxCellsPerRow", 1, 40, 20, true),
            LabelAndControl.makeLabelWithSlider("Min rows of windows", "minRows", 1, 20, 20, true),
            LabelAndControl.makeLabelWithSlider("Window app icon size", "iconSize", 0, 64, 11, false, "px"),
            LabelAndControl.makeLabelWithSlider("Window title font size", "fontHeight", 0, 64, 11, false, "px"),
            LabelAndControl.makeLabelWithDropdown("Show on", "showOnScreen", Preferences.showOnScreenMacro.labels),
            LabelAndControl.makeLabelWithSlider("Apparition delay", "windowDisplayDelay", 0, 2000, 11, false, "ms"),
            LabelAndControl.makeLabelWithCheckbox("Hide space number labels", "hideSpaceNumberLabels"),
        ])
        view.column(at: 0).xPlacement = .trailing
        view.rowAlignment = .lastBaseline
        view.setRowsHeight(rowHeight)
        view.fit()
        return view
    }
}
