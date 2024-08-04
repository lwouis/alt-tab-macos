import Cocoa

struct ShowHideRowInfo {
    let rowId: String!
    var uncheckedImage: String!
    var checkedImage: String!
    var supportedModels: [AppearanceModelPreference]!
    var leftTitle: String!
    var subTitle: String?
    var rightViews = [NSView]()

    init() {
        self.rowId = UUID().uuidString
    }
}

class IllustratedImageThemeView: ClickHoverImageView {
    static let padding = CGFloat(4)
    var model: AppearanceModelPreference!
    var theme: String!

    init(_ model: AppearanceModelPreference, _ imageWidth: CGFloat) {
        // TODO: The appearance theme functionality has not been implemented yet.
        // We will implement it later; for now, use the light theme.
        let theme = "light"
        let imageName = IllustratedImageThemeView.getConcatenatedImageName(model, theme)
        let imageView = NSImageView(image: NSImage(named: imageName)!)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        imageView.layer?.cornerRadius = 7.0

        super.init(imageView: imageView)
        self.model = model
        self.theme = theme
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true
        self.layer?.cornerRadius = 7.0
        self.layer?.borderColor = NSColor.lightGray.withAlphaComponent(0.2).cgColor
        self.layer?.borderWidth = 2.0

        let imageWidth = imageWidth
        let imageHeight = imageWidth / 1.6
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: imageWidth),
            imageView.heightAnchor.constraint(equalToConstant: imageHeight),
            imageView.topAnchor.constraint(equalTo: self.topAnchor, constant: IllustratedImageThemeView.padding),
            imageView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -IllustratedImageThemeView.padding),
            imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: IllustratedImageThemeView.padding),
            imageView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -IllustratedImageThemeView.padding),
        ])
        onClick = { event, view in
            imageView.image = NSImage(named: imageName)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateImage(_ imageName: String) {
        imageView.image = NSImage(named: self.getModelThemeImageName(imageName))
    }

    static func getConcatenatedImageName(_ model: AppearanceModelPreference,
                                         _ theme: String ,
                                         _ imageName: String = "") -> String {
        if imageName.isEmpty {
            // thumbnails_light/app_icons_dark
            return model.image.name + "_" + theme
        }
        // thumbnails_show_app_badges_light/app_icons_show_app_badges_light
        return model.image.name + "_" + imageName + "_" + theme
    }

    func getModelThemeImageName(_ imageName: String = "") -> String {
        return IllustratedImageThemeView.getConcatenatedImageName(self.model, self.theme, imageName)
    }

}

class ShowHideIllustratedView {
    private let model: AppearanceModelPreference
    private var illustratedImageView: IllustratedImageThemeView!
    private var showHideRows = [ShowHideRowInfo]()
    private var grid: GridView!

    init(_ model: AppearanceModelPreference) {
        self.model = model
        setupItems()
        illustratedImageView = IllustratedImageThemeView(model, ModelAdvancedSettingsWindow.illustratedImageWidth)
    }

    func makeView() -> NSStackView {
        let table = TableGroupView(width: ModelAdvancedSettingsWindow.width)
        for row in showHideRows {
            if row.supportedModels.contains(model) {
                table.addRow(row.leftTitle, row.rightViews, onMouseEntered: { event, view in
                    self.updateImageView(rowId: row.rowId)
                })
            }
        }
        table.fit()

        let view = NSStackView()
        view.orientation = .vertical
        view.spacing = 5
        view.setViews([illustratedImageView, table], in: .leading)
        return view
    }

