import Cocoa

class AppearanceTab {
    static var rowsCount: [NSView]!
    static var minWidthInRow: [NSView]!
    static var maxWidthInRow: [NSView]!

    static func initTab() -> NSView {
        rowsCount = LabelAndControl.makeLabelWithSlider(NSLocalizedString("Rows of thumbnails:", comment: ""), "rowsCount", 1, 20, 20, true)
        minWidthInRow = LabelAndControl.makeLabelWithSlider(NSLocalizedString("Window min width in row:", comment: ""), "windowMinWidthInRow", 1, 100, 10, true, "%", extraAction: { _ in capMinMaxWidthInRow() })
        maxWidthInRow = LabelAndControl.makeLabelWithSlider(NSLocalizedString("Window max width in row:", comment: ""), "windowMaxWidthInRow", 1, 100, 10, true, "%", extraAction: { _ in capMinMaxWidthInRow() })

        let grid = GridView([
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Theme:", comment: ""), "theme", ThemePreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Align windows:", comment: ""), "alignThumbnails", AlignThumbnailsPreference.allCases),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Max width on screen:", comment: ""), "maxWidthOnScreen", 10, 100, 10, true, "%"),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Max height on screen:", comment: ""), "maxHeightOnScreen", 10, 100, 10, true, "%"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide window thumbnails:", comment: ""), "hideThumbnails", extraAction: { _ in toggleRowsCount() }),
            rowsCount,
            minWidthInRow,
            maxWidthInRow,
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Window app icon size:", comment: ""), "iconSize", 0, 128, 11, false, "px"),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Window title font size:", comment: ""), "fontHeight", 0, 64, 11, false, "px"),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Window title truncation:", comment: ""), "titleTruncation", TitleTruncationPreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Show on:", comment: ""), "showOnScreen", ShowOnScreenPreference.allCases),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Apparition delay:", comment: ""), "windowDisplayDelay", 0, 2000, 11, false, "ms"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Fade out animation:", comment: ""), "fadeOutAnimation"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide Space number labels:", comment: ""), "hideSpaceNumberLabels"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide status icons:", comment: ""), "hideStatusIcons"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Show standard tabs as windows:", comment: ""), "showTabsAsWindows"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide colored circles on mouse hover:", comment: ""), "hideColoredCircles"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide app badges:", comment: ""), "hideAppBadges"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide apps with no open window:", comment: ""), "hideWindowlessApps"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Preview selected window:", comment: ""), "previewFocusedWindow"),
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.fit()

        toggleRowsCount()
        capMinMaxWidthInRow()

        return grid
    }

    static func capMinMaxWidthInRow() {
        let minSlider = minWidthInRow[1] as! NSSlider
        let maxSlider = maxWidthInRow[1] as! NSSlider
        maxSlider.minValue = minSlider.doubleValue
        LabelAndControl.controlWasChanged(maxSlider, "windowMaxWidthInRow")
    }

    static func toggleRowsCount() {
        (rowsCount[1] as! NSSlider).isEnabled = !Preferences.hideThumbnails
    }
}
