import Cocoa

/// An overlay view that lets clicks pass through to views behind it. Used for the Pro-lock ghost
/// overlay on the `.auto` size segment so the underlying segmented control still receives the click.
class NonHitTestingView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
    /// Shown when the current Appearance style doesn't support a Show/Hide option (the illustration
    /// is for another style). Exposed so `CustomizeStyleSheet.searchableStrings` can reference it
    /// without re-`NSLocalizedString`-ing the same English text.
    static let placeholderLabelText = NSLocalizedString("Applies in other Appearances", comment: "")
    var style: AppearanceStylePreference!
    var theme: String!
    var imageName: String!
    var isFocused: Bool = false
    private var placeholderLabel: NSTextField!

    /// Loads an illustration from the bundle without going through `NSImage(named:)`'s global
    /// named cache (which never releases). Pairs with `cacheMode = .never` so the per-image scaled
    /// bitmap cache is also disabled. Lets ARC reclaim the bitmap when no view holds the image.
    static func loadIllustration(_ name: String) -> NSImage? {
        guard let path = Bundle.main.path(forResource: "\(name)@2x", ofType: "heic") else { return nil }
        let image = NSImage(contentsOfFile: path)
        image?.cacheMode = .never
        return image
    }

    init(_ style: AppearanceStylePreference, _ width: CGFloat) {
        // TODO: The appearance theme functionality has not been implemented yet.
        // We will implement it later; for now, use the light theme.
        let theme = "light"
        let imageName = IllustratedImageThemeView.getConcatenatedImageName(style, theme)
        let imageView = NSImageView(image: IllustratedImageThemeView.loadIllustration(imageName)!)
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
        let placeholder = NSTextField(labelWithString: IllustratedImageThemeView.placeholderLabelText)
        placeholder.font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 3)
        placeholder.textColor = .secondaryLabelColor
        placeholder.alignment = .center
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.isHidden = true
        addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: IllustratedImageThemeView.padding + 8),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -(IllustratedImageThemeView.padding + 8)),
        ])
        placeholderLabel = placeholder
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
        placeholderLabel.isHidden = true
        infoCircle.isHidden = false
        if highlighted {
            updateImage(imageName)
        } else {
            (infoCircle as! NSImageView).image = IllustratedImageThemeView.loadIllustration(self.imageName)
        }
    }

    func showPlaceholder() {
        setFocused(true)
        setBorder()
        infoCircle.isHidden = true
        placeholderLabel.isHidden = false
    }

    private func updateImage(_ imageName: String) {
        (infoCircle as! NSImageView).image = IllustratedImageThemeView.loadIllustration(getStyleThemeImageName(imageName))
    }

    static func getConcatenatedImageName(_ style: AppearanceStylePreference,
                                         _ theme: String,
                                         _ imageName: String = "") -> String {
        if imageName.isEmpty {
            // thumbnails_light/app_icons_dark
            return style.image.name + "_" + theme
        }
        // thumbnails_show_status_icons_light/app_icons_hide_colored_circles_light
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
    // Row labels exposed so `CustomizeStyleSheet.searchableStrings` can reference them without
    // duplicating `NSLocalizedString` calls. Each is the single source of truth for that row's
    // localized text; `setupItems` below uses these constants when building the rows.
    static let hideStatusIconsLabel = NSLocalizedString("Hide status icons", comment: "")
    static let hideStatusIconsSubtitle = NSLocalizedString("AltTab will show if the window is currently minimized or fullscreen with a status icon.", comment: "")
    static let hideSpaceNumberLabelsLabel = NSLocalizedString("Hide Space number labels", comment: "")
    static let hideColoredCirclesLabel = NSLocalizedString("Hide colored circles on mouse hover", comment: "")

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
            table.addRow(leftViews: row.leftViews, rightViews: row.rightViews, onClick: { [weak self] _, _ in
                self?.clickCheckbox(rowId: row.rowId)
                self?.updateImageView(rowId: row.rowId)
            }, onMouseEntered: { [weak self] _, _ in
                self?.updateImageView(rowId: row.rowId)
            })
        }
        table.onMouseExited = { [weak self] event, view in
            guard let self else { return }
            IllustratedImageThemeView.resetImage(self.illustratedImageView, event, view)
        }
        return TableGroupSetView(originalViews: [table], padding: 0)
    }

    private func setupItems() {
        var hideStatusIcons = ShowHideRowInfo()
        hideStatusIcons.rowId = "hideStatusIcons"
        hideStatusIcons.uncheckedImage = "show_status_icons"
        hideStatusIcons.checkedImage = "hide_status_icons"
        hideStatusIcons.supportedStyles = [.thumbnails, .titles]
        hideStatusIcons.leftViews = [TableGroupView.makeText(ShowHideIllustratedView.hideStatusIconsLabel)]
        hideStatusIcons.subTitle = ShowHideIllustratedView.hideStatusIconsSubtitle
        hideStatusIcons.rightViews.append(LabelAndControl.makeInfoButton(searchableTooltipTexts: [hideStatusIcons.subTitle!], onMouseEntered: { event, view in
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
        hideSpaceNumberLabels.leftViews = [TableGroupView.makeText(ShowHideIllustratedView.hideSpaceNumberLabelsLabel)]
        hideSpaceNumberLabels.rightViews.append(LabelAndControl.makeSwitch(hideSpaceNumberLabels.rowId, extraAction: { sender in
            self.onCheckboxClicked(sender: sender, rowId: hideSpaceNumberLabels.rowId)
        }))
        showHideRows.append(hideSpaceNumberLabels)
        var hideColoredCircles = ShowHideRowInfo()
        hideColoredCircles.rowId = "hideColoredCircles"
        hideColoredCircles.uncheckedImage = "show_colored_circles"
        hideColoredCircles.checkedImage = "hide_colored_circles"
        hideColoredCircles.supportedStyles = [.thumbnails]
        hideColoredCircles.leftViews = [TableGroupView.makeText(ShowHideIllustratedView.hideColoredCirclesLabel)]
        hideColoredCircles.rightViews.append(LabelAndControl.makeSwitch(hideColoredCircles.rowId, extraAction: { sender in
            self.onCheckboxClicked(sender: sender, rowId: hideColoredCircles.rowId)
        }))
        showHideRows.append(hideColoredCircles)
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
        guard let row = showHideRows.first(where: { $0.rowId.elementsEqual(rowId) }) else { return }
        if !row.supportedStyles.contains(style) {
            illustratedImageView.showPlaceholder()
            return
        }
        let imageName = isChecked ? row.checkedImage : row.uncheckedImage
        illustratedImageView.highlight(true, imageName!)
    }

    private func updateImageView(rowId: String) {
        guard let row = showHideRows.first(where: { $0.rowId.elementsEqual(rowId) }) else { return }
        if !row.supportedStyles.contains(style) {
            illustratedImageView.showPlaceholder()
            return
        }
        row.rightViews.forEach { view in
            if let checkbox = view as? NSButton {
                let isChecked = checkbox.state == .on
                let imageName = isChecked ? row.checkedImage : row.uncheckedImage
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
    private var searchQuery = ""
    private var searchMatchRanges: ((String, String) -> [Range<Int>])?
    private var currentMessage = ""
    private weak var currentMessageLabel: NSTextField?

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

    func updateSearchContext(_ query: String, _ searchMatchRanges: @escaping (String, String) -> [Range<Int>]) {
        searchQuery = query
        self.searchMatchRanges = searchMatchRanges
        applySearchHighlightToCurrentMessage()
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
        currentMessage = message
        currentMessageLabel = label
        applySearchHighlightToCurrentMessage()
        contentViewController?.view = view
        // Convert the mouse location to the positioning view's coordinate system
        let locationInWindow = event.locationInWindow
        let locationInPositioningView = positioningView.convert(locationInWindow, from: nil)
        let rect = CGRect(origin: locationInPositioningView, size: .zero)
        show(relativeTo: rect, of: positioningView, preferredEdge: .minX)
    }

    private func applySearchHighlightToCurrentMessage() {
        guard let label = currentMessageLabel else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: label.font ?? NSFont.systemFont(ofSize: 12),
            .foregroundColor: label.textColor ?? NSColor.labelColor
        ]
        let attributed = NSMutableAttributedString(string: currentMessage, attributes: attributes)
        guard let searchMatchRanges, !currentMessage.isEmpty else {
            label.attributedStringValue = attributed
            return
        }
        let ranges = searchMatchRanges(searchQuery, currentMessage)
        guard !ranges.isEmpty else {
            label.attributedStringValue = attributed
            return
        }
        ranges.compactMap {
            characterRangeToNSRange($0, in: currentMessage)
        }.forEach {
            attributed.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.5), range: $0)
            attributed.addAttribute(.foregroundColor, value: NSColor(calibratedWhite: 0.12, alpha: 1), range: $0)
        }
        label.attributedStringValue = attributed
    }

    private func characterRangeToNSRange(_ range: Range<Int>, in text: String) -> NSRange? {
        if range.lowerBound < 0 || range.upperBound > text.count || range.isEmpty { return nil }
        let start = text.index(text.startIndex, offsetBy: range.lowerBound)
        let end = text.index(text.startIndex, offsetBy: range.upperBound)
        return NSRange(start..<end, in: text)
    }
}

extension Popover: NSPopoverDelegate {
    func popoverWillClose(_ notification: Notification) {
        hidingInitiated = true
        currentMessage = ""
        currentMessageLabel = nil
    }
}

class AppearanceTab: NSObject {
    // Localized labels for the per-setting rows. Exposed so `ShortcutEditor.AppearancePane`
    // (the per-shortcut override pane) can reference the same string for each conceptual
    // setting instead of re-`NSLocalizedString`-ing them.
    static let labelSize = NSLocalizedString("Size", comment: "")
    static let labelTheme = NSLocalizedString("Theme", comment: "")
    static let labelShortcutStyle = NSLocalizedString("After keys are released", comment: "")
    static let labelPreviewSelectedWindow = NSLocalizedString("Preview selected window", comment: "")

    static var customizeStyleButton: NSButton!
    static var animationsButton: NSButton!
    static var customizeStyleSheet: CustomizeStyleSheet!
    static var animationsSheet: AnimationsSheet!

    // References used by `refreshProLockUi()` to update Pro-lock affordances while Settings stays open.
    private static weak var styleButtonsStack: NSStackView?
    private static weak var sizeControlRef: NSSegmentedControl?
    private static var autoSegmentOverlayRef: ProBadgeView.SegmentOverlay?
    private static weak var shortcutStyleControlRef: NSSegmentedControl?
    private static var shortcutStyleSegmentOverlayRef: ProBadgeView.SegmentOverlay?
    private static var proLockObserver: NSObjectProtocol?

    /// One icon button per overridable preference, parked at the trailing edge of each row (same
    /// position as the "unlink" icon in the per-shortcut Appearance section in `ControlsTab`).
    /// Hidden when no shortcut overrides the global. Tooltip on hover lists the overriding
    /// shortcut numbers; click navigates to the first one's Appearance pane in `ControlsTab`.
    private static var overrideInfoIcons = [String: NSButton]()

    static func initTab() -> NSView {
        customizeStyleButton = NSButton(title: getCustomizeStyleButtonTitle(), target: self, action: #selector(showCustomizeStyleSheet))
        animationsButton = NSButton(title: NSLocalizedString("Animations…", comment: ""), target: self, action: #selector(showAnimationsSheet))
        // Sheets are constructed lazily on first show — see `showCustomizeStyleSheet` /
        // `showAnimationsSheet`. Pre-build search is satisfied by the sheets' static
        // `searchableStrings`, consulted through `SettingsSearchIndex`.
        if proLockObserver == nil {
            proLockObserver = NotificationCenter.default.addObserver(
                forName: ProTransitionManager.proLockStateDidChangeNotification,
                object: nil, queue: .main
            ) { _ in refreshProLockUi() }
        }
        return makeView()
    }

    static func cleanup() {
        if let observer = proLockObserver {
            NotificationCenter.default.removeObserver(observer)
            proLockObserver = nil
        }
        // Don't call .close() — NSWindow's default `isReleasedWhenClosed = true` interacts
        // badly with our manual nil-out and causes double-release. ARC reclaims the sheet
        // when the static ref is nilled.
        customizeStyleButton = nil
        animationsButton = nil
        customizeStyleSheet = nil
        animationsSheet = nil
        autoSegmentOverlayRef = nil
        shortcutStyleSegmentOverlayRef = nil
        overrideInfoIcons.removeAll()
    }

    private static func makeView() -> NSStackView {
        let appearanceView = makeAppearanceView()
        let multipleScreensView = makeMultipleScreensView()
        // `padding: 0` — `TableGroupSetView` adds 20pt of horizontal inset by default before its
        // inner content stack. The enclosing section (from `SettingsWindow.addSection`) already
        // provides the section's left margin via `contentHorizontalPadding`, so adding another
        // 20pt here pushes the TGV content to `container.leading + 20`, while the section title
        // sits at `container.leading + TableGroupView.padding(10)` — a 10pt visible misalignment
        // between the title and the row content below it.
        let view = TableGroupSetView(originalViews: [appearanceView, multipleScreensView, animationsButton], titleTableGroupSpacing: 15, padding: 0, bottomPadding: 0)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        return view
    }

    private static func makeAppearanceView() -> NSView {
        let table = TableGroupView(subTitle: NSLocalizedString("Switch between 3 different styles. You can customize them.", comment: ""),
            width: SettingsWindow.contentWidth)
        let styleButtons = LabelAndControl.makeImageRadioButtons("appearanceStyle", AppearanceStylePreference.allCases, extraAction: { _ in
            toggleCustomizeStyleButton()
            ControlsTab.syncOverrideControlsToGlobal()
            refreshAllOverrideInfoLabels()
        }, buttonSpacing: 10, proGatedIndices: proGatedAppearanceStyleIndices())
        addProBadgesToStyleButtons(styleButtons)
        styleButtonsStack = styleButtons
        // For the style row, the control is a horizontal stack of style cards centered in the row.
        // Wrap [styleButtons, overrideIcon] in another HStack so the icon trails the cards — same
        // pattern the per-shortcut Appearance section uses for its style + unlink pair.
        let styleOverrideIcon = makeOverrideIcon("appearanceStyleOverride")
        let styleRow = NSStackView(views: [styleButtons, styleOverrideIcon])
        styleRow.orientation = .horizontal
        styleRow.alignment = .centerY
        styleRow.spacing = TableGroupView.padding
        table.addRow(secondaryViews: [styleRow], secondaryViewsAlignment: .centerX)
        let sizeControl = LabelAndControl.makeSegmentedControl("appearanceSize", AppearanceSizePreference.allCases, segmentWidth: 105, extraAction: { control in
            refreshAutoSegmentAppearance(control as! NSSegmentedControl)
            ControlsTab.syncOverrideControlsToGlobal()
            refreshAllOverrideInfoLabels()
        })
        wrapAppearanceSizeProLockIntercept(sizeControl)
        sizeControlRef = sizeControl
        let autoOverlay = addProBadgeToAutoSegment(sizeControl)
        autoSegmentOverlayRef = autoOverlay
        // AppKit re-resolves segment label/background colors on window-key transitions but doesn't
        // notify our overlay subviews. Hook the badge's own key-state observer to trigger our
        // resync (which calls `needsDisplay` on the icon/label so their `colorProvider`-driven
        // `viewWillDraw` picks up the new state).
        autoOverlay.badge.onWindowKeyChanged = { [weak sizeControl] in
            guard let sizeControl else { return }
            refreshAutoSegmentAppearance(sizeControl)
        }
        table.addRow(leftText: AppearanceTab.labelSize,
            rightViews: [sizeControl, makeOverrideIcon("appearanceSizeOverride")])
        table.addRow(leftText: AppearanceTab.labelTheme,
            rightViews: [LabelAndControl.makeSegmentedControl("appearanceTheme", AppearanceThemePreference.allCases, segmentWidth: 105, extraAction: { _ in
                ControlsTab.syncOverrideControlsToGlobal()
                refreshAllOverrideInfoLabels()
            }), makeOverrideIcon("appearanceThemeOverride")])
        addAfterKeysReleasedRow(table)
        addPreviewSelectedWindowRow(table)
        table.addRow(rightViews: customizeStyleButton)
        refreshAllOverrideInfoLabels()
        return table
    }

    /// Build the override-indicator icon button parked at the trailing edge of each global row.
    /// Visible iff at least one shortcut overrides this global. Tooltip lists the overriding
    /// shortcut numbers; click navigates to the first overriding shortcut's Appearance pane in
    /// `ControlsTab` (same behaviour the previous text-link version had).
    private static func makeOverrideIcon(_ overrideBaseName: String) -> NSButton {
        // `arrow.triangle.branch` rotated 180° — reads as "this value has branches going
        // downward to other shortcuts". Visually distinct from the chain-link unlink button.
        let image = NSImage.fromSymbol(.arrowTriangleBranch, pointSize: 14, rotated180: true)
        let button = NSButton(image: image, target: self, action: #selector(overrideInfoClicked(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(overrideBaseName)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        if #available(macOS 10.14, *) {
            button.contentTintColor = .controlAccentColor
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 20).isActive = true
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true
        button.isHidden = true
        overrideInfoIcons[overrideBaseName] = button
        return button
    }

    private static func refreshOverrideInfoIcon(_ overrideBaseName: String, _ globalKey: String) {
        guard let icon = overrideInfoIcons[overrideBaseName] else { return }
        let indices = Preferences.shortcutIndicesWithDifferentValue(overrideBaseName, globalKey: globalKey)
        if indices.isEmpty {
            icon.isHidden = true
            icon.toolTip = nil
        } else {
            let numbers = indices.map { String($0 + 1) }.joined(separator: ", ")
            icon.toolTip = NSLocalizedString("Overridden in Shortcut:", comment: "") + " " + numbers
            icon.tag = indices[0]
            icon.isHidden = false
        }
    }

    /// Refresh every override-indicator icon's visibility + tooltip. Wrapped in
    /// `preserveScrollPosition` since toggling icon visibility can change the row's measured
    /// width and otherwise nudge the user's scroll position. During the initial build the window
    /// singleton isn't assigned yet (`init` sets `SettingsWindow.shared` only after `setupView`
    /// returns), so we still run the refresh — just without scroll preservation, which isn't
    /// needed before the window is on-screen anyway.
    static func refreshAllOverrideInfoLabels() {
        let refresh = {
            for (overrideBaseName, globalKey) in Preferences.overrideToGlobalKey {
                refreshOverrideInfoIcon(overrideBaseName, globalKey)
            }
        }
        if let window = SettingsWindow.shared {
            window.preserveScrollPosition(during: refresh)
        } else {
            refresh()
        }
    }

    @objc static func overrideInfoClicked(_ sender: NSButton) {
        SettingsWindow.shared?.navigateToSection("controls")
        ControlsTab.selectShortcutAndShowAppearance(sender.tag)
    }

    private static func addAfterKeysReleasedRow(_ table: TableGroupView) {
        let proIndex = ShortcutStylePreference.allCases.firstIndex(of: .searchOnRelease)!
        let control = LabelAndControl.makeSegmentedControl("shortcutStyle", ShortcutStylePreference.allCases, segmentWidth: 105, extraAction: { control in
            refreshShortcutStyleSegmentAppearance(control as! NSSegmentedControl)
            ControlsTab.syncOverrideControlsToGlobal()
            refreshAllOverrideInfoLabels()
        })
        wrapShortcutStyleProLockIntercept(control, proIndex: proIndex)
        shortcutStyleControlRef = control
        let shortcutStyleOverlay = addProBadgeToShortcutStyleSegment(control, proIndex: proIndex)
        shortcutStyleSegmentOverlayRef = shortcutStyleOverlay
        shortcutStyleOverlay.badge.onWindowKeyChanged = { [weak control] in
            guard let control else { return }
            refreshShortcutStyleSegmentAppearance(control)
        }
        table.addRow(leftText: AppearanceTab.labelShortcutStyle,
            rightViews: [control, makeOverrideIcon("shortcutStyleOverride")])
    }

    private static func wrapShortcutStyleProLockIntercept(_ control: NSSegmentedControl, proIndex: Int) {
        let original = control.onAction
        control.onAction = { c in
            let segmented = c as! NSSegmentedControl
            if segmented.selectedSegment == proIndex && LicenseManager.shared.isProLocked {
                let stored: ShortcutStylePreference = CachedUserDefaults.macroPref("shortcutStyle", ShortcutStylePreference.allCases)
                segmented.selectedSegment = stored.index
                refreshShortcutStyleSegmentAppearance(segmented)
                UpgradeTab.navigateToUpgradeTab()
                return
            }
            original?(c)
        }
    }

    /// Re-sync the Search-segment overlay's state. See `refreshAutoSegmentAppearance`.
    private static func refreshShortcutStyleSegmentAppearance(_ segmentedControl: NSSegmentedControl) {
        guard let overlay = shortcutStyleSegmentOverlayRef else { return }
        refreshTrailingSegmentBadge(segmentedControl, proIndex: ShortcutStylePreference.allCases.firstIndex(of: .searchOnRelease)!, overlay: overlay)
    }

    static func addProBadgeToShortcutStyleSegment(_ segmentedControl: NSSegmentedControl, proIndex: Int) -> ProBadgeView.SegmentOverlay {
        return ProBadgeView.attach(to: segmentedControl,
            segmentIndex: proIndex,
            label: ShortcutStylePreference.searchOnRelease.localizedString,
            symbol: ShortcutStylePreference.searchOnRelease.symbol)
    }

    static func refreshTrailingSegmentBadge(_ segmentedControl: NSSegmentedControl, proIndex: Int, overlay: ProBadgeView.SegmentOverlay) {
        ProBadgeView.refreshSelection(in: segmentedControl, proIndex: proIndex, overlay: overlay)
    }

    private static func addPreviewSelectedWindowRow(_ table: TableGroupView) {
        let switchControl = LabelAndControl.makeSwitch("previewFocusedWindow", extraAction: { _ in
            ControlsTab.syncOverrideControlsToGlobal()
            refreshAllOverrideInfoLabels()
        })
        _ = table.addRow(leftText: AppearanceTab.labelPreviewSelectedWindow,
            rightViews: [switchControl, makeOverrideIcon("previewFocusedWindowOverride")])
    }

    private static func makeMultipleScreensView() -> NSView {
        let table = TableGroupView(title: NSLocalizedString("Multiple screens", comment: ""), width: SettingsWindow.contentWidth)
        _ = table.addRow(leftText: NSLocalizedString("Show on", comment: ""),
            rightViews: LabelAndControl.makeDropdown("showOnScreen", ShowOnScreenPreference.allCases))
        return table
    }

    private static func getCustomizeStyleButtonTitle() -> String {
        return NSLocalizedString("Customize more…", comment: "")
    }

    @objc static func toggleCustomizeStyleButton() {
        // Recreate the sheet so the next open rebuilds with current style preference baked in.
        // (This is the "appearance style changed → reset the customize sheet" path.)
        customizeStyleSheet = CustomizeStyleSheet()
    }

    @objc static func showCustomizeStyleSheet() {
        if customizeStyleSheet == nil { customizeStyleSheet = CustomizeStyleSheet() }
        SettingsWindow.shared.beginSheetWithSearchHighlight(customizeStyleSheet)
    }

    @objc static func showAnimationsSheet() {
        if animationsSheet == nil { animationsSheet = AnimationsSheet() }
        SettingsWindow.shared.beginSheetWithSearchHighlight(animationsSheet)
    }

    /// Re-sync the Auto-segment overlay's state (badge + icon/label color). Called on click,
    /// Pro-lock transitions, programmatic resync, and window key-state changes.
    private static func refreshAutoSegmentAppearance(_ segmentedControl: NSSegmentedControl) {
        guard let overlay = autoSegmentOverlayRef else { return }
        refreshTrailingSegmentBadge(segmentedControl, proIndex: AppearanceSizePreference.allCases.count - 1, overlay: overlay)
    }

    /// Wraps the segmented control's onAction so clicks on the Pro-only `.auto` segment are
    /// redirected to the Upgrade tab while Pro is locked, instead of writing the preference.
    private static func wrapAppearanceSizeProLockIntercept(_ segmentedControl: NSSegmentedControl) {
        let autoIndex = AppearanceSizePreference.allCases.count - 1
        let original = segmentedControl.onAction
        segmentedControl.onAction = { control in
            let segmented = control as! NSSegmentedControl
            if segmented.selectedSegment == autoIndex && LicenseManager.shared.isProLocked {
                let stored: AppearanceSizePreference = CachedUserDefaults.macroPref("appearanceSize", AppearanceSizePreference.allCases)
                segmented.selectedSegment = stored.index
                // We bail before `original` fires, so the overlay's selection-sync (which
                // normally runs in the `extraAction`) never executes. Trigger it manually so the
                // badge and label colors track the reset selection.
                refreshAutoSegmentAppearance(segmented)
                UpgradeTab.navigateToUpgradeTab()
                return
            }
            original?(control)
        }
    }

    static func addProBadgeToAutoSegment(_ segmentedControl: NSSegmentedControl) -> ProBadgeView.SegmentOverlay {
        return ProBadgeView.attach(to: segmentedControl,
            segmentIndex: AppearanceSizePreference.allCases.count - 1,
            label: AppearanceSizePreference.auto.localizedString,
            symbol: AppearanceSizePreference.auto.symbol)
    }

    static func addProBadgesToStyleButtons(_ stackView: NSStackView) {
        for (index, view) in stackView.arrangedSubviews.enumerated() {
            guard index > 0, let buttonView = view as? ImageTextButtonView else { continue }
            let badge = ProBadgeView()
            buttonView.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: buttonView.label.trailingAnchor, constant: 4),
                badge.centerYAnchor.constraint(equalTo: buttonView.label.centerYAnchor, constant: 1),
            ])
        }
    }

    /// Indices of `AppearanceStylePreference.allCases` that are Pro-only (everything but `.thumbnails`).
    static func proGatedAppearanceStyleIndices() -> Set<Int> {
        Set(AppearanceStylePreference.allCases.enumerated().compactMap { $0.element == .thumbnails ? nil : $0.offset })
    }

    /// Re-sync the 3 Pro-aware controls to the currently-stored preferences and the ghost state.
    /// Called when `ProTransitionManager.proLockStateDidChangeNotification` fires so a live Settings
    /// window updates immediately after Pro locks/unlocks (instead of requiring a reopen).
    static func refreshProLockUi() {
        if let styleButtons = styleButtonsStack {
            let storedStyle = CachedUserDefaults.intFromMacroPref("appearanceStyle", AppearanceStylePreference.allCases)
            for (index, view) in styleButtons.arrangedSubviews.enumerated() {
                guard let buttonView = view as? ImageTextButtonView else { continue }
                buttonView.state = (index == storedStyle) ? .on : .off
            }
        }
        if let sizeControl = sizeControlRef {
            let storedSize: AppearanceSizePreference = CachedUserDefaults.macroPref("appearanceSize", AppearanceSizePreference.allCases)
            sizeControl.selectedSegment = storedSize.index
            refreshAutoSegmentAppearance(sizeControl)
        }
        if let control = shortcutStyleControlRef {
            let storedShortcut: ShortcutStylePreference = CachedUserDefaults.macroPref("shortcutStyle", ShortcutStylePreference.allCases)
            control.selectedSegment = storedShortcut.index
            refreshShortcutStyleSegmentAppearance(control)
        }
    }


}