    private func setupItems() {
        var hideAppBadges = ShowHideRowInfo()
        hideAppBadges.uncheckedImage = "show_app_badges"
        hideAppBadges.checkedImage = "hide_app_badges"
        hideAppBadges.supportedModels = [.thumbnails, .appIcons, .titles]
        hideAppBadges.leftTitle = NSLocalizedString("Hide app badges", comment: "")
        hideAppBadges.rightViews.append(LabelAndControl.makeCheckbox("hideAppBadges", extraAction: { sender in
            self.onCheckboxClicked(sender: sender, rowId: hideAppBadges.rowId)
        }))
        showHideRows.append(hideAppBadges)

        var hideStatusIcons = ShowHideRowInfo()
        hideStatusIcons.uncheckedImage = "show_status_icons"
        hideStatusIcons.checkedImage = "hide_status_icons"
        hideStatusIcons.supportedModels = [.thumbnails, .titles]
        hideStatusIcons.leftTitle = NSLocalizedString("Hide status icons", comment: "")
        hideStatusIcons.subTitle = NSLocalizedString("AltTab will show if the window is currently minimized or fullscreen with a status icon.", comment: "")
        hideStatusIcons.rightViews.append(LabelAndControl.makeInfoButton(width: 15, height: 15, onMouseEntered: { event, view in
            Popover.shared.show(event: event, positioningView: view, message: hideStatusIcons.subTitle!)
        }, onMouseExited: { event, view in
            Popover.shared.hide()
        }))
        hideStatusIcons.rightViews.append(LabelAndControl.makeCheckbox("hideStatusIcons", extraAction: { sender in
            self.onCheckboxClicked(sender: sender, rowId: hideStatusIcons.rowId)
        }))
        showHideRows.append(hideStatusIcons)

        var hideSpaceNumberLabels = ShowHideRowInfo()
        hideSpaceNumberLabels.uncheckedImage = "show_space_number_labels"
        hideSpaceNumberLabels.checkedImage = "hide_space_number_labels"
        hideSpaceNumberLabels.supportedModels = [.thumbnails, .titles]
        hideSpaceNumberLabels.leftTitle = NSLocalizedString("Hide Space number labels", comment: "")
        hideSpaceNumberLabels.rightViews.append(LabelAndControl.makeCheckbox("hideSpaceNumberLabels", extraAction: { sender in
            self.onCheckboxClicked(sender: sender, rowId: hideSpaceNumberLabels.rowId)
        }))
        showHideRows.append(hideSpaceNumberLabels)

        var hideColoredCircles = ShowHideRowInfo()
        hideColoredCircles.uncheckedImage = "show_colored_circles"
        hideColoredCircles.checkedImage = "hide_colored_circles"
        hideColoredCircles.supportedModels = [.thumbnails]
        hideColoredCircles.leftTitle = NSLocalizedString("Hide colored circles on mouse hover", comment: "")
        hideColoredCircles.rightViews.append(LabelAndControl.makeCheckbox("hideColoredCircles", extraAction: { sender in
            self.onCheckboxClicked(sender: sender, rowId: hideColoredCircles.rowId)
        }))
        showHideRows.append(hideColoredCircles)

        var hideWindowlessApps = ShowHideRowInfo()
        hideWindowlessApps.uncheckedImage = "show_windowless_apps"
        hideWindowlessApps.checkedImage = "hide_windowless_apps"
        hideWindowlessApps.supportedModels = [.thumbnails, .appIcons, .titles]
        hideWindowlessApps.leftTitle = NSLocalizedString("Hide apps with no open window", comment: "")
        hideWindowlessApps.rightViews.append(LabelAndControl.makeCheckbox("hideWindowlessApps", extraAction: { sender in
            self.onCheckboxClicked(sender: sender, rowId: hideWindowlessApps.rowId)
        }))
        showHideRows.append(hideWindowlessApps)

        var showTabsAsWindows = ShowHideRowInfo()
        showTabsAsWindows.uncheckedImage = "hide_tabs_as_windows"
        showTabsAsWindows.checkedImage = "show_tabs_as_windows"
        showTabsAsWindows.supportedModels = [.thumbnails, .appIcons, .titles]
        showTabsAsWindows.leftTitle = NSLocalizedString("Show standard tabs as windows", comment: "")
        showTabsAsWindows.subTitle = NSLocalizedString("Some apps like Finder or Preview use standard tabs which act like independent windows. Some other apps like web browsers use custom tabs which act in unique ways and are not actual windows. AltTab can't list those separately.", comment: "")
        showTabsAsWindows.rightViews.append(LabelAndControl.makeInfoButton(width: 15, height: 15, onMouseEntered: { event, view in
            Popover.shared.show(event: event, positioningView: view, message: showTabsAsWindows.subTitle!)
        }, onMouseExited: { event, view in
            Popover.shared.hide()
        }))
        showTabsAsWindows.rightViews.append(LabelAndControl.makeCheckbox("showTabsAsWindows", extraAction: { sender in
            self.onCheckboxClicked(sender: sender, rowId: showTabsAsWindows.rowId)
        }))
        showHideRows.append(showTabsAsWindows)

        var previewFocusedWindow = ShowHideRowInfo()
        previewFocusedWindow.uncheckedImage = "hide_preview_focused_window"
        previewFocusedWindow.checkedImage = "show_preview_focused_window"
        previewFocusedWindow.supportedModels = [.thumbnails, .appIcons, .titles]
        previewFocusedWindow.leftTitle = NSLocalizedString("Preview selected window", comment: "")
        previewFocusedWindow.rightViews.append(LabelAndControl.makeCheckbox("previewFocusedWindow", extraAction: { sender in
            self.onCheckboxClicked(sender: sender, rowId: previewFocusedWindow.rowId)
        }))
        showHideRows.append(previewFocusedWindow)
    }

