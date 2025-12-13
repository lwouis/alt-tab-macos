import Cocoa

class IBeamTextField: NSTextField {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: NSCursor.iBeam)
    }
}

struct ShowHideRowInfo {
    var rowId: String!
    var uncheckedImage: String!
    var checkedImage: String!
    var supportedStyles: [AppearanceStylePreference]!
    var subTitle: String?
    var leftViews = [NSView]()
    var rightViews = [NSView]()
}

class IllustratedImageThemeView: ClickHoverImageView {
    override var acceptsFirstResponder: Bool { false }
    static let padding = CGFloat(4)
    var style: AppearanceStylePreference!
    var theme: String!
    var imageName: String!
    var isFocused: Bool = false

    init(_ style: AppearanceStylePreference, _ width: CGFloat) {
        // TODO: The appearance theme functionality has not been implemented yet.
        // We will implement it later; for now, use the light theme.
        let theme = "light"
        let imageName = IllustratedImageThemeView.getConcatenatedImageName(style, theme)
        let imageView = NSImageView(image: NSImage(named: imageName)!)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer!.masksToBounds = true
        imageView.layer!.cornerRadius = TableGroupView.cornerRadius
        super.init(infoCircle: imageView)
        self.style = style
        self.theme = theme
        self.imageName = imageName
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        let imageWidth = width - IllustratedImageThemeView.padding
        let imageHeight = imageWidth / 1.6
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: imageWidth),
            imageView.heightAnchor.constraint(equalToConstant: imageHeight),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: IllustratedImageThemeView.padding),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -IllustratedImageThemeView.padding),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: IllustratedImageThemeView.padding),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -IllustratedImageThemeView.padding),
        ])
        highlight(false)
        onClick = { (event, view) in
            self.highlight(false)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    private func setBorder() {
        layer?.cornerRadius = TableGroupView.cornerRadius + 3
        layer?.borderColor = isFocused ? NSColor.systemAccentColor.cgColor : NSColor.lightGray.cgColor
        layer?.borderWidth = 3
    }

    private func setFocused(_ focused: Bool) {
        isFocused = focused
    }

    func highlight(_ highlighted: Bool, _ imageName: String = "") {
        if highlighted && imageName.isEmpty {
            return
        }
        setFocused(highlighted)
        setBorder()
        if highlighted {
            updateImage(imageName)
        } else {
            (infoCircle as! NSImageView).image = NSImage(named: self.imageName)
        }
    }

    private func updateImage(_ imageName: String) {
        (infoCircle as! NSImageView).image = NSImage(named: getStyleThemeImageName(imageName))
    }

    static func getConcatenatedImageName(_ style: AppearanceStylePreference,
                                         _ theme: String,
                                         _ imageName: String = "") -> String {
        if imageName.isEmpty {
            // thumbnails_light/app_icons_dark
            return style.image.name + "_" + theme
        }
        // thumbnails_show_app_badges_light/app_icons_show_app_badges_light
        return style.image.name + "_" + imageName + "_" + theme
    }

    func getStyleThemeImageName(_ imageName: String = "") -> String {
        return IllustratedImageThemeView.getConcatenatedImageName(style, theme, imageName)
    }

    static func resetImage(_ illustratedImageView: IllustratedImageThemeView, _ event: NSEvent, _ view: NSView) {
        let locationInView = view.convert(event.locationInWindow, from: nil)
        if !view.bounds.contains(locationInView) {
            illustratedImageView.highlight(false)
        }
    }
}

class ShowHideIllustratedView {
    private let style: AppearanceStylePreference
    private var showHideRows = [ShowHideRowInfo]()
    var illustratedImageView: IllustratedImageThemeView!
    var table: TableGroupView!

    init(_ style: AppearanceStylePreference, _ illustratedImageView: IllustratedImageThemeView) {
        self.style = style
        self.illustratedImageView = illustratedImageView
        setupItems()
    }

