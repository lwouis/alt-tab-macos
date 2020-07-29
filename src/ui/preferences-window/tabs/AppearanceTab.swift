import Cocoa
import Preferences

class AppearanceTab: NSViewController, PreferencePane {
    let preferencePaneIdentifier = PreferencePane.Identifier("Appearance")
    let preferencePaneTitle = NSLocalizedString("Appearance", comment: "")
    let toolbarItemIcon = NSImage(named: NSImage.colorPanelName)!

    override func loadView() {
        let grid = GridView([
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Theme:", comment: ""), "theme", ThemePreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Align windows:", comment: ""), "alignThumbnails", AlignThumbnailsPreference.allCases),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Max size on screen:", comment: ""), "maxScreenUsage", 10, 100, 10, true, "%"),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Rows of windows:", comment: ""), "rowsCount", 1, 20, 20, true),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Min windows per row:", comment: ""), "minCellsPerRow", 1, 20, 20, true),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Max windows per row:", comment: ""), "maxCellsPerRow", 1, 40, 20, true),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Window app icon size:", comment: ""), "iconSize", 0, 64, 11, false, "px"),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Window title font size:", comment: ""), "fontHeight", 0, 64, 11, false, "px"),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Window title truncation:", comment: ""), "titleTruncation", TitleTruncationPreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Show on:", comment: ""), "showOnScreen", ShowOnScreenPreference.allCases),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Apparition delay:", comment: ""), "windowDisplayDelay", 0, 2000, 11, false, "ms"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Fade out animation:", comment: ""), "fadeOutAnimation", extraAction: { _ in App.app.thumbnailsPanel.updateFadeOutAnimation() }),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide space number labels:", comment: ""), "hideSpaceNumberLabels"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide status icons:", comment: ""), "hideStatusIcons"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Show standard tabs as windows:", comment: ""), "showTabsAsWindows"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide colored circles on mouse hover:", comment: ""), "hideColoredCircles"),
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .lastBaseline
        grid.fit()

        setView(grid)
    }
}
