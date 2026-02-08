import Cocoa

class ThumbnailView: FlippedView {
    static let noOpenWindowToolTip = NSLocalizedString("App is running but has no open window", comment: "")
    // when calculating the width of a nstextfield, somehow we need to add this suffix to get the correct width
    static let extraTextForPadding = "lmnopqrstuvw"

    var window_: Window?
    var thumbnail = LightImageLayer(withTransparencyChecks: true)
    var appIcon = LightImageLayer()
    var label = ThumbnailTitleView(font: Appearance.font)
    var statusIcons = StatusIconsView()
    var dockLabelIcon = ThumbnailFilledFontIconView(
        ThumbnailFontIconView(symbol: .filledCircledNumber0, size: dockLabelLabelSize(), color: NSColor(srgbRed: 1, green: 0.30, blue: 0.25, alpha: 1)),
        backgroundColor: NSColor.white, size: dockLabelLabelSize())
    var windowlessAppIndicator = WindowlessAppIndicator(tooltip: ThumbnailView.noOpenWindowToolTip)

    var mouseUpCallback: (() -> Void)!
    var mouseMovedCallback: (() -> Void)!
    var dragAndDropTimer: Timer?
    var indexInRecycledViews: Int!

    var isFirstInRow = false
    var isLastInRow = false
    var indexInRow = 0
    var numberOfViewsInRow = 0

    var receivedMouseDown = false

    // for VoiceOver cursor
    override var canBecomeKeyView: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func isAccessibilityElement() -> Bool { true }

