import Cocoa

class HoverImageView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var imageView: NSImageView?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        let newTrackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(newTrackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}

class AppearanceTab {
    static var showHideCellWidth = CGFloat(400)

    static func initTab() -> NSView {
        let generalSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Appearance model:", comment: ""), "appearanceModel", AppearanceModelPreference.allCases),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Appearance size:", comment: ""), "appearanceSize", AppearanceSizePreference.allCases),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Theme:", comment: ""), "theme", ThemePreference.allCases, buttonSpacing: 50),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Align windows:", comment: ""), "alignThumbnails", AlignThumbnailsPreference.allCases, buttonSpacing: 60),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Window title truncation:", comment: ""), "titleTruncation", TitleTruncationPreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Show on:", comment: ""), "showOnScreen", ShowOnScreenPreference.allCases),
        ]

        let showHideSettings: [[NSView]] = [
            [createImageView()],
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
//        generalGrid.column(at: 0).width = 150
//        generalGrid.column(at: 1).width = 300
//        generalGrid.column(at: 2).width = 150
        // merge cells for separator
        generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 3), verticalRange: NSRange(location: 1, length: 1))
        generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 3), verticalRange: NSRange(location: 3, length: 1))
        generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 3), verticalRange: NSRange(location: 5, length: 1))
        generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 3), verticalRange: NSRange(location: 7, length: 1))
        generalGrid.fit()

        let showHideGrid = GridView(showHideSettings)
        for rowIndex in 0..<showHideGrid.numberOfRows {
            for columnIndex in 0..<showHideGrid.numberOfColumns {
                let cell = showHideGrid.cell(atColumnIndex: columnIndex, rowIndex: rowIndex)
                if rowIndex == 0 {
                    cell.xPlacement = .center
                } else {
                    cell.xPlacement = .leading
                }
            }
        }
//        showHideGrid.column(at: 1).xPlacement = .leading
        showHideGrid.column(at: 0).width = showHideCellWidth
        addHoverEffect(showHideGrid)
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
            generalGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.centerXAnchor),
//            generalGrid.centerYAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.centerYAnchor, constant: -TabView.padding),
//            generalGrid.leadingAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.leadingAnchor, constant: TabView.padding),
//            generalGrid.trailingAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.trailingAnchor, constant: -TabView.padding),
//            generalGrid.leadingAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.leadingAnchor, constant: TabView.padding),
//            generalGrid.trailingAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.trailingAnchor, constant: -TabView.padding),
//            generalGrid.bottomAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.bottomAnchor, constant: -TabView.padding),
//
            showHideGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.topAnchor, constant: TabView.padding),
            showHideGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.centerXAnchor),
//            showHideGrid.leadingAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.leadingAnchor, constant: TabView.padding),
//            showHideGrid.trailingAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.trailingAnchor, constant: -TabView.padding),
//            showHideGrid.bottomAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.bottomAnchor, constant: -TabView.padding),
//
            effectsGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.topAnchor, constant: TabView.padding),
            effectsGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.centerXAnchor),
//            effectsGrid.leadingAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.leadingAnchor, constant: TabView.padding),
//            effectsGrid.trailingAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.trailingAnchor, constant: -TabView.padding),
//            effectsGrid.bottomAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.bottomAnchor, constant: -TabView.padding),
        ])
        return view
    }

    private static func makeSeparator(_ padding: CGFloat = 10) -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Create a container view to hold the separator and apply padding
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(separator)

        // Set constraints for the separator within the container view
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: containerView.topAnchor, constant: padding),
            separator.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -padding),
            separator.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])

        return containerView
    }

    private static func addHoverEffect(_ grid: GridView) {
        // Ignore the first row that stores the image
        guard let imageContainer = grid.cell(atColumnIndex: 0, rowIndex: 0).contentView,
              let initialImageView = imageContainer.subviews.first as? NSImageView else { return }
        let images = ["thumbnails", "app_badges", "status_icons", "space_number", "colored_circle",
                      "no_open_window", "standard_tabs_window", "preview_window"]
        for rowIndex in 1..<grid.numberOfRows {
            for columnIndex in 0..<grid.numberOfColumns {
                if let originalView = grid.cell(atColumnIndex: columnIndex, rowIndex: rowIndex).contentView {
                    let hoverImageView = HoverImageView(frame: originalView.bounds)
                    hoverImageView.translatesAutoresizingMaskIntoConstraints = false
                    hoverImageView.onMouseEntered = {
                        hoverImageView.wantsLayer = true
                        hoverImageView.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.2).cgColor
                        hoverImageView.layer?.cornerRadius = 5.0

                        // Replace the image
                        let newImage = NSImage(named: images[rowIndex])
                        initialImageView.image = newImage
                    }
                    hoverImageView.onMouseExited = {
                        hoverImageView.layer?.backgroundColor = NSColor.clear.cgColor
                    }
                    hoverImageView.addSubview(originalView)
                    originalView.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        hoverImageView.widthAnchor.constraint(equalToConstant: grid.column(at: 0).width),
                        originalView.topAnchor.constraint(equalTo: hoverImageView.topAnchor, constant: 5),
                        originalView.bottomAnchor.constraint(equalTo: hoverImageView.bottomAnchor, constant: -5),
                        originalView.leadingAnchor.constraint(equalTo: hoverImageView.leadingAnchor, constant: 10),
                        originalView.trailingAnchor.constraint(equalTo: hoverImageView.trailingAnchor, constant: -10),
                    ])
                    grid.cell(atColumnIndex: columnIndex, rowIndex: rowIndex).contentView = hoverImageView
                }
            }
        }
    }

    private static func createImageView(_ name: String = "thumbnails") -> NSView {
        let imageContainer = NSView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.wantsLayer = true
        imageContainer.layer?.cornerRadius = 7.0
        imageContainer.layer?.borderColor = NSColor.lightGray.withAlphaComponent(0.2).cgColor
        imageContainer.layer?.borderWidth = 2.0

        let imageView = NSImageView(image: NSImage(named: name)!)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageContainer.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: showHideCellWidth - 100),
            imageView.heightAnchor.constraint(equalToConstant: (showHideCellWidth - 100) / 1.6),
            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor, constant: 4),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor, constant: -4),
            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor, constant: -4),
        ])

        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        imageView.layer?.cornerRadius = 7.0
        imageContainer.identifier = NSUserInterfaceItemIdentifier("imageContainer")
        return imageContainer
    }
}
