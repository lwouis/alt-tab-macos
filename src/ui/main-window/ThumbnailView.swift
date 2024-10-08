import Cocoa

class ThumbnailView: NSStackView {
    static let windowsControlSize = CGFloat(16)
    static let windowsControlSpacing = CGFloat(8)
    static let noOpenWindowToolTip = NSLocalizedString("App is running but has no open window", comment: "")
    var window_: Window?
    var thumbnail = NSImageView()
    var appIcon = NSImageView()
    var label = ThumbnailTitleView(Appearance.fontHeight)
    var fullscreenIcon = ThumbnailFontIconView(symbol: .circledPlusSign, tooltip: NSLocalizedString("Window is fullscreen", comment: ""))
    var minimizedIcon = ThumbnailFontIconView(symbol: .circledMinusSign, tooltip: NSLocalizedString("Window is minimized", comment: ""))
    var hiddenIcon = ThumbnailFontIconView(symbol: .circledSlashSign, tooltip: NSLocalizedString("App is hidden", comment: ""))
    var spaceIcon = ThumbnailFontIconView(symbol: .circledNumber0)
    var dockLabelIcon = ThumbnailFilledFontIconView(ThumbnailFontIconView(symbol: .filledCircledNumber0, size: dockLabelLabelSize(),
            color: NSColor(srgbRed: 1, green: 0.30, blue: 0.25, alpha: 1), shadow: nil), backgroundColor: NSColor.white, size: dockLabelLabelSize())
    var quitIcon = TrafficLightButton(.quit, NSLocalizedString("Quit app", comment: ""), windowsControlSize)
    var closeIcon = TrafficLightButton(.close, NSLocalizedString("Close window", comment: ""), windowsControlSize)
    var minimizeIcon = TrafficLightButton(.miniaturize, NSLocalizedString("Minimize/Deminimize window", comment: ""), windowsControlSize)
    var maximizeIcon = TrafficLightButton(.fullscreen, NSLocalizedString("Fullscreen/Defullscreen window", comment: ""), windowsControlSize)
    var windowlessAppIndicator = WindowlessAppIndicator(tooltip: ThumbnailView.noOpenWindowToolTip)

    var hStackView: NSStackView!
    var vStackView: NSStackView!
    var mouseUpCallback: (() -> Void)!
    var mouseMovedCallback: (() -> Void)!
    var dragAndDropTimer: Timer?
    var indexInRecycledViews: Int!
    var isShowingWindowControls = false
    var windowlessIcon = NSImageView()

    var isFirstInRow = false
    var isLastInRow = false
    var indexInRow = 0
    var numberOfViewsInRow = 0

    var windowControlIcons: [TrafficLightButton]!

    // for VoiceOver cursor
    override var canBecomeKeyView: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func isAccessibilityElement() -> Bool { true }

    convenience init() {
        self.init(frame: .zero)
        setupView()
        observeDragAndDrop()
    }

    private func setupView() {
        orientation = .vertical
        let shadow = ThumbnailView.makeShadow(Appearance.imageShadowColor)
        thumbnail.shadow = shadow
        windowlessIcon.toolTip = ThumbnailView.noOpenWindowToolTip
        windowlessIcon.shadow = shadow
        appIcon.shadow = shadow
        windowControlIcons = [quitIcon, closeIcon, minimizeIcon, maximizeIcon]

        addViews()
        addWindowControls()
        addDockLabelIcon()
        addWindowlessIndicator()
        setAccessibilityChildren([])
    }

