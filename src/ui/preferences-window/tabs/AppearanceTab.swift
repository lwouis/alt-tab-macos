import Cocoa

class AppearanceTab {
    private static let rowHeight = CGFloat(20)

    static func make() -> NSTabViewItem {
        return TabViewItem.make(NSLocalizedString("Appearance", comment: ""), NSImage.colorPanelName, makeView())
    }

    private static func makeView() -> NSGridView {
        let view = GridView.make([
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Theme", comment: ""), "theme", MacroPreferences.themeList.values.map { $0.label }),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Align windows", comment: ""), "alignThumbnails", Array(MacroPreferences.alignThumbnailsList.keys)),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Max size on screen", comment: ""), "maxScreenUsage", 10, 100, 10, true, "%"),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Min windows per row", comment: ""), "minCellsPerRow", 1, 20, 20, true),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Max windows per row", comment: ""), "maxCellsPerRow", 1, 40, 20, true),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Rows of windows", comment: ""), "rowsCount", 1, 20, 20, true),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Window app icon size", comment: ""), "iconSize", 0, 64, 11, false, "px"),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Window title font size", comment: ""), "fontHeight", 0, 64, 11, false, "px"),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Show on", comment: ""), "showOnScreen", Array(MacroPreferences.showOnScreenList.keys)),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Apparition delay", comment: ""), "windowDisplayDelay", 0, 2000, 11, false, "ms"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide space number labels", comment: ""), "hideSpaceNumberLabels"),
        ])
        view.column(at: 0).xPlacement = .trailing
        view.rowAlignment = .lastBaseline
        view.fit()
        return view
    }
}
