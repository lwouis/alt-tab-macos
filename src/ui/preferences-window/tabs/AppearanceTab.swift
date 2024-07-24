import Cocoa

struct ShowHideRowInfo {
    let rowId: String!
    var uncheckedImageLight: String!  // Light mode image when the item is unchecked
    var checkedImageLight: String!    // Light mode image when the item is checked
    var uncheckedImageDark: String!   // Dark mode image when the item is unchecked
    var checkedImageDark: String!     // Dark mode image when the item is checked
    var components: [NSView]!        // UI components associated with this item
    var supportedModels: [AppearanceModelPreference]!

    init() {
        self.rowId = UUID().uuidString
    }
}

class ShowHideIllustratedView {
    private let model: AppearanceModelPreference

    private let showHideCellWidth = CGFloat(400)
    private var showHideRows = [ShowHideRowInfo]()
    private var grid: GridView!

    init(_ model: AppearanceModelPreference) {
        self.model = model
        setupItems()
    }

    func setupView() -> GridView {
        // Add the illustrated image first
        var settings: [[NSView]] = [
            [makeIllustratedImageView(model)],
        ]
        var modelToRows = [Int: ShowHideRowInfo]()
        var index = 1
        for row in showHideRows {
            if row.supportedModels.contains(model) {
                settings.append(row.components)
                // match the row index of the grid
                modelToRows[index] = row
                index += 1
            }
        }
        grid = GridView(settings)
        setAlignment()
        grid.column(at: 0).width = showHideCellWidth
        grid.rowSpacing = 0
        grid.row(at: 0).bottomPadding = GridView.padding
        addMouseHoverEffects(modelToRows: modelToRows)
        grid.fit()
        return grid
    }

