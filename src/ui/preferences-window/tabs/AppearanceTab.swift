import Cocoa

struct ShowHideItem {
    let uncheckedImageLight: String  // Light mode image when the item is unchecked
    let checkedImageLight: String    // Light mode image when the item is checked
    let uncheckedImageDark: String   // Dark mode image when the item is unchecked
    let checkedImageDark: String     // Dark mode image when the item is checked
    let components: [NSView]!        // UI components associated with this item
}

class AdvancedSettingsWindow: NSWindow {
    var alignThumbnails: [NSView]!
    var titleTruncation: [NSView]!
    var showAppsWindows: [NSView]!
    var showAppNamesWindowTitles: [NSView]!
    var doneButton: NSButton!

    convenience init(_ model: AppearanceModelPreference) {
        self.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        setupView(model)
        setupWindow()
    }

    private func setupWindow() {
        hidesOnDeactivate = false
        makeFirstResponder(nil)
    }

    private func setupView(_ model: AppearanceModelPreference) {
        alignThumbnails = LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Align windows:", comment: ""),
                "alignThumbnails", AlignThumbnailsPreference.allCases)
        titleTruncation = LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Window title truncation:", comment: ""),
                "titleTruncation", TitleTruncationPreference.allCases)
        showAppsWindows = LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Show:", comment: ""),
                "showAppsWindows", ShowAppsWindowsPreference.allCases, extraAction: { _ in
            self.toggleAppNamesWindowTitles()
        })
        showAppNamesWindowTitles = LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Show:", comment: ""),
                "showAppNamesWindowTitles", ShowAppNamesWindowTitlesPreference.allCases)

        doneButton = NSButton(title: NSLocalizedString("Done", comment: ""), target: self, action: #selector(onClicked(_:)))
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.focusRingType = .none
        if #available(macOS 10.14, *) {
            doneButton.bezelColor = NSColor.controlAccentColor
        }

        var view: NSView!
        if model == .thumbnails {
            view = setupThumbnailsView()
        } else if model == .appIcons {
            view = setupAppIconsView()
        } else if model == .titles {
            view = setupTitlesView()
        }
        setContentSize(view.fittingSize)
        contentView = view
    }

    private func setupThumbnailsView() -> NSView {
        let view = GridView([
            alignThumbnails,
            titleTruncation,
            [AppearanceTab.makeSeparator(), AppearanceTab.makeSeparator()],
            [doneButton],
        ])
        // Merge separator/button row
        [2, 3].forEach{ row in
            view.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: row, length: 1))
        }
        view.column(at: 0).xPlacement = .trailing
        view.column(at: 1).xPlacement = .leading
        view.cell(atColumnIndex: 0, rowIndex: 3).xPlacement = .trailing
        return view
    }

    private func setupAppIconsView() -> NSView {
        let view = GridView([
            alignThumbnails,
            [AppearanceTab.makeSeparator(), AppearanceTab.makeSeparator()],
            showAppsWindows,
            showAppNamesWindowTitles,
            [AppearanceTab.makeSeparator(), AppearanceTab.makeSeparator()],
            [doneButton],
        ])
        // Merge separator/button row
        [1, 4, 5].forEach{ row in
            view.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: row, length: 1))
        }
        view.column(at: 0).xPlacement = .trailing
        view.column(at: 1).xPlacement = .leading
        view.cell(atColumnIndex: 0, rowIndex: 5).xPlacement = .trailing
        return view
    }

    private func setupTitlesView() -> NSView {
        let view = GridView([
            titleTruncation,
            [AppearanceTab.makeSeparator(), AppearanceTab.makeSeparator()],
            showAppsWindows,
            showAppNamesWindowTitles,
            [AppearanceTab.makeSeparator(), AppearanceTab.makeSeparator()],
            [doneButton],
        ])
        // Merge separator/button row
        [1, 4, 5].forEach{ row in
            view.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: row, length: 1))
        }
        view.column(at: 0).xPlacement = .trailing
        view.column(at: 1).xPlacement = .leading
        view.cell(atColumnIndex: 0, rowIndex: 5).xPlacement = .trailing
        return view
    }

    private func toggleAppNamesWindowTitles() {
        let label = showAppNamesWindowTitles[0] as? TextField
        let button = showAppNamesWindowTitles[1] as? NSControl
        if Preferences.showAppsWindows == .windows {
            label?.textColor = NSColor.textColor
            button?.isEnabled = true
        } else {
            label?.textColor = NSColor.gray
            button?.isEnabled = false
        }
    }

    @objc func onClicked(_ sender: NSButton) {
        if let sheetWindow = sender.window {
            if let mainWindow = sheetWindow.sheetParent {
                mainWindow.endSheet(sheetWindow)
            }
        }
    }
}

class Popover: NSPopover {
    static let shared = Popover()