    /// Handles the event when a checkbox is clicked.
    /// Updates the image view based on the state of the checkbox.
    ///
    /// - Parameters:
    ///   - sender: The checkbox button that was clicked.
    ///   - rowId: The identifier for the row associated with the checkbox.
    private func onCheckboxClicked(sender: NSControl, rowId: String) {
        if let sender = sender as? NSButton {
            let isChecked = sender.state == .on
            updateImageView(rowId: rowId, isChecked: isChecked)
        }
    }

    private func updateImageView(rowId: String, isChecked: Bool) {
        let row = showHideRows.first { $0.rowId.elementsEqual(rowId) }
        let imageName = isChecked ? row?.checkedImage : row?.uncheckedImage
        illustratedImageView.updateImage(imageName!)
    }

    private func updateImageView(rowId: String) {
        let row = showHideRows.first { $0.rowId.elementsEqual(rowId) }
        row?.rightViews.forEach { view in
            if let checkbox = view as? NSButton {
                let isChecked = checkbox.state == .on
                let imageName = isChecked ? row?.checkedImage : row?.uncheckedImage
                illustratedImageView.updateImage(imageName!)
            }
        }
    }

}

class ModelAdvancedSettingsWindow: NSWindow {
    static let width = CGFloat(512)
    static let illustratedImageWidth = width - 50
    static let spacing = CGFloat(5)

    var model: AppearanceModelPreference = .thumbnails
    var illustratedImageView: IllustratedImageThemeView!
    var alignThumbnails: TableGroupView.Row!
    var titleTruncation: TableGroupView.Row!
    var showAppsWindows: TableGroupView.Row!
    var showAppNamesWindowTitles: TableGroupView.Row!
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
        illustratedImageView = IllustratedImageThemeView(model, ModelAdvancedSettingsWindow.illustratedImageWidth)
        alignThumbnails = TableGroupView.Row(leftTitle: NSLocalizedString("Align windows:", comment: ""),
                rightViews: [LabelAndControl.makeDropdown(
                        "alignThumbnails", AlignThumbnailsPreference.allCases, extraAction: { _ in
            self.showAlignThumbnailsIllustratedImage()
        })])
        titleTruncation = TableGroupView.Row(leftTitle: NSLocalizedString("Window title truncation:", comment: ""),
                rightViews: [LabelAndControl.makeDropdown("titleTruncation", TitleTruncationPreference.allCases)])
        showAppsWindows = TableGroupView.Row(leftTitle: NSLocalizedString("Show running:", comment: ""),
                rightViews: LabelAndControl.makeRadioButtons(ShowAppsWindowsPreference.allCases,
                        "showAppsWindows", extraAction: { _ in
            self.toggleAppNamesWindowTitles()
            self.showAppsOrWindowsIllustratedImage()
        }))
        showAppNamesWindowTitles = TableGroupView.Row(leftTitle: NSLocalizedString("Show titles:", comment: ""),
                rightViews: [LabelAndControl.makeDropdown(
                        "showAppNamesWindowTitles", ShowAppNamesWindowTitlesPreference.allCases, extraAction: { _ in
            self.showAppsOrWindowsIllustratedImage()
        })])