    private func setupItems() {
        var hideAppBadges = ShowHideRowInfo()
        hideAppBadges.uncheckedImageLight = "show_app_badges_light"
        hideAppBadges.checkedImageLight = "hide_app_badges_light"
        hideAppBadges.uncheckedImageDark = "show_app_badges_dark"
        hideAppBadges.checkedImageDark = "hide_app_badges_dark"
        hideAppBadges.supportedModels = [.thumbnails, .appIcons, .titles]
        hideAppBadges.components = LabelAndControl.makeLabelWithCheckbox(
                NSLocalizedString("Hide app badges", comment: ""),
                "hideAppBadges", extraAction: { sender in
            let button = sender as! NSButton
            self.onCheckboxClicked(sender: button, rowId: hideAppBadges.rowId)
        }, labelPosition: .right)
        showHideRows.append(hideAppBadges)

        var hideStatusIcons = ShowHideRowInfo()
        hideStatusIcons.uncheckedImageLight = "show_status_icons_light"
        hideStatusIcons.checkedImageLight = "hide_status_icons_light"
        hideStatusIcons.uncheckedImageDark = "show_status_icons_dark"
        hideStatusIcons.checkedImageDark = "hide_status_icons_dark"
        hideStatusIcons.supportedModels = [.thumbnails, .titles]
        hideStatusIcons.components = LabelAndControl.makeLabelWithCheckboxAndInfoButton(
                NSLocalizedString("Hide status icons", comment: ""),
                "hideStatusIcons", extraAction: { sender in
            let button = sender as! NSButton
            self.onCheckboxClicked(sender: button, rowId: hideStatusIcons.rowId)
        }, labelPosition: .right, onMouseEntered: { event, view in
            Popover.shared.show(event: event, positioningView: view, message: "AltTab will show if the window is currently minimized or fullscreen with a status icon.")
        }, onMouseExited: { event, view in
            Popover.shared.hide()
        })
        showHideRows.append(hideStatusIcons)

        var hideSpaceNumberLabels = ShowHideRowInfo()
        hideSpaceNumberLabels.uncheckedImageLight = "show_space_number_labels_light"
        hideSpaceNumberLabels.checkedImageLight = "hide_space_number_labels_light"
        hideSpaceNumberLabels.uncheckedImageDark = "show_space_number_labels_dark"
        hideSpaceNumberLabels.checkedImageDark = "hide_space_number_labels_dark"
        hideSpaceNumberLabels.supportedModels = [.thumbnails, .titles]
        hideSpaceNumberLabels.components = LabelAndControl.makeLabelWithCheckbox(
                NSLocalizedString("Hide Space number labels", comment: ""),
                "hideSpaceNumberLabels", extraAction: { sender in
            let button = sender as! NSButton
            self.onCheckboxClicked(sender: button, rowId: hideSpaceNumberLabels.rowId)
        }, labelPosition: .right)
        showHideRows.append(hideSpaceNumberLabels)

        var hideColoredCircles = ShowHideRowInfo()
        hideColoredCircles.uncheckedImageLight = "show_colored_circles_light"
        hideColoredCircles.checkedImageLight = "hide_colored_circles_light"
        hideColoredCircles.uncheckedImageDark = "show_colored_circles_dark"
        hideColoredCircles.checkedImageDark = "hide_colored_circles_dark"
        hideColoredCircles.supportedModels = [.thumbnails]
        hideColoredCircles.components = LabelAndControl.makeLabelWithCheckbox(
                NSLocalizedString("Hide colored circles on mouse hover", comment: ""),
                "hideColoredCircles", extraAction: { sender in
            let button = sender as! NSButton
            self.onCheckboxClicked(sender: button, rowId: hideColoredCircles.rowId)
        }, labelPosition: .right)
        showHideRows.append(hideColoredCircles)

        var hideWindowlessApps = ShowHideRowInfo()
        hideWindowlessApps.uncheckedImageLight = "show_windowless_apps_light"
        hideWindowlessApps.checkedImageLight = "hide_windowless_apps_light"
        hideWindowlessApps.uncheckedImageDark = "show_windowless_apps_dark"
        hideWindowlessApps.checkedImageDark = "hide_windowless_apps_dark"
        hideWindowlessApps.supportedModels = [.thumbnails, .appIcons, .titles]
        hideWindowlessApps.components = LabelAndControl.makeLabelWithCheckbox(
                NSLocalizedString("Hide apps with no open window", comment: ""),
                "hideWindowlessApps", extraAction: { sender in
            let button = sender as! NSButton
            self.onCheckboxClicked(sender: button, rowId: hideWindowlessApps.rowId)
        }, labelPosition: .right)
        showHideRows.append(hideWindowlessApps)

        var showTabsAsWindows = ShowHideRowInfo()
        showTabsAsWindows.uncheckedImageLight = "hide_tabs_as_windows_light"
        showTabsAsWindows.checkedImageLight = "show_tabs_as_windows_light"
        showTabsAsWindows.uncheckedImageDark = "hide_tabs_as_windows_dark"
        showTabsAsWindows.checkedImageDark = "show_tabs_as_windows_dark"
        showTabsAsWindows.supportedModels = [.thumbnails, .appIcons, .titles]
        showTabsAsWindows.components = LabelAndControl.makeLabelWithCheckboxAndInfoButton(
                NSLocalizedString("Show standard tabs as windows", comment: ""),
                "showTabsAsWindows", extraAction: { sender in
            let button = sender as! NSButton
            self.onCheckboxClicked(sender: button, rowId: showTabsAsWindows.rowId)
        }, labelPosition: .right, onMouseEntered: { event, view in
            Popover.shared.show(event: event, positioningView: view, message: "Some apps like Finder or Preview use standard tabs which act like independent windows. Some other apps like web browsers use custom tabs which act in unique ways and are not actual windows. AltTab can't list those separately.")
        }, onMouseExited: { event, view in
            Popover.shared.hide()
        })
        showHideRows.append(showTabsAsWindows)

        var previewFocusedWindow = ShowHideRowInfo()
        previewFocusedWindow.uncheckedImageLight = "hide_preview_focused_window_light"
        previewFocusedWindow.checkedImageLight = "show_preview_focused_window_light"
        previewFocusedWindow.uncheckedImageDark = "hide_preview_focused_window_dark"
        previewFocusedWindow.checkedImageDark = "show_preview_focused_window_dark"
        previewFocusedWindow.supportedModels = [.thumbnails, .appIcons, .titles]
        previewFocusedWindow.components = LabelAndControl.makeLabelWithCheckbox(
                NSLocalizedString("Preview selected window", comment: ""),
                "previewFocusedWindow", extraAction: { sender in
            let button = sender as! NSButton
            self.onCheckboxClicked(sender: button, rowId: previewFocusedWindow.rowId)
        }, labelPosition: .right)
        showHideRows.append(previewFocusedWindow)
    }