    func makeView() -> TableGroupSetView {
        table = TableGroupView(width: CustomizeStyleSheet.width)
        for row in showHideRows {
            setStateOnApplications(row: row)
            if row.supportedStyles.contains(style) {
                table.addRow(leftViews: row.leftViews, rightViews: row.rightViews, onClick: { event, view in
                    if !ShowHideIllustratedView.isDisabledOnApplications(row) {
                        self.clickCheckbox(rowId: row.rowId)
                        self.updateImageView(rowId: row.rowId)
                    }
                }, onMouseEntered: { event, view in
                    self.updateImageView(rowId: row.rowId)
                })
            }
        }
        table.onMouseExited = { event, view in
            IllustratedImageThemeView.resetImage(self.illustratedImageView, event, view)
        }
        table.fit()
        let view = TableGroupSetView(originalViews: [table], padding: 0)
        return view
    }

    private func setupItems() {
        var hideAppBadges = ShowHideRowInfo()
        hideAppBadges.rowId = "hideAppBadges"
        hideAppBadges.uncheckedImage = "show_app_badges"
        hideAppBadges.checkedImage = "hide_app_badges"
        hideAppBadges.supportedStyles = [.thumbnails, .appIcons, .titles]
        hideAppBadges.leftViews = [TableGroupView.makeText(NSLocalizedString("Hide app badges", comment: ""))]
        hideAppBadges.rightViews.append(LabelAndControl.makeSwitch(hideAppBadges.rowId, extraAction: { sender in
            self.onCheckboxClicked(sender: sender, rowId: hideAppBadges.rowId)
        }))
        showHideRows.append(hideAppBadges)
        var hideStatusIcons = ShowHideRowInfo()
        hideStatusIcons.rowId = "hideStatusIcons"
        hideStatusIcons.uncheckedImage = "show_status_icons"
        hideStatusIcons.checkedImage = "hide_status_icons"
        hideStatusIcons.supportedStyles = [.thumbnails, .titles]
        hideStatusIcons.leftViews = [TableGroupView.makeText(NSLocalizedString("Hide status icons", comment: ""))]
        hideStatusIcons.subTitle = NSLocalizedString("AltTab will show if the window is currently minimized or fullscreen with a status icon.", comment: "")
        hideStatusIcons.rightViews.append(LabelAndControl.makeInfoButton(onMouseEntered: { event, view in
            Popover.shared.show(event: event, positioningView: view, message: hideStatusIcons.subTitle!)
        }, onMouseExited: { event, view in
            Popover.shared.hide()
        }))
        hideStatusIcons.rightViews.append(LabelAndControl.makeSwitch(hideStatusIcons.rowId, extraAction: { sender in
            self.onCheckboxClicked(sender: sender, rowId: hideStatusIcons.rowId)
        }))
        showHideRows.append(hideStatusIcons)
        var hideSpaceNumberLabels = ShowHideRowInfo()
        hideSpaceNumberLabels.rowId = "hideSpaceNumberLabels"
        hideSpaceNumberLabels.uncheckedImage = "show_space_number_labels"
        hideSpaceNumberLabels.checkedImage = "hide_space_number_labels"
        hideSpaceNumberLabels.supportedStyles = [.thumbnails, .titles]
        hideSpaceNumberLabels.leftViews = [TableGroupView.makeText(NSLocalizedString("Hide Space number labels", comment: ""))]
        hideSpaceNumberLabels.rightViews.append(LabelAndControl.makeSwitch(hideSpaceNumberLabels.rowId, extraAction: { sender in
            self.onCheckboxClicked(sender: sender, rowId: hideSpaceNumberLabels.rowId)
        }))
        showHideRows.append(hideSpaceNumberLabels)
        var hideColoredCircles = ShowHideRowInfo()
        hideColoredCircles.rowId = "hideColoredCircles"
        hideColoredCircles.uncheckedImage = "show_colored_circles"
        hideColoredCircles.checkedImage = "hide_colored_circles"
        hideColoredCircles.supportedStyles = [.thumbnails]
        hideColoredCircles.leftViews = [TableGroupView.makeText(NSLocalizedString("Hide colored circles on mouse hover", comment: ""))]
        hideColoredCircles.rightViews.append(LabelAndControl.makeSwitch(hideColoredCircles.rowId, extraAction: { sender in
            self.onCheckboxClicked(sender: sender, rowId: hideColoredCircles.rowId)
        }))
        showHideRows.append(hideColoredCircles)
        let featureUnavailable = NSLocalizedString("AltTab is currently set to show Applications. This setting is only available when AltTab is set to show Windows.", comment: "")
        var showTabsAsWindows = ShowHideRowInfo()
        showTabsAsWindows.rowId = "showTabsAsWindows"
        showTabsAsWindows.uncheckedImage = "hide_tabs_as_windows"
        showTabsAsWindows.checkedImage = "show_tabs_as_windows"
        showTabsAsWindows.supportedStyles = [.thumbnails, .appIcons, .titles]
        showTabsAsWindows.leftViews = [TableGroupView.makeText(NSLocalizedString("Show standard tabs as windows", comment: ""))]
        showTabsAsWindows.subTitle = NSLocalizedString("Some apps like Finder or Preview use standard tabs which act like independent windows. Some other apps like web browsers use custom tabs which act in unique ways and are not actual windows. AltTab can't list those separately.", comment: "")
        showTabsAsWindows.rightViews.append(LabelAndControl.makeInfoButton(onMouseEntered: { event, view in
            if ShowHideIllustratedView.isDisabledOnApplications(showTabsAsWindows) {
                Popover.shared.show(event: event, positioningView: view, message: featureUnavailable)
            } else {
                Popover.shared.show(event: event, positioningView: view, message: showTabsAsWindows.subTitle!)
            }
        }, onMouseExited: { event, view in
            Popover.shared.hide()
        }))
        showTabsAsWindows.rightViews.append(LabelAndControl.makeSwitch(showTabsAsWindows.rowId, extraAction: { sender in
            if !ShowHideIllustratedView.isDisabledOnApplications(showTabsAsWindows) {
                self.onCheckboxClicked(sender: sender, rowId: showTabsAsWindows.rowId)
            }
        }))
        showHideRows.append(showTabsAsWindows)
        var previewFocusedWindow = ShowHideRowInfo()
        previewFocusedWindow.rowId = "previewFocusedWindow"
        previewFocusedWindow.uncheckedImage = "hide_preview_focused_window"
        previewFocusedWindow.checkedImage = "show_preview_focused_window"
        previewFocusedWindow.supportedStyles = [.thumbnails, .appIcons, .titles]
        previewFocusedWindow.leftViews = [TableGroupView.makeText(NSLocalizedString("Preview selected window", comment: ""))]
        previewFocusedWindow.subTitle = NSLocalizedString("Preview the selected window.", comment: "")
        previewFocusedWindow.rightViews.append(LabelAndControl.makeInfoButton(onMouseEntered: { event, view in
            if ShowHideIllustratedView.isDisabledOnApplications(previewFocusedWindow) {
                Popover.shared.show(event: event, positioningView: view, message: featureUnavailable)
            } else {
                Popover.shared.show(event: event, positioningView: view, message: previewFocusedWindow.subTitle!)
            }
        }, onMouseExited: { event, view in
            Popover.shared.hide()
        }))
        previewFocusedWindow.rightViews.append(LabelAndControl.makeSwitch(previewFocusedWindow.rowId, extraAction: { sender in
            if !ShowHideIllustratedView.isDisabledOnApplications(previewFocusedWindow) {
                self.onCheckboxClicked(sender: sender, rowId: previewFocusedWindow.rowId)
            }
        }))
        showHideRows.append(previewFocusedWindow)
    }

