import Cocoa

class MouseHoverView: NSView {
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

struct ShowHideItem {
    let uncheckedImageLight: String  // Light mode image when the item is unchecked
    let checkedImageLight: String    // Light mode image when the item is checked
    let uncheckedImageDark: String   // Dark mode image when the item is unchecked
    let checkedImageDark: String     // Dark mode image when the item is checked
    let components: [NSView]!        // UI components associated with this item
}

class AppearanceTab {
    static var showHideCellWidth = CGFloat(400)

    static var showHideGrid: GridView!
    static var infoPopover: NSPopover!

    static var titleTruncation: [NSView]!

    static var showHideItems: [ShowHideItem] = [
        ShowHideItem(uncheckedImageLight: "show_app_badges_light",
                checkedImageLight: "hide_app_badges_light",
                uncheckedImageDark: "show_app_badges_dark",
                checkedImageDark: "hide_app_badges_dark",
                components: LabelAndControl.makeLabelWithCheckbox(
                        NSLocalizedString("Hide app badges", comment: ""),
                        "hideAppBadges", extraAction: { sender in
                    let button = sender as! NSButton
                    onCheckboxClicked(sender: button, rowIndex: 1)
                }, labelPosition: .right)),
        ShowHideItem(uncheckedImageLight: "show_status_icons_light",
                checkedImageLight: "hide_status_icons_light",
                uncheckedImageDark: "show_status_icons_dark",
                checkedImageDark: "hide_status_icons_dark",
                components: LabelAndControl.makeLabelWithCheckboxAndInfoButton(
                        NSLocalizedString("Hide status icons", comment: ""),
                        "hideStatusIcons", extraAction: { sender in
                    let button = sender as! NSButton
                    onCheckboxClicked(sender: button, rowIndex: 2)
                }, labelPosition: .right,  infoAction: { rect, view in
                    showInfo(relativeTo: rect, of: view, relativeWidth: -44, relativeHeight: -67, message: "AltTab will show if the window is currently minimized or fullscreen with a status icon.")
                })),
        ShowHideItem(uncheckedImageLight: "show_space_number_labels_light",
                checkedImageLight: "hide_space_number_labels_light",
                uncheckedImageDark: "show_space_number_labels_dark",
                checkedImageDark: "hide_space_number_labels_dark",
                components: LabelAndControl.makeLabelWithCheckbox(
                        NSLocalizedString("Hide Space number labels", comment: ""),
                        "hideSpaceNumberLabels", extraAction: { sender in
                    let button = sender as! NSButton
                    onCheckboxClicked(sender: button, rowIndex: 3)
                }, labelPosition: .right)),
        ShowHideItem(uncheckedImageLight: "show_colored_circles_light",
                checkedImageLight: "hide_colored_circles_light",
                uncheckedImageDark: "show_colored_circles_dark",
                checkedImageDark: "hide_colored_circles_dark",
                components: LabelAndControl.makeLabelWithCheckbox(
                        NSLocalizedString("Hide colored circles on mouse hover", comment: ""),
                        "hideColoredCircles", extraAction: { sender in
                    let button = sender as! NSButton
                    onCheckboxClicked(sender: button, rowIndex: 4)
                }, labelPosition: .right)),
        ShowHideItem(uncheckedImageLight: "show_windowless_apps_light",
                checkedImageLight: "hide_windowless_apps_light",
                uncheckedImageDark: "show_windowless_apps_dark",
                checkedImageDark: "hide_windowless_apps_dark",
                components: LabelAndControl.makeLabelWithCheckbox(
                        NSLocalizedString("Hide apps with no open window", comment: ""),
                        "hideWindowlessApps", extraAction: { sender in
                    let button = sender as! NSButton
                    onCheckboxClicked(sender: button, rowIndex: 5)
                }, labelPosition: .right)),
        ShowHideItem(uncheckedImageLight: "hide_tabs_as_windows_light",
                checkedImageLight: "show_tabs_as_windows_light",
                uncheckedImageDark: "hide_tabs_as_windows_dark",
                checkedImageDark: "show_tabs_as_windows_dark",
                components: LabelAndControl.makeLabelWithCheckboxAndInfoButton(
                        NSLocalizedString("Show standard tabs as windows", comment: ""),
                        "showTabsAsWindows", extraAction: { sender in
                    let button = sender as! NSButton
                    onCheckboxClicked(sender: button, rowIndex: 6)
                }, labelPosition: .right,  infoAction: { rect, view in
                    showInfo(relativeTo: rect, of: view, relativeWidth: 45, relativeHeight: -217, message: "Some apps like Finder or Preview use standard tabs which act like independent windows. Some other apps like web browsers use custom tabs which act in unique ways and are not actual windows. AltTab can't list those separately.")
                })),
        ShowHideItem(uncheckedImageLight: "hide_preview_focused_window_light",
                checkedImageLight: "show_preview_focused_window_light",
                uncheckedImageDark: "hide_preview_focused_window_dark",
                checkedImageDark: "show_preview_focused_window_dark",
                components: LabelAndControl.makeLabelWithCheckbox(
                        NSLocalizedString("Preview selected window", comment: ""),
                        "previewFocusedWindow", extraAction: { sender in
                    let button = sender as! NSButton
                    onCheckboxClicked(sender: button, rowIndex: 7)
                }, labelPosition: .right)),
    ]