    override init() {
        super.init()
        contentViewController = NSViewController()
        behavior = .semitransient
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func hide() {
        performClose(nil)
    }

    func show(event: NSEvent, positioningView: NSView, message: String) {
        hide()
        let view = NSView()

        let label = NSTextField(labelWithString: NSLocalizedString(message, comment: ""))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.isEditable = false
        label.isSelectable = true
        label.textColor = NSColor.gray
        label.font = NSFont.systemFont(ofSize: 12)
        view.addSubview(label)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 400),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
        ])
        contentViewController?.view = view

        // Convert the mouse location to the positioning view's coordinate system
        let locationInWindow = event.locationInWindow
        let locationInPositioningView = positioningView.convert(locationInWindow, from: nil)
        let rect = CGRect(origin: locationInPositioningView, size: .zero)

        show(relativeTo: rect, of: positioningView, preferredEdge: .minY)
    }
}

class AppearanceTab: NSObject, NSTabViewDelegate {
    static var shared = AppearanceTab()

    static var thumbnailAdvancedWindow: AdvancedSettingsWindow!
    static var appIconsAdvancedWindow: AdvancedSettingsWindow!
    static var titlesAdvancedWindow: AdvancedSettingsWindow!

    static var showHideCellWidth = CGFloat(400)
    static var showHideGrid: GridView!
    static var advancedButton: NSButton!

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
                }, labelPosition: .right, onMouseEntered: { event, view in
                    Popover.shared.show(event: event, positioningView: view, message: "AltTab will show if the window is currently minimized or fullscreen with a status icon.")
                }, onMouseExited: { event, view in
                    Popover.shared.hide()
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
                }, labelPosition: .right, onMouseEntered: { event, view in
                    Popover.shared.show(event: event, positioningView: view, message: "Some apps like Finder or Preview use standard tabs which act like independent windows. Some other apps like web browsers use custom tabs which act in unique ways and are not actual windows. AltTab can't list those separately.")
                }, onMouseExited: { event, view in
                    Popover.shared.hide()
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
        createAdvancedButton()
        thumbnailAdvancedWindow = AdvancedSettingsWindow(AppearanceModelPreference.thumbnails)
        appIconsAdvancedWindow = AdvancedSettingsWindow(AppearanceModelPreference.appIcons)
        titlesAdvancedWindow = AdvancedSettingsWindow(AppearanceModelPreference.titles)

        let generalGrid = setupGeneralTabView()
        let showHideGrid = setupShowHideTabView()
        let positionGrid = setupPositionTabView()
        let effectsGrid = setupEffectsTabView()

        let tabView = TabView([
            (NSLocalizedString("General", comment: ""), generalGrid),
            (NSLocalizedString("Show & Hide", comment: ""), showHideGrid),
            (NSLocalizedString("Position", comment: ""), positionGrid),
            (NSLocalizedString("Effects", comment: ""), effectsGrid),
        ])
        tabView.delegate = shared
        tabView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            generalGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.topAnchor),
            generalGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.centerXAnchor),

            showHideGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.topAnchor),
            showHideGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.centerXAnchor),

            positionGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.topAnchor),
            positionGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.centerXAnchor),

            effectsGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 3).view!.topAnchor),
            effectsGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 3).view!.centerXAnchor),
        ])
        return tabView
    }

    // Delegate method for tab view, it will be called when new tab is selected.
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        if let preferencesWindow = tabView.window as? PreferencesWindow {
            let id = NSToolbarItem.Identifier(rawValue: "appearance")
            preferencesWindow.toolbarItems[id]!.2 = tabView
            preferencesWindow.setContentSize(NSSize(width: preferencesWindow.largestTabWidth, height: tabView.fittingSize.height))
            preferencesWindow.contentView = tabView
        }
    }

    private static func setupGeneralTabView() -> NSView {
        let generalSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Appearance model:", comment: ""),
                    "appearanceModel", AppearanceModelPreference.allCases, extraAction: { _ in
                toggleAdvancedButton()
            }, buttonSpacing: 33),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Theme:", comment: ""), "theme", ThemePreference.allCases),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            LabelAndControl.makeLabelWithRadioButtons(NSLocalizedString("Appearance size:", comment: ""), "appearanceSize", AppearanceSizePreference.allCases),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            [advancedButton],
        ]
        let generalGrid = GridView(generalSettings)
        generalGrid.column(at: 0).xPlacement = .trailing
        // Merge cells for separator/advanced button
        [1, 3, 5, 6].forEach { row in
            generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 3), verticalRange: NSRange(location: row, length: 1))
        }
        // Advanced button
        generalGrid.cell(atColumnIndex: 0, rowIndex: 6).xPlacement = .trailing
        generalGrid.fit()
        return generalGrid
    }

    private static func setupShowHideTabView() -> NSView {
        var showHideSettings: [[NSView]] = [
            [createIllustratedImageView()],
        ]
        for item in showHideItems {
            showHideSettings.append(item.components)
        }
        showHideGrid = GridView(showHideSettings)
        // Set alignment
        setAlignment(showHideGrid)
        showHideGrid.column(at: 0).width = showHideCellWidth
        showHideGrid.rowSpacing = 0
        showHideGrid.row(at: 0).bottomPadding = GridView.padding
        addMouseHoverEffects(showHideGrid)
        showHideGrid.fit()
        return showHideGrid
    }

    private static func setupPositionTabView() -> NSView {
        var positionSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Show on:", comment: ""), "showOnScreen", ShowOnScreenPreference.allCases),
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("App vertical alignment:", comment: ""), "appVerticalAlignment", AppVerticalAlignmentPreference.allCases),
        ]
        let positionGrid = GridView(positionSettings)
        positionGrid.column(at: 0).xPlacement = .trailing
        positionGrid.row(at: 0).bottomPadding = TabView.padding
        positionGrid.fit()
        return positionGrid
    }

    private static func setupEffectsTabView() -> NSView {
        let effectsSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithSlider(NSLocalizedString("Apparition delay:", comment: ""), "windowDisplayDelay", 0, 2000, 11, false, "ms"),
            LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Fade out animation:", comment: ""), "fadeOutAnimation"),
        ]

        let effectsGrid = GridView(effectsSettings)
        effectsGrid.column(at: 0).xPlacement = .trailing
        effectsGrid.row(at: 0).bottomPadding = TabView.padding
        effectsGrid.column(at: 1).width = 200
        effectsGrid.fit()
        return effectsGrid
    }

    public static func makeSeparator(_ padding: CGFloat = 10) -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Create a container view to hold the separator and apply padding
        let wrapView = NSView()
        wrapView.translatesAutoresizingMaskIntoConstraints = false
        wrapView.addSubview(separator)

        // Set constraints for the separator within the container view
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: wrapView.topAnchor, constant: padding),
            separator.bottomAnchor.constraint(equalTo: wrapView.bottomAnchor, constant: -padding),
            separator.leadingAnchor.constraint(equalTo: wrapView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: wrapView.trailingAnchor)
        ])

        return wrapView
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
                    hoverView.onMouseEntered = { event, view in
                        hoverView.wantsLayer = true
                        hoverView.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.2).cgColor
                        hoverView.layer?.cornerRadius = 5.0

                        // Check the state of the checkbox using recursive search
                        let isChecked = findCheckboxState(in: contentView)
                        updateImageView(for: rowIndex, isChecked: isChecked, imageView: imageView)
                    }
                    hoverView.onMouseExited = { event, view in
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
        let wrapView = NSView()
        wrapView.translatesAutoresizingMaskIntoConstraints = false
        wrapView.wantsLayer = true
        wrapView.layer?.cornerRadius = 7.0
        wrapView.layer?.borderColor = NSColor.lightGray.withAlphaComponent(0.2).cgColor
        wrapView.layer?.borderWidth = 2.0

        let imageView = NSImageView(image: NSImage(named: name)!)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        wrapView.addSubview(imageView)

        let imageWidth = showHideCellWidth - 100
        let imageHeight = imageWidth / 1.6
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: imageWidth),
            imageView.heightAnchor.constraint(equalToConstant: imageHeight),
            imageView.topAnchor.constraint(equalTo: wrapView.topAnchor, constant: 4),
            imageView.bottomAnchor.constraint(equalTo: wrapView.bottomAnchor, constant: -4),
            imageView.leadingAnchor.constraint(equalTo: wrapView.leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: wrapView.trailingAnchor, constant: -4),
        ])

        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        imageView.layer?.cornerRadius = 7.0
        wrapView.identifier = NSUserInterfaceItemIdentifier("imageContainer")
        return wrapView
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

    private static func findButtons(in stackView: NSStackView) -> [NSButton] {
        var buttons: [NSButton] = []
        for subview in stackView.subviews {
            if let button = subview as? NSButton {
                buttons.append(button)
            } else if let nestedStackView = subview as? NSStackView {
                buttons.append(contentsOf: findButtons(in: nestedStackView))
            }
        }
        return buttons
    }

    private static func createAdvancedButton() {
        advancedButton = NSButton(title: getAdvancedButtonTitle(), target: self, action: #selector(showAdvancedSettings))
        advancedButton.widthAnchor.constraint(equalToConstant: 160).isActive = true
    }

    private static func getAdvancedButtonTitle() -> String {
        if Preferences.appearanceModel == .thumbnails {
            return NSLocalizedString("Thumbnails Advanced…", comment: "")
        } else if Preferences.appearanceModel == .appIcons {
            return NSLocalizedString("App Icons Advanced…", comment: "")
        } else if Preferences.appearanceModel == .titles {
            return NSLocalizedString("Titles Advanced…", comment: "")
        }
        return NSLocalizedString("Advanced…", comment: "")
    }

    private static func toggleAdvancedButton() {
        advancedButton.animator().title = getAdvancedButtonTitle()
    }

    @objc static func showAdvancedSettings() {
        guard let mainWindow = App.shared.mainWindow else { return }
        var sheetWindow: AdvancedSettingsWindow!
        if Preferences.appearanceModel == .thumbnails {
            sheetWindow = thumbnailAdvancedWindow
        } else if Preferences.appearanceModel == .appIcons {
            sheetWindow = appIconsAdvancedWindow
        } else if Preferences.appearanceModel == .titles {
            sheetWindow = titlesAdvancedWindow
        }
        mainWindow.beginSheet(sheetWindow, completionHandler: nil)
    }
}