    private func addMouseHoverEffects(modelToRows: [Int: ShowHideRowInfo]) {
        // Ignore the first row that stores the image
        guard let imageContainer = grid.cell(atColumnIndex: 0, rowIndex: 0).contentView,
              let imageView = imageContainer.subviews.first as? NSImageView
        else {
            return
        }
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
                        let isChecked = self.findCheckboxState(in: contentView)
                        self.updateImageView(rowId: modelToRows[rowIndex]!.rowId, isChecked: isChecked, imageView: imageView)
                    }
                    hoverView.onMouseExited = { event, view in
                        hoverView.layer?.backgroundColor = NSColor.clear.cgColor
                    }
                    hoverView.addSubview(contentView)
                    contentView.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        hoverView.widthAnchor.constraint(equalToConstant: grid.column(at: 0).width - GridView.padding),
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

    private func makeIllustratedImageView(_ model: AppearanceModelPreference) -> NSView {
        // TODO: The appearance theme functionality has not been implemented yet.
        // We will implement it later; for now, use the light theme.
        let imageName = model.image.name + "_light"
        let imageView = NSImageView(image: NSImage(named: imageName)!)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        imageView.layer?.cornerRadius = 7.0

        let wrapView = ClickHoverImageView(imageView: imageView)
        wrapView.translatesAutoresizingMaskIntoConstraints = false
        wrapView.wantsLayer = true
        wrapView.layer?.cornerRadius = 7.0
        wrapView.layer?.borderColor = NSColor.lightGray.withAlphaComponent(0.2).cgColor
        wrapView.layer?.borderWidth = 2.0

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
        wrapView.onClick = { event, view in
            wrapView.imageView.image = NSImage(named: imageName)
        }
        return wrapView
    }