        doneButton = NSButton(title: NSLocalizedString("Done", comment: ""), target: self, action: #selector(onClicked(_:)))
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.focusRingType = .none
        if #available(macOS 10.14, *) {
            doneButton.bezelColor = NSColor.controlAccentColor
        }

        let showHideView = ShowHideIllustratedView(model).makeView()

        var advancedView: NSView!
        if model == .thumbnails {
            advancedView = makeThumbnailsView()
        } else if model == .appIcons {
            advancedView = makeAppIconsView()
        } else if model == .titles {
            advancedView = makeTitlesView()
        }
        let tabView = TabView([
            (NSLocalizedString("Show & Hide", comment: ""), showHideView),
            (NSLocalizedString("Advanced", comment: ""), advancedView),
        ])
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.widthAnchor.constraint(equalToConstant: ModelAdvancedSettingsWindow.width + 50).isActive = true

        showHideView.translatesAutoresizingMaskIntoConstraints = false
        showHideView.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.topAnchor).isActive = true
        showHideView.bottomAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.bottomAnchor).isActive = true
        showHideView.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.centerXAnchor).isActive = true
        showHideView.centerYAnchor.constraint(equalTo: tabView.tabViewItem(at: 0).view!.centerYAnchor).isActive = true

        advancedView.translatesAutoresizingMaskIntoConstraints = false
        advancedView.topAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.topAnchor).isActive = true
        advancedView.bottomAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.bottomAnchor).isActive = true
        advancedView.centerXAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.centerXAnchor).isActive = true
        advancedView.centerYAnchor.constraint(equalTo: tabView.tabViewItem(at: 1).view!.centerYAnchor).isActive = true

        let grid = GridView([
            [tabView],
            [doneButton],
        ])
        grid.cell(atColumnIndex: 0, rowIndex: 1).xPlacement = .center

        setContentSize(grid.fittingSize)
        contentView = grid
    }

    private func makeThumbnailsView() -> NSStackView {
        let table = TableGroupView(width: ModelAdvancedSettingsWindow.width)
        table.addRow(alignThumbnails, onMouseEntered: { event, view in
            self.showAlignThumbnailsIllustratedImage()
        })
        table.addRow(titleTruncation)
        table.fit()

        let view = NSStackView()
        view.orientation = .vertical
        view.spacing = ModelAdvancedSettingsWindow.spacing
        view.setViews([illustratedImageView, table], in: .leading)
        return view
    }

    private func makeAppIconsView() -> NSStackView {
        let table1 = TableGroupView(width: ModelAdvancedSettingsWindow.width)
        table1.addRow(showAppsWindows, onMouseEntered: { event, view in
            self.showAppsOrWindowsIllustratedImage()
        })
        table1.addRow(showAppNamesWindowTitles, onMouseEntered: { event, view in
            self.showAppsOrWindowsIllustratedImage()
        })
        table1.fit()

        let table2 = TableGroupView(width: ModelAdvancedSettingsWindow.width)
        table2.addRow(alignThumbnails, onMouseEntered: { event, view in
            self.showAlignThumbnailsIllustratedImage()
        })
        table2.fit()

        let view = NSStackView()
        view.orientation = .vertical
        view.spacing = ModelAdvancedSettingsWindow.spacing
        view.setViews([illustratedImageView, table1, table2], in: .leading)

        toggleAppNamesWindowTitles()
        return view
    }

    private func makeTitlesView() -> NSStackView {
        let table1 = TableGroupView(width: ModelAdvancedSettingsWindow.width)
        table1.addRow(showAppsWindows, onMouseEntered: { event, view in
            self.showAppsOrWindowsIllustratedImage()
        })
        table1.addRow(showAppNamesWindowTitles, onMouseEntered: { event, view in
            self.showAppsOrWindowsIllustratedImage()
        })
        table1.fit()

        let table2 = TableGroupView(width: ModelAdvancedSettingsWindow.width)
        table2.addRow(alignThumbnails, onMouseEntered: { event, view in
            self.showAlignThumbnailsIllustratedImage()
        })
        table2.fit()

        let view = NSStackView()
        view.orientation = .vertical
        view.spacing = ModelAdvancedSettingsWindow.spacing
        view.setViews([illustratedImageView, table1, table2], in: .leading)

        toggleAppNamesWindowTitles()
        return view
    }

    private func toggleAppNamesWindowTitles() {
//        let label = showAppNamesWindowTitles[0] as? TextField
        let button = showAppNamesWindowTitles.rightViews[0] as? NSControl
        if Preferences.showAppsWindows == .windows {
//            label?.textColor = NSColor.textColor
            button?.isEnabled = true
        } else {
//            label?.textColor = NSColor.gray
            button?.isEnabled = false
        }
    }

    private func showAlignThumbnailsIllustratedImage() {
        self.illustratedImageView.updateImage(Preferences.alignThumbnails.image.name)
    }

    private func showAppsOrWindowsIllustratedImage() {
        var imageName = ShowAppNamesWindowTitlesPreference.windowTitles.image.name
        if Preferences.showAppsWindows == .applications || Preferences.showAppNamesWindowTitles == .applicationNames {
            imageName = ShowAppNamesWindowTitlesPreference.applicationNames.image.name
        } else if Preferences.showAppNamesWindowTitles == .applicationNamesAndWindowTitles {
            imageName = ShowAppNamesWindowTitlesPreference.applicationNamesAndWindowTitles.image.name
        }
        self.illustratedImageView.updateImage(imageName)
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

        let label = NSTextField(labelWithString: message)
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

        show(relativeTo: rect, of: positioningView, preferredEdge: .minX)
    }
}