    override func wantsPeriodicDraggingUpdates() -> Bool { false }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        mouseMovedCallback()
        setDraggingTimer()
        return .link
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        setDraggingTimer()
        return .link
    }

    private func setDraggingTimer() {
        dragAndDropTimer?.invalidate()
        dragAndDropTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false, block: { _ in
            // the user can tab to focus the next thumbnail, while still dragging. We don't want to perform drag then
            if Windows.selectedWindowIndex == Windows.hoveredWindowIndex {
                self.mouseUpCallback()
            }
        })
        dragAndDropTimer?.tolerance = 0.2
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragAndDropTimer?.invalidate()
        dragAndDropTimer = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragAndDropTimer?.invalidate()
        dragAndDropTimer = nil
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as! [URL]
        let appUrl = window_!.application.bundleURL!
        let open = try? NSWorkspace.shared.open(urls, withApplicationAt: appUrl, options: [], configuration: [:])
        App.app.hideUi()
        return open != nil
    }

    override func mouseDown(with event: NSEvent) {
        receivedMouseDown = true
    }

    override func mouseUp(with event: NSEvent) {
        if receivedMouseDown {
            if bounds.contains(convert(event.locationInWindow, from: nil)) {
                mouseUpCallback()
            }
            receivedMouseDown = false
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        // middle-click
        if event.buttonNumber == 2 {
            if let window_ {
                if window_.isWindowlessApp {
                    window_.application.quit()
                } else {
                    window_.close()
                }
            }
        }
    }

    func mouseMoved() {
        updateLabelTooltipIfNeeded()
        mouseMovedCallback()
    }

    private func updateLabelTooltipIfNeeded() {
        guard Preferences.appearanceStyle != .appIcons else { return }
        label.toolTip = label.cell!.cellSize.width >= label.frame.size.width ? label.stringValue : nil
    }

    convenience init() {
        self.init(frame: .zero)
        setupView()
        observeDragAndDrop()
    }

    /// The frame used by HighlightOverlayView to position the highlight rectangle.
    /// In appIcons style, it covers appIcon + edge insets. Otherwise, it covers the full cell.
    var highlightFrame: CGRect {
        if Preferences.appearanceStyle == .appIcons {
            return CGRect(x: 0, y: 0,
                          width: frame.width, height: appIcon.frame.height + Appearance.edgeInsetsSize * 2)
        }
        return CGRect(origin: .zero, size: frame.size)
    }

    func updateRecycledCellWithNewContent(_ element: Window, _ index: Int, _ newHeight: CGFloat) {
        window_ = element
        label.toolTip = nil
        updateValues(element, index, newHeight)
        updateSizes(newHeight)
        updatePositions(newHeight)
    }

    func drawHighlight() {
        if Preferences.appearanceStyle == .appIcons {
            let isFocused = indexInRecycledViews == Windows.selectedWindowIndex
            let isHovered = indexInRecycledViews == Windows.hoveredWindowIndex
            label.isHidden = !(isFocused || isHovered)
            updateAppIconsLabel(isFocused: isFocused, isHovered: isHovered)
        }
    }

    func updateDockLabelIcon(_ dockLabel: String?) {
        assignIfDifferent(&dockLabelIcon.isHidden, dockLabel == nil || Preferences.hideAppBadges || Appearance.iconSize == 0)
        if !dockLabelIcon.isHidden, let dockLabel {
            let view = dockLabelIcon.subviews[1] as! ThumbnailFontIconView
            let dockLabelInt = Int(dockLabel)
            if dockLabelInt == nil || dockLabelInt! > 30 {
                view.setFilledStar()
            } else {
                view.setNumber(dockLabelInt!, true)
            }
            view.setAccessibilityLabel(getAccessibilityTextForBadge(dockLabel))
        }
    }

    private func setupView() {
        setAccessibilityChildren([])
        wantsLayer = true
        layer!.masksToBounds = false // without this, label will be clipped in app-icons style since its larger than its parentView
        setupSharedSubviews()
        setupStyleSpecificSubviews()
    }

    private func setupSharedSubviews() {
        let shadow = ThumbnailView.makeShadow(Appearance.imagesShadowColor)
        thumbnail.masksToBounds = false // let thumbnail shadows show
        thumbnail.applyShadow(shadow)
        appIcon.applyShadow(shadow)
        dockLabelIcon.shadow = shadow
        layer!.addSublayer(appIcon)
        addSubview(dockLabelIcon)
        label.fixHeight()
    }

    private func setupStyleSpecificSubviews() {
        if Preferences.appearanceStyle == .appIcons {
            addSubviews([label])
            setSubviewAbove(windowlessAppIndicator)
            label.alignment = .center
            label.isHidden = true
        } else if Preferences.appearanceStyle == .thumbnails {
            layer!.addSublayer(thumbnail)
            addSubviews([label, statusIcons])
            setSubviewAbove(windowlessAppIndicator)
        } else {
            setSubviewAbove(windowlessAppIndicator)
            addSubviews([label, statusIcons])
        }
    }

    private func updateAppIconsLabel(isFocused: Bool, isHovered: Bool) {
        let focusedView = ThumbnailsView.recycledViews[Windows.selectedWindowIndex]
        var hoveredView: ThumbnailView? = nil
        if Windows.hoveredWindowIndex != nil {
            hoveredView = ThumbnailsView.recycledViews[Windows.hoveredWindowIndex!]
        }
        if isFocused || (!isFocused && !isHovered) {
            hoveredView?.label.isHidden = true
            focusedView.label.isHidden = false
            focusedView.updateAppIconsLabelFrame()
        } else if isHovered {
            hoveredView?.label.isHidden = false
            focusedView.label.isHidden = true
            if let hoveredView {
                hoveredView.updateAppIconsLabelFrame()
            }
        }
    }

    private func getMaxAllowedLabelWidth() -> CGFloat {
        let viewWidth = frame.width
        let maxAllowedWidth = min(viewWidth * 2, ThumbnailsView.thumbnailsWidth)
        let availableLeftWidth = isFirstInRow ? 0 : CGFloat(indexInRow) * viewWidth
        let availableRightWidth = isLastInRow ? 0 : CGFloat(numberOfViewsInRow - 1 - indexInRow) * viewWidth
        let totalWidth = availableLeftWidth + availableRightWidth + viewWidth
        let maxLabelWidth = min(totalWidth, maxAllowedWidth)
        return maxLabelWidth - Appearance.intraCellPadding * 2
    }

    private func updateAppIconsLabelFrame() {
        let viewWidth = frame.width
        let labelWidth = label.cell!.cellSize.width
        let padding = (Preferences.appearanceSize == .small ? 0 : ( Preferences.appearanceSize == .medium ? 1 : 2)) * Appearance.intraCellPadding
        let maxAllowedLabelWidth = getMaxAllowedLabelWidth()
        let sidesToOffset: CGFloat = (isFirstInRow ? 1 : 0) + (isLastInRow ? 1 : 0)
        let paddingForOffset = sidesToOffset * padding
        var effectiveLabelWidth = max(min(labelWidth, maxAllowedLabelWidth), viewWidth) - paddingForOffset
        // if the label is small, and with an offset only on one side, we reduce its width to center its text
        if sidesToOffset == 1 && labelWidth <= (effectiveLabelWidth - paddingForOffset) {
            effectiveLabelWidth -= paddingForOffset
        }
        var leftOffset = CGFloat(0)
        if isFirstInRow {
            leftOffset = -padding
        } else if isLastInRow {
            leftOffset = effectiveLabelWidth - viewWidth + padding
        } else {
            let halfNeededOffset = max(0, (effectiveLabelWidth - viewWidth) / 2)
            let availableLeftWidth = isFirstInRow ? 0 : CGFloat(indexInRow) * viewWidth
            let availableRightWidth = isLastInRow ? 0 : CGFloat(numberOfViewsInRow - 1 - indexInRow) * viewWidth
            if availableLeftWidth >= halfNeededOffset && availableRightWidth >= halfNeededOffset {
                leftOffset = halfNeededOffset
            } else if availableLeftWidth <= halfNeededOffset && availableRightWidth <= halfNeededOffset {
                leftOffset = availableLeftWidth
            } else if availableRightWidth <= halfNeededOffset {
                leftOffset = min(effectiveLabelWidth - viewWidth - availableRightWidth, availableLeftWidth)
            } else if availableLeftWidth <= halfNeededOffset {
                leftOffset = availableLeftWidth
            }
        }
        let xPosition = -leftOffset
        let height = ThumbnailsView.layoutCache.labelHeight
        let yPosition = appIcon.frame.maxY + Appearance.intraCellPadding * 2
        label.frame = NSRect(x: xPosition, y: yPosition, width: effectiveLabelWidth, height: height)
        label.setWidth(effectiveLabelWidth)
        label.toolTip = label.cell!.cellSize.width >= label.frame.size.width ? label.stringValue : nil
    }

    private func updateAppIcon(_ element: Window, _ title: String) {
        let appIconSize = ThumbnailView.iconSize()
        appIcon.updateContents(.cgImage(element.icon), appIconSize)
    }

    private func updateValues(_ element: Window, _ index: Int, _ newHeight: CGFloat) {
        assignIfDifferent(&windowlessAppIndicator.isHidden, !element.isWindowlessApp)
        statusIcons.update(
            isHidden: element.isHidden && !Preferences.hideStatusIcons,
            isFullscreen: element.isFullscreen && !Preferences.hideStatusIcons,
            isMinimized: element.isMinimized && !Preferences.hideStatusIcons,
            showSpace: !(element.isWindowlessApp || Spaces.isSingleSpace() || Preferences.hideSpaceNumberLabels || (
                Preferences.spacesToShow[App.app.shortcutIndex] == .visible && (
                    NSScreen.screens.count < 2 || Preferences.screensToShow[App.app.shortcutIndex] == .showingAltTab
                )
            ))
        )
        if !thumbnail.isHidden {
            if let screenshot = element.thumbnail {
                let thumbnailSize = ThumbnailView.thumbnailSize(element.size, false)
                thumbnail.updateContents(screenshot, thumbnailSize)
            } else {
                // if no thumbnail, show appIcon instead
                let thumbnailSize = ThumbnailView.thumbnailSize(element.icon?.size(), true)
                thumbnail.updateContents(.cgImage(element.icon), thumbnailSize)
            }
        }
        let title = getAppOrAndWindowTitle()
        let labelChanged = label.stringValue != title
        if labelChanged {
            label.stringValue = title
            setAccessibilityLabel(title)
        }
        label.updateTruncationModeIfNeeded()
        if statusIcons.spaceVisible {
            let spaceIndex = element.spaceIndexes.first
            if element.isOnAllSpaces || (spaceIndex != nil && spaceIndex! > 30) {
                statusIcons.setSpaceStar()
            } else if let spaceIndex {
                statusIcons.setSpaceNumber(spaceIndex)
            }
        }
        updateAppIcon(element, title)
        updateDockLabelIcon(element.dockLabel)
        setAccessibilityHelp(getAccessibilityHelp(element.application.localizedName, element.dockLabel))
        mouseUpCallback = { () -> Void in App.app.focusSelectedWindow(element) }
        mouseMovedCallback = { () -> Void in Windows.updateSelectedAndHoveredWindowIndex(index, true) }
    }

    private func updateSizes(_ newHeight: CGFloat) {
        setFrameWidthHeight(newHeight)
        if Preferences.appearanceStyle != .appIcons {
            let hWidth = frame.width - Appearance.edgeInsetsSize * 2
            let labelWidth = hWidth - appIcon.frame.width - Appearance.appIconLabelSpacing - statusIcons.totalWidth
            label.setWidth(labelWidth)
        }
    }

    private func updatePositions(_ newHeight: CGFloat) {
        let edgeInsets = Appearance.edgeInsetsSize
        assignIfDifferent(&appIcon.frame.origin, NSPoint(x: edgeInsets, y: edgeInsets))
        if Preferences.appearanceStyle != .appIcons {
            let hWidth = frame.width - edgeInsets * 2
            let hHeight = max(appIcon.frame.height, ThumbnailsView.layoutCache.labelHeight)
            if App.shared.userInterfaceLayoutDirection == .rightToLeft {
                assignIfDifferent(&appIcon.frame.origin.x, edgeInsets + hWidth - appIcon.frame.width)
            }
            statusIcons.layoutIcons(hWidth: hWidth, hHeight: hHeight, edgeInsets: edgeInsets)
            let labelWidth = hWidth - appIcon.frame.width - Appearance.appIconLabelSpacing - statusIcons.totalWidth
            let labelX: CGFloat
            if App.shared.userInterfaceLayoutDirection == .leftToRight {
                labelX = appIcon.frame.maxX + Appearance.appIconLabelSpacing
            } else {
                labelX = edgeInsets + hWidth - appIcon.frame.width - Appearance.appIconLabelSpacing - labelWidth
            }
            assignIfDifferent(&label.frame.origin.x, labelX)
            assignIfDifferent(&label.frame.origin.y, edgeInsets + ((hHeight - ThumbnailsView.layoutCache.labelHeight) / 2).rounded())
        }
        if Preferences.appearanceStyle == .thumbnails {
            let hHeight = max(appIcon.frame.height, ThumbnailsView.layoutCache.labelHeight)
            assignIfDifferent(&thumbnail.frame.origin, NSPoint(x: edgeInsets, y: edgeInsets + hHeight + Appearance.intraCellPadding))
            thumbnail.centerInSuperlayer(x: true)
        }
        if !windowlessAppIndicator.isHidden {
            if Preferences.appearanceStyle == .thumbnails {
                windowlessAppIndicator.frame.origin.x = thumbnail.frame.origin.x + ((thumbnail.frame.width - windowlessAppIndicator.frame.width) / 2).rounded()
            } else if Preferences.appearanceStyle != .titles {
                windowlessAppIndicator.centerFrameInParent(x: true)
            } else {
                windowlessAppIndicator.frame.origin.x = ((appIcon.frame.width / 2) - (windowlessAppIndicator.frame.width / 2)).rounded()
                    + (App.shared.userInterfaceLayoutDirection == .leftToRight ? 0 : appIcon.frame.origin.x)
            }
            if Preferences.appearanceStyle != .thumbnails {
                windowlessAppIndicator.frame.origin.y = windowlessAppIndicator.superview!.frame.height - windowlessAppIndicator.frame.height + 5
            } else {
                windowlessAppIndicator.frame.origin.y = thumbnail.frame.origin.y - 5
            }
        }
        // we set dockLabelIcon origin, without checking if .isHidden
        // This is because its updated async. We need it positioned correctly always
        let (offsetX, offsetY) = dockLabelOffset()
        assignIfDifferent(&dockLabelIcon.frame.origin.x, appIcon.frame.maxX - (ThumbnailsView.layoutCache.dockLabelSize.width * offsetX).rounded())
        assignIfDifferent(&dockLabelIcon.frame.origin.y, appIcon.frame.maxY - (ThumbnailsView.layoutCache.dockLabelSize.height * offsetY).rounded())
    }

    /// positioning the dock label is messy because it's an NSTextField so it's visual size doesn't match what we can through APIs
    // TODO: remove this; find a better way
    private func dockLabelOffset() -> (CGFloat, CGFloat) {
        var offsetX = 0.6
        if Preferences.appearanceStyle == .appIcons {
            if Preferences.appearanceSize == .small {
                offsetX = 0.82
            } else if Preferences.appearanceSize == .medium {
                offsetX = 0.86
            } else { // .large
                offsetX = 0.92
            }
        }
        var offsetY = offsetX
        if Preferences.appearanceStyle == .appIcons {
            if Preferences.appearanceSize == .small {
                offsetY = 0.88
            } else if Preferences.appearanceSize == .medium {
                offsetY = 0.90
            } else { // .large
                offsetY = 0.92
            }
        }
        return (offsetX, offsetY)
    }

    private func getAppOrAndWindowTitle() -> String {
        let appName = window_?.application.localizedName
        let windowTitle = window_?.title
        if Preferences.onlyShowApplications() || Preferences.showTitles == .appName {
            return appName ?? ""
        } else if Preferences.showTitles == .appNameAndWindowTitle {
            return [appName, windowTitle].compactMap { $0 }.joined(separator: " - ")
        }
        return windowTitle ?? ""
    }

    private func setFrameWidthHeight(_ newHeight: CGFloat) {
        var contentWidth = CGFloat(0)
        if Preferences.appearanceStyle == .thumbnails {
            // Preferred to the width of the image, and the minimum width may be set to be large.
            contentWidth = thumbnail.frame.size.width
        } else if Preferences.appearanceStyle == .titles {
            contentWidth = ThumbnailView.maxThumbnailWidth() - Appearance.edgeInsetsSize * 2
        } else {
            contentWidth = Appearance.iconSize
        }
        let frameWidth = (contentWidth + Appearance.edgeInsetsSize * 2).rounded()
        let widthMin = ThumbnailView.minThumbnailWidth()
        let width = max(frameWidth, widthMin).rounded()
        assignIfDifferent(&frame.size.width, width)
        assignIfDifferent(&frame.size.height, newHeight)
    }

    private func getAccessibilityHelp(_ appName: String?, _ dockLabel: String?) -> String {
        [appName, dockLabel.map { getAccessibilityTextForBadge($0) }]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    private func getAccessibilityTextForBadge(_ dockLabel: String) -> String {
        if let dockLabelInt = Int(dockLabel) {
            return "Red badge with number \(dockLabelInt)"
        }
        return "Red badge"
    }

    private func observeDragAndDrop() {
        // we only handle URLs (i.e. not text, image, or other draggable things)
        registerForDraggedTypes([NSPasteboard.PasteboardType(kUTTypeURL as String)])
    }

    static func dockLabelLabelSize() -> CGFloat {
        let size = (ThumbnailView.iconSize().width * 0.43).rounded()
        // label should have a minimum size for readability
        return max(size, 13)
    }

    static func makeShadow(_ color: NSColor?) -> NSShadow? {
        if color == nil {
            return nil
        }
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 1
        return shadow
    }

    static func maxThumbnailWidth(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
        return ThumbnailsPanel.maxThumbnailsWidth(screen) * Appearance.windowMaxWidthInRow - Appearance.interCellPadding * 2
    }

    static func widthOfComfortableReadability() -> CGFloat? {
        let labTitleView = ThumbnailTitleView(font: Appearance.font)
        labTitleView.stringValue = "abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz" + extraTextForPadding
        return labTitleView.cell!.cellSize.width
    }

    static func widthOfLongestTitle() -> CGFloat? {
        let labTitleView = ThumbnailTitleView(font: Appearance.font)
        var maxWidth = CGFloat(0)
        for window in Windows.list {
            guard window.shouldShowTheUser else { continue }
            labTitleView.stringValue = window.title + extraTextForPadding
            let width = labTitleView.cell!.cellSize.width
            if width > maxWidth {
                maxWidth = width
            }
        }
        guard maxWidth > 0 else { return nil }
        return maxWidth
    }

    static func minThumbnailWidth(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
        return ThumbnailsPanel.maxThumbnailsWidth(screen) * Appearance.windowMinWidthInRow - Appearance.interCellPadding * 2
    }

    /// The maximum height that a thumbnail can be drawn
    /// maxThumbnailsHeight = maxThumbnailHeight * rowCount + interCellPadding * (rowCount - 1)
    /// maxThumbnailHeight = (maxThumbnailsHeight - interCellPadding * (rowCount - 1)) / rowCount
    static func maxThumbnailHeight(_ screen: NSScreen = NSScreen.preferred) -> CGFloat {
        return ((ThumbnailsPanel.maxThumbnailsHeight(screen) - Appearance.interCellPadding) / Appearance.rowsCount - Appearance.interCellPadding).rounded()
    }

    static func thumbnailSize(_ imageSize: NSSize?, _ isWindowlessApp: Bool) -> NSSize {
        guard let imageSize else { return NSSize(width: 0, height: 0) }
        let imageWidth = imageSize.width
        let imageHeight = imageSize.height
        let thumbnailHeightMax = ThumbnailView.maxThumbnailHeight()
            - Appearance.edgeInsetsSize * 2
            - Appearance.intraCellPadding
            - Appearance.iconSize
        let thumbnailWidthMax = ThumbnailView.maxThumbnailWidth()
            - Appearance.edgeInsetsSize * 2
        // don't stretch very small windows; keep them 1:1 in the switcher
        if !isWindowlessApp && imageWidth < thumbnailWidthMax && imageHeight < thumbnailHeightMax {
            return imageSize
        }
        let thumbnailHeight = min(imageHeight, thumbnailHeightMax)
        let thumbnailWidth = min(imageWidth, thumbnailWidthMax)
        let imageRatio = imageWidth / imageHeight
        let thumbnailRatio = thumbnailWidth / thumbnailHeight
        var width: CGFloat
        var height: CGFloat
        if thumbnailRatio > imageRatio {
            // Keep the height and reduce the width
            width = imageWidth * thumbnailHeight / imageHeight
            height = thumbnailHeight
        } else if thumbnailRatio < imageRatio {
            // Keep the width and reduce the height
            width = thumbnailWidth
            height = imageHeight * thumbnailWidth / imageWidth
        } else {
            // Enlarge the height to the maximum height and enlarge the width
            width = thumbnailHeightMax / imageHeight * imageWidth
            height = thumbnailHeightMax
        }
        return NSSize(width: width.rounded(), height: height.rounded())
    }

    static func iconSize(_ screen: NSScreen = NSScreen.preferred) -> NSSize {
        if Preferences.appearanceStyle == .appIcons {
            let widthMin = ThumbnailView.minThumbnailWidth(screen)
            let contentWidth = Appearance.iconSize
            let frameWidth = contentWidth + Appearance.edgeInsetsSize * 2
            let width = max(frameWidth, widthMin).rounded()
            if widthMin > frameWidth {
                let iconSize = width - Appearance.edgeInsetsSize * 2
                return NSSize(width: iconSize, height: iconSize)
            }
        }
        return NSSize(width: Appearance.iconSize, height: Appearance.iconSize)
    }

    static func height(_ labelHeight: CGFloat) -> CGFloat {
        if Preferences.appearanceStyle == .titles {
            return max(ThumbnailView.iconSize().height, labelHeight) + Appearance.edgeInsetsSize * 2
        } else if Preferences.appearanceStyle == .appIcons {
            return ThumbnailView.iconSize().height + Appearance.edgeInsetsSize * 2 + Appearance.intraCellPadding * 2 + labelHeight
        }
        return ThumbnailView.maxThumbnailHeight()
    }
}

class StatusIconsView: FlippedView {
    struct Icon {
        var symbol: String
        var tooltip: String?
        var visible = false
    }

    static let hiddenIdx = 0
    static let fullscreenIdx = 1
    static let minimizedIdx = 2
    static let spaceIdx = 3

    private static let defaultSymbols: [(Symbols, String?)] = [
        (.circledSlashSign, NSLocalizedString("App is hidden", comment: "")),
        (.circledPlusSign, NSLocalizedString("Window is fullscreen", comment: "")),
        (.circledMinusSign, NSLocalizedString("Window is minimized", comment: "")),
        (.circledNumber0, nil),
    ]

    var icons: [Icon]
    private let attrs: [NSAttributedString.Key: Any]
    private var visibleCount = 0
    /// Single-character cell size, cached at init for the layout cache
    let iconCellSize: NSSize

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame: NSRect) {
        let font = NSFont(name: "SF Pro Text", size: (Appearance.fontHeight * 0.85).rounded())!
        let paragraphStyle = ThumbnailFontIconView.paragraphStyle
        attrs = [.font: font, .foregroundColor: Appearance.fontColor, .paragraphStyle: paragraphStyle]
        icons = Self.defaultSymbols.map { Icon(symbol: $0.0.rawValue, tooltip: $0.1) }
        let measure = NSAttributedString(string: Symbols.circledNumber0.rawValue, attributes: attrs)
        iconCellSize = measure.size()
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    var totalWidth: CGFloat { CGFloat(visibleCount) * ThumbnailsView.layoutCache.iconWidth }

    func update(isHidden: Bool, isFullscreen: Bool, isMinimized: Bool, showSpace: Bool) {
        icons[Self.hiddenIdx].visible = isHidden
        icons[Self.fullscreenIdx].visible = isFullscreen
        icons[Self.minimizedIdx].visible = isMinimized
        icons[Self.spaceIdx].visible = showSpace
        visibleCount = icons.count(where: { $0.visible })
    }

    func setSpaceStar() {
        icons[Self.spaceIdx].symbol = Symbols.circledStar.rawValue
        icons[Self.spaceIdx].tooltip = NSLocalizedString("Window is on every Space", comment: "")
    }

    func setSpaceNumber(_ number: Int) {
        let (base, offset) = number <= 9
            ? (Symbols.circledNumber0.rawValue, number * 2)
            : (Symbols.circledNumber10.rawValue, number - 10)
        icons[Self.spaceIdx].symbol = String(UnicodeScalar(Int(base.unicodeScalars.first!.value) + offset)!)
        icons[Self.spaceIdx].tooltip = String(format: NSLocalizedString("Window is on Space %d", comment: ""), number)
    }

    var spaceVisible: Bool { icons[Self.spaceIdx].visible }

    func layoutIcons(hWidth: CGFloat, hHeight: CGFloat, edgeInsets: CGFloat) {
        let indicatorSpace = totalWidth
        assignIfDifferent(&frame.size.width, indicatorSpace)
        assignIfDifferent(&frame.size.height, hHeight)
        let isLTR = App.shared.userInterfaceLayoutDirection == .leftToRight
        assignIfDifferent(&frame.origin.x, isLTR ? edgeInsets + hWidth - indicatorSpace : edgeInsets)
        assignIfDifferent(&frame.origin.y, edgeInsets)
        removeAllToolTips()
        let iconWidth = ThumbnailsView.layoutCache.iconWidth
        let iconHeight = ThumbnailsView.layoutCache.iconHeight
        let yOffset = ((hHeight - iconHeight) / 2).rounded()
        var offset = CGFloat(0)
        for icon in icons {
            guard icon.visible else { continue }
            offset += iconWidth
            let x = isLTR ? indicatorSpace - offset : offset - iconWidth
            if let tooltip = icon.tooltip {
                _ = addToolTip(NSRect(x: x, y: yOffset, width: iconWidth, height: iconHeight), owner: tooltip as NSString, userData: nil)
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard visibleCount > 0 else { return }
        let iconWidth = ThumbnailsView.layoutCache.iconWidth
        let iconHeight = ThumbnailsView.layoutCache.iconHeight
        let isLTR = App.shared.userInterfaceLayoutDirection == .leftToRight
        let yOffset = ((frame.height - iconHeight) / 2).rounded()
        var offset = CGFloat(0)
        for icon in icons {
            guard icon.visible else { continue }
            offset += iconWidth
            let x = isLTR ? frame.width - offset : offset - iconWidth
            icon.symbol.draw(at: NSPoint(x: x, y: yOffset), withAttributes: attrs)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        // no-op prevents tooltips from disappearing on mouseMoved
    }
}