    private func addViews() {
        vStackView = NSStackView()
        vStackView.orientation = .vertical
        vStackView.wantsLayer = true
        vStackView.layer!.backgroundColor = .clear
        vStackView.layer!.borderColor = .clear
        vStackView.layer!.cornerRadius = Appearance.cellCornerRadius
        vStackView.layer!.borderWidth = CGFloat(1)
        vStackView.edgeInsets = NSEdgeInsets(top: Appearance.edgeInsetsSize, left: Appearance.edgeInsetsSize,
                bottom: Appearance.edgeInsetsSize, right: Appearance.edgeInsetsSize)

        if Preferences.appearanceStyle == .appIcons {
            // The label is outside and below the selected icon in AppIcons style
            hStackView = NSStackView(views: [appIcon])
            vStackView.setViews([hStackView], in: .leading)
            label.alignment = .center
            setViews([vStackView], in: .leading)
            addSubview(label)
            label.isHidden = true

            vStackView.translatesAutoresizingMaskIntoConstraints = false
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                vStackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                vStackView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                vStackView.topAnchor.constraint(equalTo: self.topAnchor),

                label.topAnchor.constraint(equalTo: vStackView.bottomAnchor, constant: Appearance.intraCellPadding),
                self.bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: Appearance.intraCellPadding)
            ])
        } else {
            hStackView = NSStackView(views: [appIcon, label, hiddenIcon, fullscreenIcon, minimizedIcon, spaceIcon])
            vStackView.setViews([hStackView, thumbnail, windowlessIcon], in: .leading)
            setViews([vStackView], in: .leading)
        }
    }

    private func addDockLabelIcon() {
        appIcon.addSubview(dockLabelIcon, positioned: .above, relativeTo: nil)
    }

    private func addWindowlessIndicator() {
        addSubview(windowlessAppIndicator, positioned: .above, relativeTo: nil)
    }

    private func addWindowControls() {
        thumbnail.addSubview(quitIcon, positioned: .above, relativeTo: nil)
        thumbnail.addSubview(closeIcon, positioned: .above, relativeTo: nil)
        thumbnail.addSubview(minimizeIcon, positioned: .above, relativeTo: nil)
        thumbnail.addSubview(maximizeIcon, positioned: .above, relativeTo: nil)
        windowControlIcons.forEach { $0.isHidden = true }
    }

    func showOrHideWindowControls(_ shouldShowWindowControls: Bool) {
        let shouldShow = shouldShowWindowControls && !Preferences.hideColoredCircles && !Appearance.hideThumbnails
        if isShowingWindowControls != shouldShow {
            isShowingWindowControls = shouldShow
            let target = (window_?.isWindowlessApp ?? true) ? windowlessIcon : thumbnail
            target.addSubview(quitIcon, positioned: .above, relativeTo: nil)
            var xOffset = CGFloat(3)
            var yOffset = CGFloat(2 + ThumbnailView.windowsControlSize)
            windowControlIcons.forEach { icon in
                icon.isHidden = !shouldShow ||
                    (icon.type == .quit && !(window_?.application.canBeQuit() ?? true)) ||
                    (icon.type == .close && !(window_?.canBeClosed() ?? true)) ||
                    ((icon.type == .miniaturize || icon.type == .fullscreen) && !(window_?.canBeMinDeminOrFullscreened() ?? true))
                if !icon.isHidden {
                    icon.setFrameOrigin(NSPoint(
                        x: xOffset,
                        y: target.frame.height - yOffset))
                    xOffset += ThumbnailView.windowsControlSize + ThumbnailView.windowsControlSpacing
                    if xOffset + ThumbnailView.windowsControlSize > target.frame.width {
                        xOffset = 3
                        yOffset += ThumbnailView.windowsControlSize + ThumbnailView.windowsControlSpacing
                    }
                }
                // Force the icons to redraw, or after clicking the fullscreen button,
                // it will still appear to be in fullscreen mode.
                icon.display()
            }
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
        vStackView?.layer!.backgroundColor = getBackgroundColor(isFocused: isFocused, isHovered: isHovered).cgColor
    }

    private func setBorder(isFocused: Bool, isHovered: Bool) {
        if isFocused {
            vStackView?.layer!.borderColor = Appearance.highlightFocusedBorderColor.cgColor
            vStackView?.layer!.borderWidth = Appearance.highlightBorderWidth
        } else if isHovered {
            vStackView?.layer!.borderColor = Appearance.highlightHoveredBorderColor.cgColor
            vStackView?.layer!.borderWidth = Appearance.highlightBorderWidth
        } else {
            vStackView?.layer!.borderColor = NSColor.clear.cgColor
            vStackView?.layer!.borderWidth = 0
        }
    }

    private func setShadow(isFocused: Bool, isHovered: Bool) {
        if (isFocused || isHovered) && Appearance.highlightBorderShadowColor != .clear {
            vStackView?.layer!.shadowColor = Appearance.highlightBorderShadowColor.cgColor
            vStackView?.layer!.shadowOpacity = 0.25
            vStackView?.layer!.shadowOffset = .zero
            vStackView?.layer!.shadowRadius = 1
        }
    }

    func drawHighlight() {
        let isFocused = indexInRecycledViews == Windows.focusedWindowIndex
        let isHovered = indexInRecycledViews == Windows.hoveredWindowIndex
        setBackground(isFocused: isFocused, isHovered: isHovered)
        setBorder(isFocused: isFocused, isHovered: isHovered)
        setShadow(isFocused: isFocused, isHovered: isHovered)
        if Preferences.appearanceStyle == .appIcons {
            label.isHidden = !(isFocused || isHovered)
            updateAppIconsLabel(isFocused: isFocused, isHovered: isHovered)
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
            if let hoveredView = hoveredView {
                updateAppIconsLabelFrame(hoveredView)
            }
        }
    }

    func getMaxAllowedLabelWidth(_ view: ThumbnailView) -> CGFloat {
        let viewWidth = view.frame.width
        let maxAllowedWidth = min(viewWidth * 2, ThumbnailsView.thumbnailsWith)

        let availableLeftWidth = view.isFirstInRow ? 0 : CGFloat(view.indexInRow) * viewWidth
        let availableRightWidth = view.isLastInRow ? 0 : CGFloat(view.numberOfViewsInRow - 1 - view.indexInRow) * viewWidth
        let totalWidth = availableLeftWidth + availableRightWidth + viewWidth
        let maxLabelWidth = min(totalWidth, maxAllowedWidth)
        return maxLabelWidth
    }

    private func updateAppIconsLabelFrame(_ view: ThumbnailView) {
        let viewWidth = view.frame.width
        let labelWidth = view.label.getTitleWidth()
        let maxAllowedLabelWidth = getMaxAllowedLabelWidth(view)
        let effectiveLabelWidth = max(min(labelWidth, maxAllowedLabelWidth), viewWidth)

        var leftOffset = CGFloat(0)
        var rightOffset = CGFloat(0)

        if view.isFirstInRow && view.isLastInRow {
            leftOffset = 0
            rightOffset = 0
        } else if view.isFirstInRow {
            rightOffset = max(0, effectiveLabelWidth - viewWidth)
        } else if view.isLastInRow {
            leftOffset = max(0, effectiveLabelWidth - viewWidth)
        } else if !view.isFirstInRow && !view.isLastInRow {
            let halfNeededOffset = max(0, (effectiveLabelWidth - viewWidth) / 2)
            let availableLeftWidth = view.isFirstInRow ? 0 : CGFloat(view.indexInRow) * viewWidth
            let availableRightWidth = view.isLastInRow ? 0 : CGFloat(view.numberOfViewsInRow - 1 - view.indexInRow) * viewWidth

            if availableLeftWidth >= halfNeededOffset && availableRightWidth >= halfNeededOffset {
                leftOffset = halfNeededOffset
                rightOffset = halfNeededOffset
            } else if availableLeftWidth <= halfNeededOffset && availableRightWidth <= halfNeededOffset {
                leftOffset = availableLeftWidth
                rightOffset = availableRightWidth
            } else if availableRightWidth <= halfNeededOffset {
                rightOffset = availableRightWidth
                leftOffset = min(effectiveLabelWidth - viewWidth - rightOffset, availableLeftWidth)
            } else if availableLeftWidth <= halfNeededOffset {
                leftOffset = availableLeftWidth
                rightOffset = min(effectiveLabelWidth - viewWidth - leftOffset, availableRightWidth)
            }
        }

        // Bottom aligned with space
        let xPosition = -leftOffset
        let yPosition = Appearance.intraCellPadding
        let height = ThumbnailTitleView.maxHeight()
        view.label.frame = NSRect(x: xPosition, y: yPosition, width: effectiveLabelWidth, height: height)
        assignIfDifferent(&view.label.textContainer!.size.width, effectiveLabelWidth)
    }

    func updateRecycledCellWithNewContent(_ element: Window, _ index: Int, _ newHeight: CGFloat, _ screen: NSScreen) {
        window_ = element
        assignIfDifferent(&thumbnail.isHidden, Appearance.hideThumbnails || element.isWindowlessApp)
        if !thumbnail.isHidden {
            thumbnail.image = element.thumbnail
            if let image = thumbnail.image {
                image.size = element.thumbnailFullSize!
            } else {
                thumbnail.image = element.icon?.copy() as? NSImage
                thumbnail.image?.size = NSSize(width: 1024, height: 1024)
            }
            let thumbnailSize = ThumbnailView.thumbnailSize(thumbnail.image, screen)
            thumbnail.image?.size = thumbnailSize
            thumbnail.frame.size = thumbnailSize
            // for Accessibility > "speak items under the pointer"
            thumbnail.setAccessibilityLabel(element.title)
        }
        assignIfDifferent(&vStackView.spacing, Appearance.hideThumbnails ? 0 : Appearance.intraCellPadding)
        assignIfDifferent(&spacing, Appearance.intraCellPadding)
        assignIfDifferent(&hStackView.spacing, Appearance.fontHeight == 0 ? 0 : Appearance.intraCellPadding)
        let title = getAppOrAndWindowTitle()
        let appIconChanged = appIcon.image != element.icon
        if appIconChanged {
            appIcon.image = element.icon
            let appIconSize = ThumbnailView.iconSize(screen)
            appIcon.image?.size = appIconSize
            appIcon.frame.size = appIconSize
            appIcon.setAccessibilityLabel(title)
        }
        let labelChanged = label.string != title
        if labelChanged {
            label.string = title
            // workaround: setting string on NSTextView changes the font (most likely a Cocoa bug)
            label.font = Appearance.font
            setAccessibilityLabel(title)
        }
        assignIfDifferent(&hiddenIcon.isHidden, !element.isHidden || Preferences.hideStatusIcons)
        assignIfDifferent(&fullscreenIcon.isHidden, !element.isFullscreen || Preferences.hideStatusIcons)
        assignIfDifferent(&minimizedIcon.isHidden, !element.isMinimized || Preferences.hideStatusIcons)
        assignIfDifferent(&spaceIcon.isHidden, element.isWindowlessApp || Spaces.isSingleSpace() || Preferences.hideSpaceNumberLabels)
        if !spaceIcon.isHidden {
            if element.spaceIndex > 30 || element.isOnAllSpaces {
                spaceIcon.setStar()
                spaceIcon.toolTip = NSLocalizedString("Window is on every Space", comment: "")
            } else {
                spaceIcon.setNumber(element.spaceIndex, false)
                spaceIcon.toolTip = String(format: NSLocalizedString("Window is on Space %d", comment: ""), element.spaceIndex)
            }
        }
        let dockLabelChanged = updateDockLabelIcon(element.dockLabel)
        if appIconChanged || dockLabelChanged {
            setAccessibilityHelp(getAccessibilityHelp(element.application.runningApplication.localizedName, element.dockLabel))
        }
        label.toolTip = label.textStorage!.size().width >= label.textContainer!.size.width ? label.string : nil
        assignIfDifferent(&windowlessIcon.isHidden, !element.isWindowlessApp || Appearance.hideThumbnails)
        if element.isWindowlessApp {
            windowlessIcon.image = appIcon.image!.copy() as? NSImage
            windowlessIcon.image?.size = NSSize(width: 1024, height: 1024)
            let windowlessIconSize = ThumbnailView.thumbnailSize(windowlessIcon.image, screen)
            windowlessIcon.image!.size = windowlessIconSize
            windowlessIcon.frame.size = windowlessIconSize
            windowlessIcon.needsDisplay = true
        }
        setFrameWidthHeight(element, screen, newHeight)
        setLabelWidth()
        updateWindowlessIndicator(element, screen)
        self.mouseUpCallback = { () -> Void in App.app.focusSelectedWindow(element) }
        self.mouseMovedCallback = { () -> Void in Windows.updateFocusedAndHoveredWindowIndex(index, true) }
        windowControlIcons.forEach { $0.window_ = element }
        showOrHideWindowControls(false)
        // force a display to avoid flickering; see https://github.com/lwouis/alt-tab-macos/issues/197
        // quirk: display() should be called last as it resets thumbnail.frame.size somehow
        if labelChanged {
            label.display()
        }
    }

    func getAppOrAndWindowTitle() -> String {
        let appName = window_?.application.runningApplication.localizedName
        let windowTitle = window_?.title

        if Preferences.appearanceStyle != .thumbnails {
            if Preferences.onlyShowApplications() || Preferences.showTitles == .appName {
                return appName ?? ""
            } else if Preferences.showTitles == .appNameAndWindowTitle {
                return [appName, windowTitle].compactMap{ $0 }.joined(separator: " - ")
            }
        }
        return windowTitle ?? ""
    }

    func setFrameWidthHeight(_ element: Window, _ screen: NSScreen, _ newHeight: CGFloat) {
        // Retrieves the minimum width for the screen.
        let widthMin = ThumbnailView.minThumbnailWidth(screen)
        let leftRightEdgeInsetsSize = ThumbnailView.getLeftRightEdgeInsetsSize()
        let topBottomEdgeInsetsSize = ThumbnailView.getTopBottomEdgeInsetsSize()
        var width = CGFloat(0)
        if Preferences.appearanceStyle == .thumbnails {
            // Preferred to the width of the image, and the minimum width may be set to be large.
            if element.isWindowlessApp {
                width = (windowlessIcon.frame.size.width + leftRightEdgeInsetsSize).rounded()
            } else {
                width = (thumbnail.frame.size.width + leftRightEdgeInsetsSize).rounded()
            }
        } else {
            let contentWidth = max(hStackView.frame.size.width, Appearance.iconSize)
            let frameWidth = contentWidth + leftRightEdgeInsetsSize
            width = max(frameWidth, widthMin).rounded()
        }
        assignIfDifferent(&frame.size.width, width)
        assignIfDifferent(&frame.size.height, newHeight)

        if logger.isDebugEnabled() {
            logger.d(window_?.title)
            printSubviewFrames(of: self)
        }
    }

    func printSubviewFrames(of view: NSView, indent: String = "", isLast: Bool = true) {
        let indentSymbol = isLast ? "└── " : "├── "
        logger.d("\(indent)\(indentSymbol)View: \(type(of: view)), Frame: \(view.frame)")
        let newIndent = indent + (isLast ? "    " : "│   ")

        for (index, subview) in view.subviews.enumerated() {
            let isLastSubview = index == view.subviews.count - 1
            printSubviewFrames(of: subview, indent: newIndent, isLast: isLastSubview)
        }
    }

    func setLabelWidth() {
        if Preferences.appearanceStyle == .appIcons {
            assignIfDifferent(&label.textContainer!.size.width, frame.width)
        } else {
            let visibleCount = [fullscreenIcon, minimizedIcon, hiddenIcon, spaceIcon].filter { !$0.isHidden }.count
            let fontIconWidth = CGFloat(visibleCount) * (Appearance.fontHeight + Appearance.intraCellPadding)
            let labelWidth = max(vStackView.frame.width, frame.width)
                    - Appearance.edgeInsetsSize * 2
                    - Appearance.iconSize
                    - Appearance.intraCellPadding - fontIconWidth
            assignIfDifferent(&label.textContainer!.size.width, labelWidth)
        }
    }

    func updateWindowlessIndicator(_ element: Window, _ screen: NSScreen) {
        assignIfDifferent(&windowlessAppIndicator.isHidden, !element.isWindowlessApp)
        if element.isWindowlessApp {
            var xOffset = CGFloat(0)
            var yOffset = CGFloat(0)
            if Preferences.appearanceStyle == .thumbnails {
                xOffset = (frame.size.width - windowlessAppIndicator.frame.size.width) / 2
                yOffset = Appearance.edgeInsetsSize
            } else if Preferences.appearanceStyle == .appIcons {
                xOffset = (frame.size.width - windowlessAppIndicator.frame.size.width) / 2
                yOffset = ThumbnailFontIconView.maxHeight() + 2 * Appearance.intraCellPadding + Appearance.edgeInsetsSize / 2
            } else if Preferences.appearanceStyle == .titles {
                let iconSize = ThumbnailView.iconSize(screen)
                xOffset = Appearance.edgeInsetsSize + (iconSize.width - windowlessAppIndicator.frame.size.width) / 2
                yOffset = Appearance.edgeInsetsSize / 2
            }
            assignIfDifferent(&windowlessAppIndicator.frame.origin.x, xOffset)
            assignIfDifferent(&windowlessAppIndicator.frame.origin.y, yOffset)
        }
    }

    @discardableResult
    func updateDockLabelIcon(_ dockLabel: String?) -> Bool {
        assignIfDifferent(&dockLabelIcon.isHidden, dockLabel == nil || Preferences.hideAppBadges || Appearance.iconSize == 0)
        if !dockLabelIcon.isHidden, let dockLabel = dockLabel {
            let view = dockLabelIcon.subviews[1] as! ThumbnailFontIconView
            let dockLabelInt = Int(dockLabel)
            if dockLabelInt == nil || dockLabelInt! > 30 {
                view.setFilledStar()
            } else {
                view.setNumber(dockLabelInt!, true)
            }
            let badgeOffset = Preferences.appearanceSize == .small ? CGFloat(1) : CGFloat(0)
            let iconSize = ThumbnailView.iconSize(NSScreen.preferred())
            dockLabelIcon.setFrameOrigin(NSPoint(
                    x: iconSize.width - (dockLabelIcon.fittingSize.width / 2) - (iconSize.width / 7) - badgeOffset,
                    y: iconSize.height - (dockLabelIcon.fittingSize.height / 2) - (iconSize.height / 5) - badgeOffset))
            view.setAccessibilityLabel(getAccessibilityTextForBadge(dockLabel))
            return true
        }
        return false
    }

    func getAccessibilityHelp(_ appName: String?, _ dockLabel: String?) -> String {
        [appName, dockLabel.map { getAccessibilityTextForBadge($0) }]
                .compactMap { $0 }
                .joined(separator: " - ")
    }

    func getAccessibilityTextForBadge(_ dockLabel: String) -> String {
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

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        mouseMovedCallback()
        return .link
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragAndDropTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false, block: { _ in
            self.mouseUpCallback()
        })
        dragAndDropTimer?.tolerance = 0.2
        return .link
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dragAndDropTimer?.invalidate()
        dragAndDropTimer = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dragAndDropTimer?.invalidate()
        dragAndDropTimer = nil
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as! [URL]
        let appUrl = window_!.application.runningApplication.bundleURL!
        let open = try? NSWorkspace.shared.open(urls, withApplicationAt: appUrl, options: [], configuration: [:])
        App.app.hideUi()
        return open != nil
    }

    func mouseMoved() {
        showOrHideWindowControls(true)
        mouseMovedCallback()
    }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount >= 1 {
            mouseUpCallback()
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        // middle-click
        if event.buttonNumber == 2 {
            window_?.close()
        }
    }

    static func dockLabelLabelSize() -> CGFloat {
        return (ThumbnailView.iconSize(NSScreen.preferred()).width * 0.43).rounded()
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

    static func maxThumbnailWidth(_ screen: NSScreen) -> CGFloat {
        return ThumbnailsPanel.maxThumbnailsWidth(screen) * Appearance.windowMaxWidthInRow - Appearance.interCellPadding * 2
    }

    static func minThumbnailWidth(_ screen: NSScreen) -> CGFloat {
        return ThumbnailsPanel.maxThumbnailsWidth(screen) * Appearance.windowMinWidthInRow - Appearance.interCellPadding * 2
    }

    /// The maximum height that a thumbnail can be drawn
    ///
    /// maxThumbnailsHeight = maxThumbnailHeight * rowCount + interCellPadding * (rowCount - 1)
    ///
    /// maxThumbnailHeight = (maxThumbnailsHeight - interCellPadding * (rowCount - 1)) / rowCount
    ///
    /// - Parameter screen:
    /// - Returns:
    static func maxThumbnailHeight(_ screen: NSScreen) -> CGFloat {
        return (ThumbnailsPanel.maxThumbnailsHeight(screen) - Appearance.interCellPadding) / Appearance.rowsCount - Appearance.interCellPadding
    }

    static func thumbnailSize(_ image: NSImage?, _ screen: NSScreen) -> NSSize {
        guard let image = image else { return NSSize(width: 0, height: 0) }
        let thumbnailHeightMax = ThumbnailView.maxThumbnailHeight(screen)
                - Appearance.edgeInsetsSize * 2
                - Appearance.intraCellPadding
                - Appearance.iconSize
        let thumbnailWidthMax = ThumbnailView.maxThumbnailWidth(screen)
                - Appearance.edgeInsetsSize * 2
        let thumbnailHeight = min(image.size.height, thumbnailHeightMax)
        let thumbnailWidth = min(image.size.width, thumbnailWidthMax)
        let imageRatio = image.size.width / image.size.height
        let thumbnailRatio = thumbnailWidth / thumbnailHeight
        var width: CGFloat
        var height: CGFloat
        if thumbnailRatio > imageRatio {
            // Keep the height and reduce the width
            width = image.size.width * thumbnailHeight / image.size.height
            height = thumbnailHeight
        } else if thumbnailRatio < imageRatio {
            // Keep the width and reduce the height
            width = thumbnailWidth
            height = image.size.height * thumbnailWidth / image.size.width
        } else {
            // Enlarge the height to the maximum height and enlarge the width
            width = thumbnailHeightMax / image.size.height * image.size.width
            height = thumbnailHeightMax
        }
        return NSSize(width: width.rounded(), height: height.rounded())
    }

    static func iconSize(_ screen: NSScreen) -> NSSize {
        if Preferences.appearanceStyle == .appIcons {
            let widthMin = ThumbnailView.minThumbnailWidth(screen)
            let contentWidth = Appearance.iconSize
            let leftRightEdgeInsetsSize = ThumbnailView.getTopBottomEdgeInsetsSize()
            let frameWidth = contentWidth + leftRightEdgeInsetsSize
            let width = max(frameWidth, widthMin).rounded()
            if widthMin > frameWidth {
                let iconSize = width - leftRightEdgeInsetsSize
                return NSSize(width: iconSize, height: iconSize)
            }
        }
        return NSSize(width: Appearance.iconSize, height: Appearance.iconSize)
    }

    static func height(_ screen: NSScreen) -> CGFloat {
        let topBottomEdgeInsetsSize = ThumbnailView.getTopBottomEdgeInsetsSize()
        if Preferences.appearanceStyle == .titles {
            return max(ThumbnailView.iconSize(screen).height, ThumbnailTitleView.maxHeight()) + topBottomEdgeInsetsSize
        } else if Preferences.appearanceStyle == .appIcons {
            return ThumbnailView.iconSize(screen).height
                    + topBottomEdgeInsetsSize
                    + Appearance.intraCellPadding
                    + ThumbnailTitleView.maxHeight()
                    + Appearance.intraCellPadding
        }
        return ThumbnailView.maxThumbnailHeight(screen).rounded(.down)
    }

    static func getLeftRightEdgeInsetsSize() -> CGFloat {
        return Appearance.edgeInsetsSize * 2
    }

    static func getTopBottomEdgeInsetsSize() -> CGFloat {
        return Appearance.edgeInsetsSize * 2
    }
}