    static func isDisabledOnApplications(_ row: ShowHideRowInfo) -> Bool {
        let contains = ["showTabsAsWindows", "previewFocusedWindow"].contains(where: { $0 == row.rowId })
        return contains && Preferences.onlyShowApplications()
    }

    func setStateOnApplications(row: ShowHideRowInfo? = nil) {
        if let row {
            let isEnabled = !ShowHideIllustratedView.isDisabledOnApplications(row)
            row.rightViews.forEach { view in
                if let view = view as? Switch {
                    if !isEnabled {
                        view.state = .off
                    }
                    view.isEnabled = isEnabled
                }
            }
            row.leftViews.forEach { view in
                if let view = view as? NSTextField {
                    view.textColor = isEnabled ? NSColor.textColor : NSColor.gray
                }
            }
        } else {
            showHideRows.forEach { row in
                setStateOnApplications(row: row)
            }
        }
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
        let row = showHideRows.first {
            $0.rowId.elementsEqual(rowId)
        }
        let imageName = isChecked ? row?.checkedImage : row?.uncheckedImage
        illustratedImageView.highlight(true, imageName!)
    }

    private func updateImageView(rowId: String) {
        let row = showHideRows.first {
            $0.rowId.elementsEqual(rowId)
        }
        row?.rightViews.forEach { view in
            if let checkbox = view as? NSButton {
                let isChecked = checkbox.state == .on
                let imageName = isChecked ? row?.checkedImage : row?.uncheckedImage
                illustratedImageView.highlight(true, imageName!)
            }
        }
    }

