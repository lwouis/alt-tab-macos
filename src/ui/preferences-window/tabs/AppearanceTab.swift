import Cocoa

class AppearanceTab {
    static var width = CGFloat(600)
    static var height = CGFloat(280)

    static func initTab() -> NSView {
        let generalSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Appearance model:", comment: ""), "appearanceModel", AppearanceModelPreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Appearance size:", comment: ""), "appearanceSize", AppearanceSizePreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Theme:", comment: ""), "theme", ThemePreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Align windows:", comment: ""), "alignThumbnails", AlignThumbnailsPreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Window title truncation:", comment: ""), "titleTruncation", TitleTruncationPreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Show on:", comment: ""), "showOnScreen", ShowOnScreenPreference.allCases),
        ]

        let showHideSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide app badges", comment: ""), "hideAppBadges", labelPosition: .right),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide status icons", comment: ""), "hideStatusIcons", labelPosition: .right),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide Space number labels", comment: ""), "hideSpaceNumberLabels", labelPosition: .right),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide colored circles on mouse hover", comment: ""), "hideColoredCircles", labelPosition: .right),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide apps with no open window", comment: ""), "hideWindowlessApps", labelPosition: .right),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Show standard tabs as windows", comment: ""), "showTabsAsWindows", labelPosition: .right),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Preview selected window", comment: ""), "previewFocusedWindow", labelPosition: .right),
        ]

        let effectsSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Apparition delay:", comment: ""), "windowDisplayDelay", 0, 2000, 11, false, "ms"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Fade out animation:", comment: ""), "fadeOutAnimation"),
        ]

        let generalGrid = GridView(generalSettings)
        generalGrid.column(at: 0).xPlacement = .trailing
        generalGrid.column(at: 1).width = 200
        generalGrid.fit()

        let showHideGrid = GridView(showHideSettings)
        showHideGrid.column(at: 0).xPlacement = .leading
//        showHideGrid.column(at: 0).width = 200
        showHideGrid.fit()

        let effectsGrid = GridView(effectsSettings)
        effectsGrid.column(at: 0).xPlacement = .trailing
        effectsGrid.column(at: 1).width = 200
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

        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: view.topAnchor, constant: TabView.padding),
            tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TabView.padding),
            tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TabView.padding),
            tabView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -TabView.padding),
            tabView.widthAnchor.constraint(equalToConstant: width),
            tabView.heightAnchor.constraint(equalToConstant: height),

            generalGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.topAnchor, constant: -TabView.padding),
            generalGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.centerXAnchor),

            showHideGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.topAnchor, constant: -TabView.padding),
            showHideGrid.leadingAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.leadingAnchor, constant: 150),

            effectsGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.topAnchor, constant: -TabView.padding),
            effectsGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.centerXAnchor),
        ])

        return view
    }
}
