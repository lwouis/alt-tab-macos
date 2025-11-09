import Cocoa

class ThumbnailView: FlippedView {
    static let noOpenWindowToolTip = NSLocalizedString("App is running but has no open window", comment: "")
    // when calculating the width of a nstextfield, somehow we need to add this suffix to get the correct width
    static let extraTextForPadding = "lmnopqrstuvw"
    var window_: Window?
    var thumbnail = LightImageView()
    var windowlessIcon = LightImageView()
    let thumbnailContainer = FlippedView()
    var appIcon = LightImageView()
    var label = ThumbnailTitleView(font: Appearance.font)
    var fullscreenIcon = ThumbnailFontIconView(symbol: .circledPlusSign, tooltip: NSLocalizedString("Window is fullscreen", comment: ""))
    var minimizedIcon = ThumbnailFontIconView(symbol: .circledMinusSign, tooltip: NSLocalizedString("Window is minimized", comment: ""))
    var hiddenIcon = ThumbnailFontIconView(symbol: .circledSlashSign, tooltip: NSLocalizedString("App is hidden", comment: ""))
    var spaceIcon = ThumbnailFontIconView(symbol: .circledNumber0)
    var dockLabelIcon = ThumbnailFilledFontIconView(
        ThumbnailFontIconView(symbol: .filledCircledNumber0, size: dockLabelLabelSize(), color: NSColor(srgbRed: 1, green: 0.30, blue: 0.25, alpha: 1)),
        backgroundColor: NSColor.white, size: dockLabelLabelSize())
    var quitIcon = TrafficLightButton(.quit, NSLocalizedString("Quit app", comment: ""))
    var closeIcon = TrafficLightButton(.close, NSLocalizedString("Close window", comment: ""))
    var minimizeIcon = TrafficLightButton(.miniaturize, NSLocalizedString("Minimize/Deminimize window", comment: ""))
    var maximizeIcon = TrafficLightButton(.fullscreen, NSLocalizedString("Fullscreen/Defullscreen window", comment: ""))
    var windowlessAppIndicator = WindowlessAppIndicator(tooltip: ThumbnailView.noOpenWindowToolTip)

    let hStackView = FlippedView()
    let vStackView = FlippedView()
    var mouseUpCallback: (() -> Void)!
    var mouseMovedCallback: (() -> Void)!
    var dragAndDropTimer: Timer?
    var indexInRecycledViews: Int!
    var isShowingWindowControls = false

    var isFirstInRow = false
    var isLastInRow = false
    var indexInRow = 0
    var numberOfViewsInRow = 0

    var windowControlIcons: [TrafficLightButton] { [quitIcon, closeIcon, minimizeIcon, maximizeIcon] }
    var windowIndicatorIcons: [ThumbnailFontIconView] { [hiddenIcon, fullscreenIcon, minimizedIcon, spaceIcon] }

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
            if Windows.focusedWindowIndex == Windows.hoveredWindowIndex {
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
        showOrHideWindowControls(true)
        mouseMovedCallback()
    }

    convenience init() {
        self.init(frame: .zero)
        setupView()
        observeDragAndDrop()
    }

    func updateRecycledCellWithNewContent(_ element: Window, _ index: Int, _ newHeight: CGFloat) {
        window_ = element
        updateValues(element, index, newHeight)
        updateSizes(newHeight)
        updatePositions(newHeight)
        label.toolTip = label.cell!.cellSize.width >= label.frame.size.width ? label.stringValue : nil
    }

    func drawHighlight() {
        let isFocused = indexInRecycledViews == Windows.focusedWindowIndex
        let isHovered = indexInRecycledViews == Windows.hoveredWindowIndex
        setBackground(isFocused: isFocused, isHovered: isHovered)
        setBorder(isFocused: isFocused, isHovered: isHovered)
        if Preferences.appearanceStyle == .appIcons {
            label.isHidden = !(isFocused || isHovered)
            updateAppIconsLabel(isFocused: isFocused, isHovered: isHovered)
        }
    }