class AppearanceTab: NSObject {
    static var shared = AppearanceTab()

    static var advancedButton: NSButton!

    static func initTab() -> NSView {
        createAdvancedButton()

        let generalGrid = makeGeneralTabView()
        let positionGrid = makePositionTabView()
        let effectsGrid = makeEffectsTabView()

        let view = NSView()
        let tabView = TabView([
            (NSLocalizedString("General", comment: ""), generalGrid),
            (NSLocalizedString("Position", comment: ""), positionGrid),
            (NSLocalizedString("Effects", comment: ""), effectsGrid),
        ])
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

    private static func makeGeneralTabView() -> NSView {
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

    private static func makePositionTabView() -> NSView {
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

    private static func makeEffectsTabView() -> NSView {
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

    public static func makeSeparator(_ topPadding: CGFloat = 7, _ bottomPadding: CGFloat = -7) -> NSView {
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
            separator.trailingAnchor.constraint(equalTo: wrapView.trailingAnchor),
            separator.widthAnchor.constraint(equalTo: wrapView.widthAnchor),
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

    @objc static func toggleAdvancedButton() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(handleToggleAdvancedButton), object: nil)
        self.perform(#selector(handleToggleAdvancedButton), with: nil, afterDelay: 0.1)
    }

    @objc static func handleToggleAdvancedButton() {
        advancedButton.animator().title = getAdvancedButtonTitle()
    }

    @objc static func showAdvancedSettings() {
        let advancedSettingsSheetWindow = ModelAdvancedSettingsWindow(Preferences.appearanceModel)
        App.app.preferencesWindow.beginSheet(advancedSettingsSheetWindow)
    }
}