    private func clickCheckbox(rowId: String) {
        let row = showHideRows.first {
            $0.rowId.elementsEqual(rowId)
        }
        row?.rightViews.forEach { view in
            if let checkbox = view as? NSButton {
                // Toggle the checkbox state
                checkbox.state = (checkbox.state == .on) ? .off : .on
            }
        }
    }
}

class Popover: NSPopover {
    static let shared = Popover()
    private var hidingInitiated = true

    override init() {
        super.init()
        delegate = self
        contentViewController = NSViewController()
        behavior = .semitransient
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func hide() {
        performClose(nil)
    }

    func show(event: NSEvent, positioningView: NSView, message: String, extraView: NSView? = nil) {
        if !hidingInitiated { return }
        hidingInitiated = false
        let view = NSView()
        let label = NSTextField(labelWithString: message)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.isEditable = false
        label.isSelectable = true
        label.font = NSFont.systemFont(ofSize: 12)
        let actualView: NSView = extraView == nil ? label : StackView([label, extraView!], .vertical)
        view.addSubview(actualView)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
            actualView.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            actualView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            actualView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            actualView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
        ])
        contentViewController?.view = view
        // Convert the mouse location to the positioning view's coordinate system
        let locationInWindow = event.locationInWindow
        let locationInPositioningView = positioningView.convert(locationInWindow, from: nil)
        let rect = CGRect(origin: locationInPositioningView, size: .zero)
        show(relativeTo: rect, of: positioningView, preferredEdge: .minX)
    }
}

extension Popover: NSPopoverDelegate {
    func popoverWillClose(_ notification: Notification) {
        hidingInitiated = true
    }
}

class AppearanceTab: NSObject {
    static var livePreviewOptionRows = [TableGroupView.RowInfo]()
    static var customizeStyleButton: NSButton!
    static var animationsButton: NSButton!
    static var customizeStyleSheet: CustomizeStyleSheet!
    static var animationsSheet: AnimationsSheet!

