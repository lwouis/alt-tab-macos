import Cocoa

class AppearanceTab {
    static var rowsCount: [NSView]!
    static var minWidthInRow: [NSView]!
    static var maxWidthInRow: [NSView]!

    static func initTab() -> NSView {
        rowsCount = LabelAndControl.makeLabelWithSlider(NSLocalizedString("Rows of thumbnails:", comment: ""), "rowsCount", 1, 20, 20, true) ?? []
        minWidthInRow = LabelAndControl.makeLabelWithSlider(NSLocalizedString("Window min width in row:", comment: ""), "windowMinWidthInRow", 1, 100, 10, true, "%", extraAction: { _ in capMinMaxWidthInRow() }) ?? []
        maxWidthInRow = LabelAndControl.makeLabelWithSlider(NSLocalizedString("Window max width in row:", comment: ""), "windowMaxWidthInRow", 1, 100, 10, true, "%", extraAction: { _ in capMinMaxWidthInRow() }) ?? []

        let generalSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Appearance model:", comment: ""), "appearanceModel", AppearanceModelPreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Appearance size:", comment: ""), "appearanceSize", AppearanceSizePreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Theme:", comment: ""), "theme", ThemePreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Align windows:", comment: ""), "alignThumbnails", AlignThumbnailsPreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Show on:", comment: ""), "showOnScreen", ShowOnScreenPreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Window title truncation:", comment: ""), "titleTruncation", TitleTruncationPreference.allCases),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide window thumbnails:", comment: ""), "hideThumbnails", extraAction: { _ in toggleRowsCount() }),
            rowsCount,
            minWidthInRow,
            maxWidthInRow,
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Window app icon size:", comment: ""), "iconSize", 0, 128, 11, false, "px"),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Window title font size:", comment: ""), "fontHeight", 0, 64, 11, false, "px"),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Max width on screen:", comment: ""), "maxWidthOnScreen", 10, 100, 10, true, "%"),
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Max height on screen:", comment: ""), "maxHeightOnScreen", 10, 100, 10, true, "%"),
        ]

        let showHideSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide app badges:", comment: ""), "hideAppBadges"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide status icons:", comment: ""), "hideStatusIcons"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide Space number labels:", comment: ""), "hideSpaceNumberLabels"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide colored circles on mouse hover:", comment: ""), "hideColoredCircles"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide apps with no open window:", comment: ""), "hideWindowlessApps"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Show standard tabs as windows:", comment: ""), "showTabsAsWindows"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Preview selected window:", comment: ""), "previewFocusedWindow"),
        ]

//        let positionSettings: [[NSView]] = [
//            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Max width on screen:", comment: ""), "maxWidthOnScreen", 10, 100, 10, true, "%"),
//            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Max height on screen:", comment: ""), "maxHeightOnScreen", 10, 100, 10, true, "%"),
//        ]

        let effectsSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Apparition delay:", comment: ""), "windowDisplayDelay", 0, 2000, 11, false, "ms"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Fade out animation:", comment: ""), "fadeOutAnimation"),
        ]

        let generalGrid = GridView(generalSettings)
        generalGrid.column(at: 0).xPlacement = .trailing
//        generalGrid.column(at: 0).width = 250
        generalGrid.column(at: 1).width = 200
//        generalGrid.column(at: 2).width = 50
        generalGrid.fit()

        let showHideGrid = GridView(showHideSettings)
        showHideGrid.column(at: 0).xPlacement = .trailing
//        showHideGrid.column(at: 0).width = 250
        showHideGrid.column(at: 1).width = 200
//        showHideGrid.column(at: 2).width = 50
        showHideGrid.fit()

        let effectsGrid = GridView(effectsSettings)
        effectsGrid.column(at: 0).xPlacement = .trailing
//        effectsGrid.column(at: 0).width = 250
        effectsGrid.column(at: 1).width = 200
//        effectsGrid.column(at: 2).width = 50
        effectsGrid.fit()

        // Create the tab view with fixed width and height
        let tabView = TabView([
            (NSLocalizedString("General", comment: ""), generalGrid),
            (NSLocalizedString("Show & Hide", comment: ""), showHideGrid),
            (NSLocalizedString("Effects", comment: ""), effectsGrid),
        ])
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        tabView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabView)

        let fixedWidth = CGFloat(600)
        let fixedHeight = CGFloat(500)

        NSLayoutConstraint.activate([
//            view.widthAnchor.constraint(equalToConstant: fixedWidth),
//            view.heightAnchor.constraint(equalToConstant: fixedHeight),

            tabView.topAnchor.constraint(equalTo: view.topAnchor, constant: TabView.padding),
            tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TabView.padding),
            tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TabView.padding),
            tabView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -TabView.padding),
            tabView.widthAnchor.constraint(equalToConstant: fixedWidth),
            tabView.heightAnchor.constraint(equalToConstant: fixedHeight),

            generalGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.topAnchor, constant: -TabView.padding),
            generalGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.centerXAnchor),

            showHideGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.topAnchor, constant: -TabView.padding),
            showHideGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.centerXAnchor),

            effectsGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.topAnchor, constant: -TabView.padding),
            effectsGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.centerXAnchor),
        ])

        return view
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
