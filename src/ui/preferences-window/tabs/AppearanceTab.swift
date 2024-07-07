import Cocoa

class AppearanceTab {
    static var width = CGFloat(600)
    static var height = CGFloat(300)

    static func initTab() -> NSView {
        let generalSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Appearance model:", comment: ""), "appearanceModel", AppearanceModelPreference.allCases),
            makeSeparator(),
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Appearance size:", comment: ""), "appearanceSize", AppearanceSizePreference.allCases),
            makeSeparator(),
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Theme:", comment: ""), "theme", ThemePreference.allCases, buttonSpacing: 50),
            makeSeparator(),
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Align windows:", comment: ""), "alignThumbnails", AlignThumbnailsPreference.allCases),
            makeSeparator(),
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
        generalGrid.column(at: 1).width = 300
        // merge cells for separator
        generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: 1, length: 1))
        generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: 3, length: 1))
        generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: 5, length: 1))
        generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: 7, length: 1))
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
            tabView.widthAnchor.constraint(equalToConstant: tabView.fittingSize.width + 60),
            tabView.heightAnchor.constraint(equalToConstant: tabView.fittingSize.height + 20),

            generalGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.topAnchor, constant: TabView.padding),
//            generalGrid.leadingAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.leadingAnchor, constant: TabView.padding),
//            generalGrid.trailingAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.trailingAnchor, constant: -TabView.padding),
//            generalGrid.bottomAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.bottomAnchor, constant: -TabView.padding),
//
            showHideGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.topAnchor, constant: TabView.padding),
//            showHideGrid.leadingAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.leadingAnchor, constant: TabView.padding),
//            showHideGrid.trailingAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.trailingAnchor, constant: -TabView.padding),
//            showHideGrid.bottomAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.bottomAnchor, constant: -TabView.padding),
//
            effectsGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.topAnchor, constant: TabView.padding),
//            effectsGrid.leadingAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.leadingAnchor, constant: TabView.padding),
//            effectsGrid.trailingAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.trailingAnchor, constant: -TabView.padding),
//            effectsGrid.bottomAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.bottomAnchor, constant: -TabView.padding),
        ])

        return view
    }

    private static func makeSeparator() -> [NSView] {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Create a container view to hold the separator and apply padding
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(separator)

        // Set constraints for the separator within the container view
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            separator.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            separator.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])

        return [containerView]
    }
}