    static func initTab() -> NSView {
        titleTruncation = LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Window title truncation:", comment: ""),
                "titleTruncation", TitleTruncationPreference.allCases)

        let generalSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Appearance model:", comment: ""),
                    "appearanceModel", AppearanceModelPreference.allCases, extraAction: { sender in
                let button = sender as! NSButton
                toggleTitleTruncation(button: button)
            }),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Theme:", comment: ""),
                    "theme", ThemePreference.allCases, buttonSpacing: 50),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Align windows:", comment: ""),
                    "alignThumbnails", AlignThumbnailsPreference.allCases, buttonSpacing: 55),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            LabelAndControl.makeLabelWithRadioButtons(NSLocalizedString("Appearance size:", comment: ""),
                    "appearanceSize", AppearanceSizePreference.allCases),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            LabelAndControl.makeLabelWithRadioButtons(NSLocalizedString("Icon size:", comment: ""),
                    "radioIconSize", IconSizePreference.allCases),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            LabelAndControl.makeLabelWithRadioButtons(NSLocalizedString("Title font size:", comment: ""),
                    "radioTitleFontSize", TitleFontSizePreference.allCases),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            titleTruncation,
        ]

        var showHideSettings: [[NSView]] = [
            [createIllustratedImageView()],
        ]
        for item in showHideItems {
            showHideSettings.append(item.components)
        }

        var positionSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Show on:", comment: ""), "showOnScreen", ShowOnScreenPreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("App vertical alignment:", comment: ""), "appVerticalAlignment", AppVerticalAlignmentPreference.allCases),
        ]

        let effectsSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Apparition delay:", comment: ""), "windowDisplayDelay", 0, 2000, 11, false, "ms"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Fade out animation:", comment: ""), "fadeOutAnimation"),
        ]

        let generalGrid = GridView(generalSettings)
        generalGrid.column(at: 0).xPlacement = .trailing
        // merge cells for separator
        [1, 3, 5, 7, 9, 11].forEach { row in
            generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 3), verticalRange: NSRange(location: row, length: 1))
        }
        generalGrid.fit()

        showHideGrid = GridView(showHideSettings)
        // Set alignment
        setAlignment(showHideGrid)
        showHideGrid.column(at: 0).width = showHideCellWidth
        showHideGrid.rowSpacing = 0
        showHideGrid.row(at: 0).bottomPadding = GridView.padding
        addMouseHoverEffects(showHideGrid)
        showHideGrid.fit()

        let positionGrid = GridView(positionSettings)
        positionGrid.column(at: 0).xPlacement = .trailing
        positionGrid.row(at: 0).bottomPadding = TabView.padding
        positionGrid.fit()

        let effectsGrid = GridView(effectsSettings)
        effectsGrid.column(at: 0).xPlacement = .trailing
        effectsGrid.row(at: 0).bottomPadding = TabView.padding
        effectsGrid.column(at: 1).width = 200
        effectsGrid.fit()

        // Create the tab view with fixed width and height
        let tabView = TabView([
            (NSLocalizedString("General", comment: ""), generalGrid),
            (NSLocalizedString("Show & Hide", comment: ""), showHideGrid),
            (NSLocalizedString("Position", comment: ""), positionGrid),
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

            positionGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.topAnchor),
            positionGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.centerXAnchor),

            effectsGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 3).view!.topAnchor),
            effectsGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 3).view!.centerXAnchor),
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

    private static func addMouseHoverEffects(_ grid: GridView) {
        // Ignore the first row that stores the image
        guard let imageContainer = grid.cell(atColumnIndex: 0, rowIndex: 0).contentView,
              let imageView = imageContainer.subviews.first as? NSImageView else { return }
        for rowIndex in 1..<grid.numberOfRows {
            for columnIndex in 0..<grid.numberOfColumns {
                if let contentView = grid.cell(atColumnIndex: columnIndex, rowIndex: rowIndex).contentView {
                    let hoverView = MouseHoverView(frame: contentView.bounds)
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

    private static func createIllustratedImageView(_ name: String = "thumbnails_light") -> NSView {
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

    private static func onCheckboxClicked(sender: NSButton, rowIndex: Int) {
        guard let imageContainer = showHideGrid.cell(atColumnIndex: 0, rowIndex: 0).contentView,
              let imageView = imageContainer.subviews.first as? NSImageView else { return }

        let isChecked = sender.state == .on
        updateImageView(for: rowIndex, isChecked: isChecked, imageView: imageView)
    }

    private static func updateImageView(for rowIndex: Int, isChecked: Bool, imageView: NSImageView) {
        // The first row is preview picture, so the index should minus 1
        // TODO: The appearance theme functionality has not been implemented yet.
        // We will implement it later; for now, use the light theme.
        let imageName = isChecked ?
                showHideItems[rowIndex - 1].checkedImageLight : showHideItems[rowIndex - 1].uncheckedImageLight
        imageView.image = NSImage(named: imageName)
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

    private static func showInfo(relativeTo rect: NSRect, of view: NSView,
                                 relativeWidth: CGFloat, relativeHeight: CGFloat, message: String) {
        guard let window = view.window else {
            return
        }

        // Close the existing Popover if it's already open
        if let existingPopover = infoPopover {
            existingPopover.performClose(nil)
        }

        // Create a new Popover
        let popover = NSPopover()
        popover.behavior = .semitransient

        // Create the content view controller
        let viewController = NSViewController()
        viewController.view = NSView()

        // Add the text label
        let label = NSTextField(labelWithString: NSLocalizedString(message, comment: ""))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.isEditable = false
        label.isSelectable = true
        label.textColor = NSColor.gray
        label.font = NSFont.systemFont(ofSize: 12)
        viewController.view.addSubview(label)

        let button = NSButton(title: NSLocalizedString("Done", comment: ""), target: popover, action: #selector(NSPopover.performClose(_:)))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.focusRingType = .none
        button.bezelStyle = .shadowlessSquare
        button.wantsLayer = true
        button.layer?.cornerRadius = 5.0
        button.layer?.backgroundColor = NSColor.lightGray.cgColor
        button.layer?.masksToBounds = true
        button.alignment = .center

        viewController.view.addSubview(button)

        // Set constraints
        NSLayoutConstraint.activate([
            viewController.view.widthAnchor.constraint(equalToConstant: 400),
            label.topAnchor.constraint(equalTo: viewController.view.topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor, constant: -10),

            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 15),
            button.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor, constant: -10),
            button.widthAnchor.constraint(equalToConstant: 42),
            button.heightAnchor.constraint(equalToConstant: 23),
        ])

        popover.contentViewController = viewController

        // It's not a good idea to use relativeWidth and relativeHeight to show popover at the right position
        let correctRect = NSRect(x: window.frame.width / 2 + relativeWidth, y: window.frame.height / 2 + relativeHeight, width: 1, height: 1)
        popover.show(relativeTo: correctRect, of: window.contentView!, preferredEdge: .minY)

        infoPopover = popover
    }

    private static func toggleTitleTruncation(button: NSButton) {
        (titleTruncation[1] as! NSPopUpButton).isEnabled = (Preferences.appearanceModel == .thumbnails
                || Preferences.appearanceModel == .titles)
    }
}