    /// Sets the alignment for cells in a grid.
    /// The cells in the first row are centered horizontally,
    /// while the cells in all other rows are aligned to the leading edge.
    private func setAlignment() {
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

    /// Handles the event when a checkbox is clicked.
    /// Updates the image view based on the state of the checkbox.
    ///
    /// - Parameters:
    ///   - sender: The checkbox button that was clicked.
    ///   - rowId: The identifier for the row associated with the checkbox.
    private func onCheckboxClicked(sender: NSButton, rowId: String) {
        guard let imageContainer = grid.cell(atColumnIndex: 0, rowIndex: 0).contentView,
              let imageView = imageContainer.subviews.first as? NSImageView
        else {
            return
        }

        let isChecked = sender.state == .on
        updateImageView(rowId: rowId, isChecked: isChecked, imageView: imageView)
    }

    private func updateImageView(rowId: String, isChecked: Bool, imageView: NSImageView) {
        // TODO: The appearance theme functionality has not been implemented yet.
        // We will implement it later; for now, use the light theme.
        let row = showHideRows.first { $0.rowId.elementsEqual(rowId) }
        var imageName = isChecked ? row?.checkedImageLight : row?.uncheckedImageLight
        // e.g. thumbnails_show_app_badges_light/app_icons_show_app_badges_light
        imageName = model.image.name + "_" + imageName!
        imageView.image = NSImage(named: imageName!)
    }


    private func findCheckboxState(in view: NSView) -> Bool {
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

    /// Recursively finds all `NSButton` instances within a given `NSStackView` and its nested stack views.
    ///
    /// - Parameter stackView: The root `NSStackView` to search for buttons.
    /// - Returns: An array of `NSButton` instances found within the stack view and its nested stack views.
    private func findButtons(in stackView: NSStackView) -> [NSButton] {
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
}

class ModelAdvancedSettingsWindow: NSWindow, NSTabViewDelegate {
    var model: AppearanceModelPreference = .thumbnails
    var alignThumbnails: [NSView]!
    var titleTruncation: [NSView]!
    var showAppsWindows: [NSView]!
    var showAppNamesWindowTitles: [NSView]!
    var doneButton: NSButton!

    convenience init(_ model: AppearanceModelPreference) {
        self.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        self.model = model
        setupWindow()
        setupView()
    }

    private func setupWindow() {
        hidesOnDeactivate = false
    }

    private func setupView() {
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

        let showHideGrid = ShowHideIllustratedView(model).setupView()

        var advancedView: NSView!
        if model == .thumbnails {
            advancedView = setupThumbnailsView()
        } else if model == .appIcons {
            advancedView = setupAppIconsView()
        } else if model == .titles {
            advancedView = setupTitlesView()
        }
        let tabView = TabView([
            (NSLocalizedString("Show & Hide", comment: ""), showHideGrid),
            (NSLocalizedString("Advanced", comment: ""), advancedView),
        ])
        tabView.delegate = self
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.widthAnchor.constraint(equalToConstant: tabView.maxIntrinsicContentSize().width + GridView.padding).isActive = true

        showHideGrid.translatesAutoresizingMaskIntoConstraints = false
        showHideGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.topAnchor).isActive = true
        showHideGrid.bottomAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.bottomAnchor).isActive = true
        showHideGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.centerXAnchor).isActive = true

        advancedView.translatesAutoresizingMaskIntoConstraints = false
        advancedView.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.topAnchor).isActive = true
        advancedView.bottomAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.bottomAnchor).isActive = true
        advancedView.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.centerXAnchor).isActive = true

        let grid = GridView([
            [tabView],
            [doneButton],
        ])
        grid.cell(atColumnIndex: 0, rowIndex: 1).xPlacement = .center

        setContentSize(grid.fittingSize)
        contentView = grid
    }

    // Delegate method for tab view, it will be called when new tab is selected.
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        if let grid = tabView.superview as? GridView, let tabView = tabView as? TabView {
            if let window = tabView.window as? ModelAdvancedSettingsWindow {
                // Adjust the size of the tabView to fit its content
                tabView.widthAnchor.constraint(equalToConstant: tabView.maxIntrinsicContentSize().width + GridView.padding).isActive = true
                let newSize = grid.fittingSize

                if let parentWindow = window.sheetParent {
                    // Get parent window frame
                    let parentFrame = parentWindow.frame
                    var frame = window.frame
                    frame.size.height = newSize.height
                    frame.origin.y = parentFrame.origin.y + parentFrame.height - newSize.height

                    window.setFrame(frame, display: true, animate: true)
                    window.layoutIfNeeded()
                }
            }
        }
    }

    private func setupThumbnailsView() -> NSView {
        let view = GridView([
            alignThumbnails,
            titleTruncation,
        ])

//        view.column(at: 0).width = 150
//        view.column(at: 1).width = 150
        view.column(at: 0).xPlacement = .trailing
        view.column(at: 1).xPlacement = .leading
        return view
    }

    private func setupAppIconsView() -> NSView {
        let view = GridView([
            alignThumbnails,
            [AppearanceTab.makeSeparator(), AppearanceTab.makeSeparator()],
            showAppsWindows,
            showAppNamesWindowTitles,
        ])
        view.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: 1, length: 1))
//        view.column(at: 0).width = 150
//        view.column(at: 1).width = 150
        view.column(at: 0).xPlacement = .trailing
        view.column(at: 1).xPlacement = .leading
        return view
    }

    private func setupTitlesView() -> NSView {
        let view = GridView([
            titleTruncation,
            [AppearanceTab.makeSeparator(), AppearanceTab.makeSeparator()],
            showAppsWindows,
            showAppNamesWindowTitles,
        ])
        view.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: 1, length: 1))
