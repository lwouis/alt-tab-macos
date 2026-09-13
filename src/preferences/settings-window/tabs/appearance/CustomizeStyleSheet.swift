import Cocoa

class CustomizeStyleSheet: SheetWindow {
    // Local labels (rows owned by this sheet). The Show/Hide rows below are sourced from
    // `ShowHideIllustratedView`'s static constants so each NSLocalizedString call lives in
    // exactly one place across the codebase.
    private static let labelShowTitles = NSLocalizedString("Show titles", comment: "")
    private static let labelTitleTruncation = NSLocalizedString("Title truncation", comment: "")
    private static let labelAppNameColumn = NSLocalizedString("Show app names in a separate column", comment: "")
    private static let labelAppNameAlignment = NSLocalizedString("Right-align app names", comment: "")
    private static let labelMinimumWidth = NSLocalizedString("Minimum width", comment: "")
    private static let labelMaximumWidth = NSLocalizedString("Maximum width", comment: "")
    private static let minimumWidthDescription = NSLocalizedString("Minimum content width in points. The switcher grows for longer titles, with a little spare room for changing symbols.", comment: "")
    private static let maximumWidthDescription = NSLocalizedString("Maximum percentage of the available screen width. Longer titles truncate at this limit.", comment: "")

    /// Pre-build search index for the open-button. See `SettingsSearchIndex.sheetSearchableStrings`.
    static let searchableStrings: [String] = [
        labelShowTitles,
        labelTitleTruncation,
        labelAppNameColumn, labelAppNameAlignment,
        labelMinimumWidth, labelMaximumWidth, minimumWidthDescription, maximumWidthDescription,
        ShowHideIllustratedView.hideStatusIconsLabel,
        ShowHideIllustratedView.hideStatusIconsSubtitle,
        ShowHideIllustratedView.hideSpaceNumberLabelsLabel,
        ShowHideIllustratedView.hideColoredCirclesLabel,
        IllustratedImageThemeView.placeholderLabelText,
    ] + ShowTitlesPreference.allCases.map { $0.localizedString }
      + TitleTruncationPreference.allCases.map { $0.localizedString }

    static let illustratedImageWidth = width

    let style = Preferences.appearanceStyle
    var illustratedImageView: IllustratedImageThemeView!
    var showHideIllustratedView: ShowHideIllustratedView!

    override func makeContentView() -> NSView {
        // The per-shortcut Customize sheet was trimmed to just style-tied global toggles. The
        // settings that used to live here either (a) moved to per-shortcut storage and now live
        // in `ControlsTab` (`showAppsOrWindows`, `showTabsAsWindows`) or (b) were dropped
        // entirely (`alignThumbnails`). The "Show & Hide" / "Advanced" tab control is gone too —
        // the remaining rows fit comfortably in one flat list.
        illustratedImageView = IllustratedImageThemeView(style, CustomizeStyleSheet.illustratedImageWidth)
        showHideIllustratedView = ShowHideIllustratedView(style, illustratedImageView)
        let showHideView = showHideIllustratedView.makeView()
        let advancedTable = TableGroupView(width: CustomizeStyleSheet.width)
        let showTitles = TableGroupView.Row(leftTitle: Self.labelShowTitles,
            rightViews: [LabelAndControl.makeDropdown(
                "showTitles", ShowTitlesPreference.allCases, extraAction: { [weak self] _ in
                    self?.showTitlesIllustratedImage()
                })])
        advancedTable.addRow(showTitles, onMouseEntered: { [weak self] _, _ in
            self?.showTitlesIllustratedImage()
        })
        let titleTruncation = TableGroupView.Row(leftTitle: Self.labelTitleTruncation,
            rightViews: LabelAndControl.makeRadioButtons("titleTruncation", TitleTruncationPreference.allCases))
        advancedTable.addRow(titleTruncation)
        if style == .titles {
            advancedTable.addRow(TableGroupView.Row(leftTitle: Self.labelAppNameColumn, rightViews: [LabelAndControl.makeSwitch("titlesAppNameColumn")]))
            advancedTable.addRow(TableGroupView.Row(leftTitle: Self.labelAppNameAlignment, rightViews: [LabelAndControl.makeSwitch("titlesAppNameTrailingAlignment")]))
            addWidthRow(advancedTable, Self.labelMinimumWidth, Self.minimumWidthDescription, "titlesMinimumWidth", 240, 600, 13, "pt")
            addWidthRow(advancedTable, Self.labelMaximumWidth, Self.maximumWidthDescription, "titlesMaximumWidthPercent", 50, 95, 10, "%")
        }
        advancedTable.onMouseExited = { [weak self] event, view in
            guard let self else { return }
            IllustratedImageThemeView.resetImage(self.illustratedImageView, event, view)
        }
        let advancedView = TableGroupSetView(originalViews: [advancedTable], padding: 0)
        return TableGroupSetView(originalViews: [illustratedImageView, showHideView, advancedView], padding: 0)
    }

    private func addWidthRow(_ table: TableGroupView, _ title: String, _ description: String,
                             _ key: String, _ minimum: Double, _ maximum: Double, _ ticks: Int, _ unit: String) {
        let controls = LabelAndControl.makeLabelWithSlider("", key, minimum, maximum, ticks, true, unit, width: 140)
        let slider = controls[1] as! NSSlider
        slider.setAccessibilityLabel(title)
        slider.setAccessibilityHelp(description)
        let value = controls[2] as! NSTextField
        value.alignment = .right
        value.fit(56, value.fittingSize.height)
        table.addRow(TableGroupView.Row(leftTitle: title, subTitle: description, rightViews: [slider, value]))
    }

    private func showTitlesIllustratedImage() {
        illustratedImageView.highlight(true, Preferences.showTitles.image.name)
    }
}