    static func initTab() -> NSView {
        customizeStyleButton = NSButton(title: getCustomizeStyleButtonTitle(), target: self, action: #selector(showCustomizeStyleSheet))
        animationsButton = NSButton(title: NSLocalizedString("Animations…", comment: ""), target: self, action: #selector(showAnimationsSheet))
        customizeStyleSheet = CustomizeStyleSheet()
        animationsSheet = AnimationsSheet()
        return makeView()
    }

    private static func makeView() -> NSStackView {
        let appearanceView = makeAppearanceView()
        let multipleScreensView = makeMultipleScreensView()
        let livePreviewView = makeLivePreviewView()
        let view = TableGroupSetView(originalViews: [appearanceView, multipleScreensView, livePreviewView, animationsButton])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        return view
    }

    private static func makeAppearanceView() -> NSView {
        let table = TableGroupView(title: NSLocalizedString("Appearance", comment: ""),
            subTitle: NSLocalizedString("Switch between 3 different styles. You can customize them.", comment: ""),
            width: PreferencesWindow.width)
        table.addRow(secondaryViews: [LabelAndControl.makeImageRadioButtons("appearanceStyle", AppearanceStylePreference.allCases, extraAction: { _ in
            toggleCustomizeStyleButton()
        }, buttonSpacing: 10)], secondaryViewsAlignment: .centerX)
        table.addRow(leftText: NSLocalizedString("Size", comment: ""),
            rightViews: [LabelAndControl.makeSegmentedControl("appearanceSize", AppearanceSizePreference.allCases, segmentWidth: 100)])
        table.addRow(leftText: NSLocalizedString("Theme", comment: ""),
            rightViews: [LabelAndControl.makeSegmentedControl("appearanceTheme", AppearanceThemePreference.allCases, segmentWidth: 100)])
        table.addRow(rightViews: customizeStyleButton)
        table.fit()
        return table
    }

    private static func makeMultipleScreensView() -> NSView {
        let table = TableGroupView(title: NSLocalizedString("Multiple screens", comment: ""), width: PreferencesWindow.width)
        _ = table.addRow(leftText: NSLocalizedString("Show on", comment: ""),
            rightViews: LabelAndControl.makeDropdown("showOnScreen", ShowOnScreenPreference.allCases))
        table.fit()
        return table
    }

    private static func makeLivePreviewView() -> NSView {
        livePreviewOptionRows.removeAll()
        let table = TableGroupView(title: NSLocalizedString("Live Preview", comment: ""),
            subTitle: NSLocalizedString("Higher quality and frame rate use more CPU/GPU resources. Use lower settings if you experience lag.", comment: ""),
            width: PreferencesWindow.width)

        let enableSwitch = LabelAndControl.makeSwitch("enableLivePreview", extraAction: { sender in
            toggleLivePreviewOptions()
            if !Preferences.enableLivePreview {
                if #available(macOS 12.3, *) {
                    Task {
                        await LiveWindowCapture.shared.stopAllCaptures()
                    }
                }
            }
        })

        _ = table.addRow(leftText: NSLocalizedString("Enable live preview", comment: ""),
            rightViews: [enableSwitch])

        let qualityDropdown = LabelAndControl.makeDropdown("livePreviewQuality", LivePreviewQualityPreference.allCases)
        livePreviewOptionRows.append(table.addRow(leftText: NSLocalizedString("Quality", comment: ""),
            rightViews: [qualityDropdown]))

        let frameRateDropdown = LabelAndControl.makeDropdown("livePreviewFrameRate", LivePreviewFrameRatePreference.allCases)
        livePreviewOptionRows.append(table.addRow(leftText: NSLocalizedString("Frame rate", comment: ""),
            rightViews: [frameRateDropdown]))

        let scopeDropdown = LabelAndControl.makeDropdown("livePreviewScope", LivePreviewScopePreference.allCases)
        livePreviewOptionRows.append(table.addRow(leftText: NSLocalizedString("Scope", comment: ""),
            rightViews: [scopeDropdown]))

        let keepAliveControl = makeStreamKeepAliveControl()
        livePreviewOptionRows.append(table.addRow(leftText: NSLocalizedString("Stream keep-alive", comment: ""),
            rightViews: [keepAliveControl]))

        table.fit()
        toggleLivePreviewOptions()
        return table
    }

    private static func makeStreamKeepAliveControl() -> NSView {
        let mainContainer = NSStackView()
        mainContainer.orientation = .vertical
        mainContainer.alignment = .leading
        mainContainer.spacing = 8

        let value = Preferences.livePreviewStreamKeepAlive
        let isImmediate = value == 0
        let isForever = value == -1
        let isCustom = value > 0

        let immediateRadio = NSButton(radioButtonWithTitle: NSLocalizedString("Immediately close", comment: ""), target: self, action: #selector(keepAliveImmediateClicked))
        immediateRadio.identifier = NSUserInterfaceItemIdentifier("keepAliveImmediate")
        immediateRadio.state = isImmediate ? .on : .off

        let foreverRadio = NSButton(radioButtonWithTitle: NSLocalizedString("Keep open forever", comment: ""), target: self, action: #selector(keepAliveForeverClicked))
        foreverRadio.identifier = NSUserInterfaceItemIdentifier("keepAliveForever")
        foreverRadio.state = isForever ? .on : .off

        let customRadio = NSButton(radioButtonWithTitle: NSLocalizedString("Close after", comment: ""), target: self, action: #selector(keepAliveCustomClicked))
        customRadio.identifier = NSUserInterfaceItemIdentifier("keepAliveCustom")
        customRadio.state = isCustom ? .on : .off

        let customRow = NSStackView()
        customRow.orientation = .horizontal
        customRow.spacing = 6
        customRow.alignment = .centerY
        customRow.identifier = NSUserInterfaceItemIdentifier("keepAliveCustomRow")

        let textField = IBeamTextField()
        textField.identifier = NSUserInterfaceItemIdentifier("livePreviewStreamKeepAlive")
        textField.stringValue = isCustom ? String(value) : "3"
        textField.isEnabled = isCustom
        textField.formatter = NumberFormatter()
        textField.alignment = .center
        textField.placeholderString = "3"
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        textField.target = self
        textField.action = #selector(keepAliveTextFieldChanged(_:))
        NotificationCenter.default.addObserver(self, selector: #selector(keepAliveTextDidChange(_:)),
            name: NSControl.textDidChangeNotification, object: textField)

        let secondsLabel = NSTextField(labelWithString: NSLocalizedString("seconds", comment: ""))
        secondsLabel.textColor = .secondaryLabelColor

        customRow.addArrangedSubview(customRadio)
        customRow.addArrangedSubview(textField)
        customRow.addArrangedSubview(secondsLabel)

        let descriptionLabel = NSTextField(wrappingLabelWithString: NSLocalizedString("How long to keep video streams active after closing the switcher. Longer duration means faster reopening but uses more resources.", comment: ""))
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.font = NSFont.systemFont(ofSize: 11)
        descriptionLabel.preferredMaxLayoutWidth = 400

        mainContainer.addArrangedSubview(immediateRadio)
        mainContainer.addArrangedSubview(foreverRadio)
        mainContainer.addArrangedSubview(customRow)
        mainContainer.addArrangedSubview(descriptionLabel)

        return mainContainer
    }

    @objc private static func keepAliveImmediateClicked() {
        Preferences.set("livePreviewStreamKeepAlive", 0)
        updateKeepAliveButtonStates()
    }

    @objc private static func keepAliveForeverClicked() {
        Preferences.set("livePreviewStreamKeepAlive", -1)
        updateKeepAliveButtonStates()
    }

    @objc private static func keepAliveCustomClicked() {
        let currentValue = Preferences.livePreviewStreamKeepAlive
        let newValue = currentValue > 0 ? currentValue : 3
        Preferences.set("livePreviewStreamKeepAlive", newValue)
        updateKeepAliveButtonStates()
    }

    @objc private static func keepAliveTextFieldChanged(_ sender: NSTextField) {
        let value = max(1, Int(sender.stringValue) ?? 3)
        Preferences.set("livePreviewStreamKeepAlive", value)
        sender.stringValue = String(value)
        updateKeepAliveButtonStates()
    }

    @objc private static func keepAliveTextDidChange(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }
        if let value = Int(textField.stringValue), value > 0 {
            Preferences.set("livePreviewStreamKeepAlive", value)
            findViewRecursive(identifier: "keepAliveImmediate", as: NSButton.self)?.state = .off
            findViewRecursive(identifier: "keepAliveForever", as: NSButton.self)?.state = .off
            findViewRecursive(identifier: "keepAliveCustom", as: NSButton.self)?.state = .on
        }
    }

    private static func updateKeepAliveButtonStates() {
        let value = Preferences.livePreviewStreamKeepAlive
        let isImmediate = value == 0
        let isForever = value == -1
        let isCustom = value > 0

        findViewRecursive(identifier: "keepAliveImmediate", as: NSButton.self)?.state = isImmediate ? .on : .off
        findViewRecursive(identifier: "keepAliveForever", as: NSButton.self)?.state = isForever ? .on : .off
        findViewRecursive(identifier: "keepAliveCustom", as: NSButton.self)?.state = isCustom ? .on : .off

        if let textField = findViewRecursive(identifier: "livePreviewStreamKeepAlive", as: NSTextField.self) {
            textField.isEnabled = isCustom
            if isCustom {
                textField.stringValue = String(value)
            }
        }
    }

    private static func findViewRecursive<T: NSView>(identifier: String, as type: T.Type) -> T? {
        guard let contentView = App.app.preferencesWindow?.contentView else { return nil }
        return findInView(contentView, identifier: identifier, as: type)
    }

    private static func findInView<T: NSView>(_ view: NSView, identifier: String, as type: T.Type) -> T? {
        if let typedView = view as? T, typedView.identifier?.rawValue == identifier {
            return typedView
        }
        for subview in view.subviews {
            if let found = findInView(subview, identifier: identifier, as: type) {
                return found
            }
        }
        return nil
    }

    private static func toggleLivePreviewOptions() {
        let isEnabled = Preferences.enableLivePreview

        for rowInfo in livePreviewOptionRows {
            for subview in rowInfo.view.subviews {
                setEnabledRecursive(subview, isEnabled)
            }
            rowInfo.view.alphaValue = isEnabled ? 1.0 : 0.4
        }

        if isEnabled {
            updateKeepAliveButtonStates()
        }
    }

    private static func setEnabledRecursive(_ view: NSView, _ enabled: Bool) {
        if let control = view as? NSControl {
            control.isEnabled = enabled
        }
        for subview in view.subviews {
            setEnabledRecursive(subview, enabled)
        }
    }

    private static func getCustomizeStyleButtonTitle() -> String {
        if Preferences.appearanceStyle == .thumbnails {
            return NSLocalizedString("Customize Thumbnails style…", comment: "")
        } else if Preferences.appearanceStyle == .appIcons {
            return NSLocalizedString("Customize App Icons style…", comment: "")
        }
        return NSLocalizedString("Customize Titles style…", comment: "")
    }

    @objc static func toggleCustomizeStyleButton() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(handleToggleAdvancedButton), object: nil)
        self.perform(#selector(handleToggleAdvancedButton), with: nil, afterDelay: 0.1)
    }

    @objc static func handleToggleAdvancedButton() {
        customizeStyleButton.animator().title = getCustomizeStyleButtonTitle()
        customizeStyleSheet = CustomizeStyleSheet()
    }

    @objc static func showCustomizeStyleSheet() {
        App.app.preferencesWindow.beginSheet(customizeStyleSheet)
    }

    @objc static func showAnimationsSheet() {
        App.app.preferencesWindow.beginSheet(animationsSheet)
    }
}
