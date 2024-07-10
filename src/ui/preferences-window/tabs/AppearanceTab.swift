import Cocoa

class HoverView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

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

    static var showHideItems = [
        ["show_app_badges_light", "hide_app_badges_light", "show_app_badges_dark", "hide_app_badges_dark",
         LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide app badges", comment: ""), "hideAppBadges", labelPosition: .right)],
        ["show_status_icons_light", "hide_status_icons_light", "show_status_icons_dark", "hide_status_icons_dark",
         LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide status icons", comment: ""), "hideStatusIcons", labelPosition: .right)],
        ["show_space_number_labels_light", "hide_space_number_labels_light", "show_space_number_labels_dark", "hide_space_number_labels_dark",
         LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide Space number labels", comment: ""), "hideSpaceNumberLabels", labelPosition: .right)],
        ["show_colored_circles_light", "hide_colored_circles_light", "show_colored_circles_dark", "hide_colored_circles_dark",
         LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide colored circles on mouse hover", comment: ""), "hideColoredCircles", labelPosition: .right)],
        ["show_windowless_apps_light", "hide_windowless_apps_light", "show_windowless_apps_dark", "hide_windowless_apps_dark",
         LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide apps with no open window", comment: ""), "hideWindowlessApps", labelPosition: .right)],
        ["hide_tabs_as_windows_light", "show_tabs_as_windows_light", "hide_tabs_as_windows_dark", "show_tabs_as_windows_dark",
         LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Show standard tabs as windows", comment: ""), "showTabsAsWindows", labelPosition: .right)],
        ["hide_preview_focused_window_light", "show_preview_focused_window_light", "hide_preview_focused_window_dark", "show_preview_focused_window_dark", LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Preview selected window", comment: ""), "previewFocusedWindow", labelPosition: .right)],

    ]

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

        var showHideSettings: [[NSView]] = [
            [createImageView()],
        ]
        for item in showHideItems {
            if item.count >= 5, let view = item[4] as? [NSView] {
                showHideSettings.append(view)
            }
        }

        let effectsSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Apparition delay:", comment: ""), "windowDisplayDelay", 0, 2000, 11, false, "ms"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Fade out animation:", comment: ""), "fadeOutAnimation"),
        ]

        let generalGrid = GridView(generalSettings)
        generalGrid.column(at: 0).xPlacement = .trailing
        // merge cells for separator
        generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 3), verticalRange: NSRange(location: 1, length: 1))
        generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 3), verticalRange: NSRange(location: 3, length: 1))
        generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 3), verticalRange: NSRange(location: 5, length: 1))
        generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 3), verticalRange: NSRange(location: 7, length: 1))
        generalGrid.fit()

        let showHideGrid = GridView(showHideSettings)
        // Set alignment
        setAlignment(showHideGrid)
        showHideGrid.column(at: 0).width = showHideCellWidth
        showHideGrid.rowSpacing = 0
        showHideGrid.row(at: 0).bottomPadding = GridView.padding

        addHoverEffect(showHideGrid)
        addCheckboxObserver(showHideGrid)
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
            tabView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -TabView.padding),
            tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TabView.padding),
            tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TabView.padding),
            tabView.widthAnchor.constraint(equalToConstant: tabView.fittingSize.width + 60),
            tabView.heightAnchor.constraint(equalToConstant: tabView.fittingSize.height + 20),

            generalGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.topAnchor),
            generalGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.centerXAnchor),

            showHideGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.topAnchor),
            showHideGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.centerXAnchor),

            effectsGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.topAnchor),
            effectsGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.centerXAnchor),
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
              let imageView = imageContainer.subviews.first as? NSImageView else { return }
        for rowIndex in 1..<grid.numberOfRows {
            for columnIndex in 0..<grid.numberOfColumns {
                if let contentView = grid.cell(atColumnIndex: columnIndex, rowIndex: rowIndex).contentView {
                    let hoverView = HoverView(frame: contentView.bounds)
                    hoverView.translatesAutoresizingMaskIntoConstraints = false
                    hoverView.onMouseEntered = {
                        hoverView.wantsLayer = true
                        hoverView.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.2).cgColor
                        hoverView.layer?.cornerRadius = 5.0

                        // Check the state of the checkbox using recursive search
                        let isChecked = findCheckboxState(in: contentView)
                        updateImageView(for: rowIndex, isChecked: isChecked, imageView: imageView)
                    }
                    hoverView.onMouseExited = {
                        hoverView.layer?.backgroundColor = NSColor.clear.cgColor
                    }
                    hoverView.addSubview(contentView)
                    contentView.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        hoverView.widthAnchor.constraint(equalToConstant: grid.column(at: 0).width),
                        contentView.topAnchor.constraint(equalTo: hoverView.topAnchor, constant: 10),
                        contentView.bottomAnchor.constraint(equalTo: hoverView.bottomAnchor, constant: -10),
                        contentView.leadingAnchor.constraint(equalTo: hoverView.leadingAnchor, constant: 10),
                        contentView.trailingAnchor.constraint(equalTo: hoverView.trailingAnchor, constant: -10),
                    ])
                    grid.cell(atColumnIndex: columnIndex, rowIndex: rowIndex).contentView = hoverView
                }
            }
        }
    }

    private static func createImageView(_ name: String = "thumbnails_light") -> NSView {
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

        let imageWidth = showHideCellWidth - 100
        let imageHeight = imageWidth / 1.6
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: imageWidth),
            imageView.heightAnchor.constraint(equalToConstant: imageHeight),
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

    private static func setAlignment(_ grid: GridView) {
        for rowIndex in 0..<grid.numberOfRows {
            for columnIndex in 0..<grid.numberOfColumns {
                let cell = grid.cell(atColumnIndex: columnIndex, rowIndex: rowIndex)
                if rowIndex == 0 {
                    cell.xPlacement = .center
                } else {
                    cell.xPlacement = .leading
                }
            }
        }
    }

    private static func addCheckboxObserver(_ grid: GridView) {
        guard let imageContainer = grid.cell(atColumnIndex: 0, rowIndex: 0).contentView,
              let imageView = imageContainer.subviews.first as? NSImageView else { return }

        for rowIndex in 1..<grid.numberOfRows {
            for columnIndex in 0..<grid.numberOfColumns {
                if let contentView = grid.cell(atColumnIndex: columnIndex, rowIndex: rowIndex).contentView as? HoverView {
                    for subview in contentView.subviews {
                        if let checkbox = subview as? NSButton {
                            checkbox.target = self
                            checkbox.action = #selector(checkboxClicked(_:))
                            checkbox.tag = rowIndex
                        }
                    }
                }
            }
        }
    }

    @objc private static func checkboxClicked(_ sender: NSButton) {
        guard let grid = sender.superview?.superview as? GridView,
              let imageContainer = grid.cell(atColumnIndex: 0, rowIndex: 0).contentView,
              let imageView = imageContainer.subviews.first as? NSImageView else { return }

        let rowIndex = sender.tag
        let isChecked = sender.state == .on
        updateImageView(for: rowIndex, isChecked: isChecked, imageView: imageView)
    }

    private static func updateImageView(for rowIndex: Int, isChecked: Bool, imageView: NSImageView) {
        debugPrint("updateImageView", "rowIndex:", rowIndex, "isChecked:", isChecked)
        // The first row is preview picture, so the index should minus 1
        // The light images are stored at index 0/1, dark images are stored at index 2/3
        // TODO: The appearance theme functionality has not been implemented yet.
        // We will implement it later; for now, use the light theme.
        let imageName = isChecked ? showHideItems[rowIndex - 1][1] : showHideItems[rowIndex - 1][0]
        if let imageName = imageName as? String {
            imageView.image = NSImage(named: imageName)
        }
    }

    private static func findCheckboxState(in view: NSView) -> Bool {
        if let checkbox = view as? NSButton {
            return checkbox.state == .on
        }
        for subview in view.subviews {
            if findCheckboxState(in: subview) {
                return true
            }
        }
        return false
    }
}