    func showOrHideWindowControls(_ shouldShowWindowControls: Bool) {
        let shouldShow = shouldShowWindowControls && !Preferences.hideColoredCircles && !Appearance.hideThumbnails
        if Preferences.appearanceStyle == .thumbnails {
            isShowingWindowControls = shouldShow
            for icon in windowControlIcons {
                icon.isHidden = !shouldShow
                    || (icon.type == .quit && !(window_?.application.canBeQuit() ?? true))
                    || (icon.type == .close && !(window_?.canBeClosed() ?? true))
                    || ((icon.type == .miniaturize || icon.type == .fullscreen) && !(window_?.canBeMinDeminOrFullscreened() ?? true))
                // Force the icons to redraw; otherwise after clicking the fullscreen button,
                // it will still appear to be in fullscreen mode.
                icon.display()
            }
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
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityChildren([])
        wantsLayer = true
        layer!.masksToBounds = false // without this, label will be clipped in app-icons style since its larger than its parentView
        setupSharedSubviews()
        setupStyleSpecificSubviews()
    }

    private func setupSharedSubviews() {
        let shadow = ThumbnailView.makeShadow(Appearance.imagesShadowColor)
        thumbnailContainer.wantsLayer = true
        thumbnailContainer.layer!.masksToBounds = false // let thumbnail shadows show
        thumbnail.shadow = shadow
        windowlessIcon.shadow = shadow
        appIcon.shadow = shadow
        dockLabelIcon.shadow = shadow
        windowlessIcon.translatesAutoresizingMaskIntoConstraints = false
        windowlessIcon.toolTip = ThumbnailView.noOpenWindowToolTip
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.setSubviewAbove(dockLabelIcon)
        label.fixHeight()
        vStackView.wantsLayer = true
        vStackView.layer!.backgroundColor = .clear
        vStackView.layer!.borderColor = .clear
        vStackView.layer!.cornerRadius = Appearance.cellCornerRadius
        vStackView.layer!.borderWidth = CGFloat(1)
        setSubviews([vStackView])
        vStackView.setSubviews([hStackView])
        hStackView.setSubviews([appIcon])
    }

    private func setupStyleSpecificSubviews() {
        if Preferences.appearanceStyle == .appIcons {
            addSubviews([label])
            hStackView.setSubviewAbove(windowlessAppIndicator)
            label.alignment = .center
            label.isHidden = true
        } else if Preferences.appearanceStyle == .thumbnails {
            vStackView.addSubviews([thumbnailContainer])
            thumbnailContainer.setSubviews([thumbnail, windowlessIcon])
            thumbnailContainer.setSubviewAbove(windowlessAppIndicator)
            for icon in windowControlIcons {
                thumbnailContainer.setSubviewAbove(icon)
                icon.isHidden = true
            }
            hStackView.addSubviews([label] + windowIndicatorIcons)
        } else {
            hStackView.setSubviewAbove(windowlessAppIndicator)
            hStackView.addSubviews([label] + windowIndicatorIcons)
        }
    }

    private func getBackgroundColor(isFocused: Bool, isHovered: Bool) -> NSColor {
        if isFocused {
            return Appearance.highlightFocusedBackgroundColor
        }
        if isHovered {
            return Appearance.highlightHoveredBackgroundColor
        }
        return NSColor.clear
    }

    private func setBackground(isFocused: Bool, isHovered: Bool) {
        vStackView.layer!.backgroundColor = getBackgroundColor(isFocused: isFocused, isHovered: isHovered).cgColor
    }

    private func setBorder(isFocused: Bool, isHovered: Bool) {
        if isFocused {
            vStackView.layer!.borderColor = Appearance.highlightFocusedBorderColor.cgColor
            vStackView.layer!.borderWidth = Appearance.highlightBorderWidth
        } else if isHovered {
            vStackView.layer!.borderColor = Appearance.highlightHoveredBorderColor.cgColor
            vStackView.layer!.borderWidth = Appearance.highlightBorderWidth
        } else {
            vStackView.layer!.borderColor = NSColor.clear.cgColor
            vStackView.layer!.borderWidth = 0
        }
    }

    private func updateAppIconsLabel(isFocused: Bool, isHovered: Bool) {
        let focusedView = ThumbnailsView.recycledViews[Windows.focusedWindowIndex]
        var hoveredView: ThumbnailView? = nil
        if Windows.hoveredWindowIndex != nil {
            hoveredView = ThumbnailsView.recycledViews[Windows.hoveredWindowIndex!]
        }
        if isFocused || (!isFocused && !isHovered) {
            hoveredView?.label.isHidden = true
            focusedView.label.isHidden = false
            updateAppIconsLabelFrame(focusedView)
        } else if isHovered {
            hoveredView?.label.isHidden = false
            focusedView.label.isHidden = true
            if let hoveredView {
                updateAppIconsLabelFrame(hoveredView)
            }
        }
    }

    private func getMaxAllowedLabelWidth(_ view: ThumbnailView) -> CGFloat {
        let viewWidth = view.frame.width
        let maxAllowedWidth = min(viewWidth * 2, ThumbnailsView.thumbnailsWidth)
        let availableLeftWidth = view.isFirstInRow ? 0 : CGFloat(view.indexInRow) * viewWidth
        let availableRightWidth = view.isLastInRow ? 0 : CGFloat(view.numberOfViewsInRow - 1 - view.indexInRow) * viewWidth
        let totalWidth = availableLeftWidth + availableRightWidth + viewWidth
        let maxLabelWidth = min(totalWidth, maxAllowedWidth)
        return maxLabelWidth - Appearance.intraCellPadding * 2
    }

    private func updateAppIconsLabelFrame(_ view: ThumbnailView) {
        let viewWidth = view.frame.width
        let labelWidth = view.label.cell!.cellSize.width
        let maxAllowedLabelWidth = getMaxAllowedLabelWidth(view)
        let effectiveLabelWidth = max(min(labelWidth, maxAllowedLabelWidth), viewWidth)
            - (view.isFirstInRow && view.isLastInRow ? 4 : (view.isFirstInRow || view.isLastInRow ? 2 : 0)) * Appearance.intraCellPadding
        var leftOffset = -Appearance.intraCellPadding * 2
        if view.isFirstInRow && view.isLastInRow {
            leftOffset = -Appearance.intraCellPadding * 2

        } else if view.isLastInRow {
            leftOffset = max(0, effectiveLabelWidth - viewWidth + Appearance.intraCellPadding * 2)
        } else if !view.isFirstInRow && !view.isLastInRow {
            let halfNeededOffset = max(0, (effectiveLabelWidth - viewWidth) / 2)
            let availableLeftWidth = view.isFirstInRow ? 0 : CGFloat(view.indexInRow) * viewWidth
            let availableRightWidth = view.isLastInRow ? 0 : CGFloat(view.numberOfViewsInRow - 1 - view.indexInRow) * viewWidth
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
        let height = view.label.fittingSize.height
        let yPosition = view.hStackView.frame.origin.y + view.hStackView.frame.height + Appearance.intraCellPadding * 2
        view.label.frame = NSRect(x: xPosition, y: yPosition, width: effectiveLabelWidth, height: height)
        view.label.setWidth(effectiveLabelWidth)
        view.label.toolTip = view.label.cell!.cellSize.width >= view.label.frame.size.width ? view.label.stringValue : nil
    }

    private func updateAppIcon(_ element: Window, _ title: String) {
        let appIconSize = ThumbnailView.iconSize()
        appIcon.updateWithResizedCopy(element.icon, appIconSize)
        appIcon.setAccessibilityLabel(title)
    }

    private func updateValues(_ element: Window, _ index: Int, _ newHeight: CGFloat) {
        assignIfDifferent(&thumbnail.isHidden, Appearance.hideThumbnails || element.isWindowlessApp)
        assignIfDifferent(&windowlessIcon.isHidden, !element.isWindowlessApp || Appearance.hideThumbnails)
        assignIfDifferent(&windowlessAppIndicator.isHidden, !element.isWindowlessApp)
        assignIfDifferent(&hiddenIcon.isHidden, !element.isHidden || Preferences.hideStatusIcons)
        assignIfDifferent(&fullscreenIcon.isHidden, !element.isFullscreen || Preferences.hideStatusIcons)
        assignIfDifferent(&minimizedIcon.isHidden, !element.isMinimized || Preferences.hideStatusIcons)
        assignIfDifferent(&spaceIcon.isHidden, element.isWindowlessApp || Spaces.isSingleSpace() || Preferences.hideSpaceNumberLabels || (
            Preferences.spacesToShow[App.app.shortcutIndex] == .visible && (
                NSScreen.screens.count < 2 || Preferences.screensToShow[App.app.shortcutIndex] == .showingAltTab
            )
        ))
        if !thumbnail.isHidden {
            if let screenshot = element.thumbnail {
                let thumbnailSize = ThumbnailView.thumbnailSize(screenshot, false)
                thumbnail.updateWithResizedCopy(screenshot, thumbnailSize)
            } else {
                // if no thumbnail, show appIcon instead
                let thumbnailSize = ThumbnailView.thumbnailSize(element.icon, true)
                thumbnail.updateWithResizedCopy(element.icon, thumbnailSize)
            }
            // for Accessibility > "speak items under the pointer"
            thumbnail.setAccessibilityLabel(element.title)
        }
        let title = getAppOrAndWindowTitle()
        let labelChanged = label.stringValue != title
        if labelChanged {
            label.stringValue = title
            setAccessibilityLabel(title)
        }
        label.updateTruncationModeIfNeeded()
        if !spaceIcon.isHidden {
            let spaceIndex = element.spaceIndexes.first
            if element.isOnAllSpaces || (spaceIndex != nil && spaceIndex! > 30) {
                spaceIcon.setStar()
                spaceIcon.toolTip = NSLocalizedString("Window is on every Space", comment: "")
            } else if let spaceIndex {
                spaceIcon.setNumber(spaceIndex, false)
                spaceIcon.toolTip = String(format: NSLocalizedString("Window is on Space %d", comment: ""), spaceIndex)
            }
        }
        updateAppIcon(element, title)
        updateDockLabelIcon(element.dockLabel)
        setAccessibilityHelp(getAccessibilityHelp(element.application.localizedName, element.dockLabel))
        if !windowlessIcon.isHidden {
            let windowlessIconSize = ThumbnailView.thumbnailSize(element.icon, true)
            windowlessIcon.updateWithResizedCopy(element.icon, windowlessIconSize)
        }
        windowControlIcons.forEach { $0.window_ = element }
        showOrHideWindowControls(isShowingWindowControls)
        mouseUpCallback = { () -> Void in App.app.focusSelectedWindow(element) }
        mouseMovedCallback = { () -> Void in Windows.updateFocusedAndHoveredWindowIndex(index, true) }
    }

    private func updateSizes(_ newHeight: CGFloat) {
        setFrameWidthHeight(newHeight)
        if Preferences.appearanceStyle == .appIcons {
            vStackView.frame.size = NSSize(width: frame.width, height: appIcon.frame.height + Appearance.edgeInsetsSize * 2)
            hStackView.frame.size = NSSize(width: appIcon.frame.width, height: appIcon.frame.height)
        } else {
            vStackView.frame.size = NSSize(width: frame.width, height: frame.height)
            hStackView.frame.size = NSSize(width: frame.width - Appearance.edgeInsetsSize * 2, height: max(appIcon.frame.height, label.fittingSize.height))
            let labelWidth = hStackView.frame.width - appIcon.frame.width - Appearance.appIconLabelSpacing - indicatorsSpace()
            label.setWidth(labelWidth)
        }
        if Preferences.appearanceStyle == .thumbnails {
            let content = !windowlessIcon.isHidden ? windowlessIcon : thumbnail
            thumbnailContainer.frame.size = NSSize(width: hStackView.frame.width, height: content.frame.height)
        }
    }

    private func updatePositions(_ newHeight: CGFloat) {
        hStackView.frame.origin = NSPoint(x: Appearance.edgeInsetsSize, y: Appearance.edgeInsetsSize)
        if Preferences.appearanceStyle != .appIcons {
            appIcon.frame.origin.x = App.shared.userInterfaceLayoutDirection == .leftToRight
                ? 0
                : hStackView.frame.width - appIcon.frame.width
            let iconWidth = windowIndicatorIcons.first!.fittingSize.width
            var indicatorSpace = CGFloat(0)
            for icon in windowIndicatorIcons {
                if !icon.isHidden {
                    indicatorSpace += iconWidth
                    icon.centerFrameInParent(y: true)
                    icon.frame.origin.x = App.shared.userInterfaceLayoutDirection == .leftToRight
                        ? hStackView.frame.width - indicatorSpace
                        : indicatorSpace - iconWidth
                }
            }
            let labelWidth = hStackView.frame.width - appIcon.frame.width - Appearance.appIconLabelSpacing - indicatorSpace
            label.frame.origin.x = App.shared.userInterfaceLayoutDirection == .leftToRight
                ? appIcon.frame.maxX + Appearance.appIconLabelSpacing
                : hStackView.frame.width - appIcon.frame.width - Appearance.appIconLabelSpacing - labelWidth
            label.centerFrameInParent(y: true)
        }
        if Preferences.appearanceStyle == .thumbnails {
            let content = !windowlessIcon.isHidden ? windowlessIcon : thumbnail
            thumbnailContainer.frame.origin = NSPoint(x: Appearance.edgeInsetsSize, y: hStackView.frame.maxY + Appearance.intraCellPadding)
            content.centerFrameInParent(x: true)
            var xOffset = CGFloat(3)
            var yOffset = CGFloat(2)
            for icon in windowControlIcons {
                icon.frame.origin = NSPoint(x: xOffset, y: yOffset)
                xOffset += TrafficLightButton.size + TrafficLightButton.spacing
                if xOffset + TrafficLightButton.size > thumbnailContainer.frame.width {
                    xOffset = 3 + Appearance.edgeInsetsSize
                    yOffset += TrafficLightButton.size + TrafficLightButton.spacing
                }
            }
        }
        if !windowlessAppIndicator.isHidden {
            if Preferences.appearanceStyle != .titles {
                windowlessAppIndicator.centerFrameInParent(x: true)
            } else {
                windowlessAppIndicator.frame.origin.x = ((appIcon.frame.width / 2) - (windowlessAppIndicator.frame.width / 2)).rounded()
                    + (App.shared.userInterfaceLayoutDirection == .leftToRight ? 0 : appIcon.frame.origin.x)
            }
            windowlessAppIndicator.frame.origin.y = windowlessAppIndicator.superview!.frame.height - windowlessAppIndicator.frame.height + 5
        }
        // we set dockLabelIcon origin, without checking if .isHidden
        // This is because its updated async. We need it positioned correctly always
        let (offsetX, offsetY) = dockLabelOffset()
        dockLabelIcon.frame.origin.x = appIcon.frame.maxX - (dockLabelIcon.fittingSize.width * offsetX).rounded()
        dockLabelIcon.frame.origin.y = appIcon.frame.maxY - (dockLabelIcon.fittingSize.height * offsetY).rounded()
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

    private func indicatorsSpace() -> CGFloat {
        let iconWidth = windowIndicatorIcons.first!.fittingSize.width
        return CGFloat(windowIndicatorIcons.filter { !$0.isHidden }.count) * iconWidth
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
            contentWidth = (!windowlessIcon.isHidden ? windowlessIcon : thumbnail).frame.size.width
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
        // NSImageView instances are registered to drag-and-drop by default
        thumbnail.unregisterDraggedTypes()
        appIcon.unregisterDraggedTypes()
        windowlessIcon.unregisterDraggedTypes()
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

    static func maxThumbnailWidth() -> CGFloat {
        return ThumbnailsPanel.maxThumbnailsWidth() * Appearance.windowMaxWidthInRow - Appearance.interCellPadding * 2
    }

    static func widthOfComfortableReadability() -> CGFloat? {
        let labTitleView = ThumbnailTitleView(font: Appearance.font)
        labTitleView.stringValue = "abcdefghijklmnopqrstuvwxyz-abcdefghijklmnopqrstuvwxyz-abcdefghijk" + extraTextForPadding
        Logger.error(labTitleView.font)
        return labTitleView.fittingSize.width
    }

    static func widthOfLongestTitle() -> CGFloat? {
        let labTitleView = ThumbnailTitleView(font: Appearance.font)
        var maxWidth = CGFloat(0)
        for window in Windows.list {
            guard window.shouldShowTheUser else { continue }
            labTitleView.stringValue = window.title + extraTextForPadding
            let width = labTitleView.fittingSize.width
            if width > maxWidth {
                maxWidth = width
            }
        }
        guard maxWidth > 0 else { return nil }
        return maxWidth
    }

    static func minThumbnailWidth() -> CGFloat {
        return ThumbnailsPanel.maxThumbnailsWidth() * Appearance.windowMinWidthInRow - Appearance.interCellPadding * 2
    }

    /// The maximum height that a thumbnail can be drawn
    /// maxThumbnailsHeight = maxThumbnailHeight * rowCount + interCellPadding * (rowCount - 1)
    /// maxThumbnailHeight = (maxThumbnailsHeight - interCellPadding * (rowCount - 1)) / rowCount
    static func maxThumbnailHeight() -> CGFloat {
        return ((ThumbnailsPanel.maxThumbnailsHeight() - Appearance.interCellPadding) / Appearance.rowsCount - Appearance.interCellPadding).rounded()
    }

    static func thumbnailSize(_ image: CGImage?, _ isWindowlessApp: Bool) -> NSSize {
        guard let image else { return NSSize(width: 0, height: 0) }
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        let thumbnailHeightMax = ThumbnailView.maxThumbnailHeight()
            - Appearance.edgeInsetsSize * 2
            - Appearance.intraCellPadding
            - Appearance.iconSize
        let thumbnailWidthMax = ThumbnailView.maxThumbnailWidth()
            - Appearance.edgeInsetsSize * 2
        // don't stretch very small windows; keep them 1:1 in the switcher
        if !isWindowlessApp && imageWidth < thumbnailWidthMax && imageHeight < thumbnailHeightMax {
            return NSSize(width: imageWidth, height: imageHeight)
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

    static func iconSize() -> NSSize {
        if Preferences.appearanceStyle == .appIcons {
            let widthMin = ThumbnailView.minThumbnailWidth()
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