//        view.column(at: 0).width = 200
//        view.column(at: 1).width = 200
        view.column(at: 0).xPlacement = .trailing
        view.column(at: 1).xPlacement = .leading
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

    static var advancedButton: NSButton!

    static func initTab() -> NSView {
        createAdvancedButton()

        let generalGrid = setupGeneralTabView()
        let positionGrid = setupPositionTabView()
        let effectsGrid = setupEffectsTabView()

        let view = NSView()
        let tabView = TabView([
            (NSLocalizedString("General", comment: ""), generalGrid),
            (NSLocalizedString("Position", comment: ""), positionGrid),
            (NSLocalizedString("Effects", comment: ""), effectsGrid),
        ])
        tabView.delegate = shared
        tabView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(tabView)
        view.translatesAutoresizingMaskIntoConstraints = false
        tabView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        view.heightAnchor.constraint(equalToConstant: tabView.fittingSize.height + GridView.padding).isActive = true

        NSLayoutConstraint.activate([
            generalGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.topAnchor),
            generalGrid.bottomAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.bottomAnchor),
            generalGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.centerXAnchor),

            positionGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.topAnchor),
            positionGrid.bottomAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.bottomAnchor),
            positionGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.centerXAnchor),

            effectsGrid.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.topAnchor),
            effectsGrid.bottomAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.bottomAnchor),
            effectsGrid.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 2).view!.centerXAnchor),
        ])
        
        return view
    }

    // Delegate method for tab view, it will be called when new tab is selected.
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
//        tabView.topAnchor.constraint(equalTo: tabView.superview!.topAnchor).isActive = true
//        tabView.superview?.heightAnchor.constraint(equalToConstant: tabView.intrinsicContentSize.height).isActive = true
//
//        if let preferencesWindow = tabView.window as? PreferencesWindow {
//            let id = NSToolbarItem.Identifier(rawValue: "appearance")
//            preferencesWindow.toolbarItems[id]!.2 = tabView
//            preferencesWindow.setContentSize(NSSize(width: preferencesWindow.largestTabWidth, height: tabView.fittingSize.height))
//            preferencesWindow.contentView = tabView
//        }
    }

    private static func setupGeneralTabView() -> NSView {
        let generalSettings: [[NSView]] = [
            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Appearance model:", comment: ""),
                    "appearanceModel", AppearanceModelPreference.allCases, extraAction: { _ in
                toggleAdvancedButton()
            }, buttonSpacing: 33),
//            [makeSeparator(), makeSeparator(), makeSeparator()],
//            LabelAndControl.makeLabelWithImageRadioButtons(NSLocalizedString("Theme:", comment: ""), "theme", ThemePreference.allCases),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            LabelAndControl.makeLabelWithRadioButtons(NSLocalizedString("Appearance size:", comment: ""), "appearanceSize", AppearanceSizePreference.allCases),
            [makeSeparator(), makeSeparator(), makeSeparator()],
            [advancedButton],
        ]
        let generalGrid = GridView(generalSettings)
        generalGrid.column(at: 0).xPlacement = .trailing
        // Merge cells for separator/advanced button
        [1, 3, 4].forEach { row in
            generalGrid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 3), verticalRange: NSRange(location: row, length: 1))
        }
        // Advanced button
        generalGrid.cell(atColumnIndex: 0, rowIndex: 4).xPlacement = .trailing
        generalGrid.fit()
        return generalGrid
    }

    private static func setupPositionTabView() -> NSView {
        let positionSettings: [[NSView]] = [
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

    public static func makeSeparator(_ topPadding: CGFloat = 10, _ bottomPadding: CGFloat = -10) -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Create a container view to hold the separator and apply padding
        let wrapView = NSView()
        wrapView.translatesAutoresizingMaskIntoConstraints = false
        wrapView.addSubview(separator)

        // Set constraints for the separator within the container view
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: wrapView.topAnchor, constant: topPadding),
            separator.bottomAnchor.constraint(equalTo: wrapView.bottomAnchor, constant: bottomPadding),
            separator.leadingAnchor.constraint(equalTo: wrapView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: wrapView.trailingAnchor)
        ])

        return wrapView
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
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            advancedButton.animator().title = getAdvancedButtonTitle()
            advancedButton.displayIfNeeded()
        })
    }

    @objc static func showAdvancedSettings() {
        let advancedSettingsSheetWindow = ModelAdvancedSettingsWindow(Preferences.appearanceModel)
        App.app.preferencesWindow.beginSheet(advancedSettingsSheetWindow)
    }
}
