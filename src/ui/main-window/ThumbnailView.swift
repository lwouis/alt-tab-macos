import Cocoa

class ThumbnailView: NSStackView {
    static let windowsControlSize = CGFloat(16)
    static let windowsControlSpacing = CGFloat(8)
    var window_: Window?
    var thumbnail = NSImageView()
    var appIcon = NSImageView()
    var label = ThumbnailTitleView(Preferences.fontHeight)
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

    var hStackView: NSStackView!
    var vStackView: NSStackView!
    var vBorderStackView: NSStackView!
    var labelStackView: NSStackView!
    var mouseUpCallback: (() -> Void)!
    var mouseMovedCallback: (() -> Void)!
    var dragAndDropTimer: Timer?
    var indexInRecycledViews: Int!
    var shouldShowWindowControls = false
    var isShowingWindowControls = false
    var windowlessIcon = NSImageView()

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
        let shadow = ThumbnailView.makeShadow(Preferences.appearanceThemeParameters.imageShadowColor)
        thumbnail.shadow = shadow
        windowlessIcon.toolTip = NSLocalizedString("App is running but has no open window", comment: "")
        windowlessIcon.shadow = shadow
        appIcon.shadow = shadow

        addViews()
        addWindowControls()
        addDockLabelIcon()
        setAccessibilityChildren([])
    }

    private func addViews() {
        vBorderStackView = NSStackView()
        vBorderStackView.wantsLayer = true
        vBorderStackView.layer!.backgroundColor = .clear
        vBorderStackView.layer!.borderColor = .clear
        vBorderStackView.layer!.cornerRadius = Preferences.cellBorderCornerRadius
        vBorderStackView.layer!.borderWidth = CGFloat(1)
        let borderWidth = Preferences.appearanceThemeParameters.highlightBorderWidth
        vBorderStackView.edgeInsets = NSEdgeInsets(top: borderWidth, left: borderWidth, bottom: borderWidth, right: borderWidth)

        vStackView = NSStackView()
        vStackView.orientation = .vertical
        vStackView.wantsLayer = true
        vStackView.layer!.backgroundColor = .clear
        vStackView.layer!.borderColor = .clear
        vStackView.layer!.cornerRadius = Preferences.cellCornerRadius
        vStackView.layer!.borderWidth = CGFloat(1)
        vStackView.edgeInsets = NSEdgeInsets(top: Preferences.edgeInsetsSize, left: Preferences.edgeInsetsSize,
                bottom: Preferences.edgeInsetsSize, right: Preferences.edgeInsetsSize)
        if Preferences.appearanceStyle == .appIcons {
            // The label is outside and below the selected icon in AppIcons style
            hStackView = NSStackView(views: [appIcon])
            vStackView.setViews([hStackView], in: .leading)
            vBorderStackView.setViews([vStackView], in: .leading)
            label.alignment = .center
            label.isHidden = true
            setViews([vBorderStackView, label], in: .leading)
        } else {
            hStackView = NSStackView(views: [appIcon, label, hiddenIcon, fullscreenIcon, minimizedIcon, spaceIcon])
            vStackView.setViews([hStackView, thumbnail, windowlessIcon], in: .leading)
            vBorderStackView.setViews([vStackView], in: .leading)
            setViews([vBorderStackView], in: .leading)
        }
    }

    private func addDockLabelIcon() {
        appIcon.addSubview(dockLabelIcon, positioned: .above, relativeTo: nil)
    }

    private func addWindowControls() {
        thumbnail.addSubview(quitIcon, positioned: .above, relativeTo: nil)
        thumbnail.addSubview(closeIcon, positioned: .above, relativeTo: nil)
        thumbnail.addSubview(minimizeIcon, positioned: .above, relativeTo: nil)
        thumbnail.addSubview(maximizeIcon, positioned: .above, relativeTo: nil)
        [quitIcon, closeIcon, minimizeIcon, maximizeIcon].forEach { $0.isHidden = true }
    }

    func showOrHideWindowControls(_ shouldShowWindowControls: Bool) {
        let shouldShow = shouldShowWindowControls && !Preferences.hideColoredCircles && !Preferences.hideThumbnails
        if isShowingWindowControls != shouldShow {
            isShowingWindowControls = shouldShow
            let target = (window_?.isWindowlessApp ?? true) ? windowlessIcon : thumbnail
            target.addSubview(quitIcon, positioned: .above, relativeTo: nil)
            var xOffset = CGFloat(3)
            var yOffset = CGFloat(2 + ThumbnailView.windowsControlSize)
            [quitIcon, closeIcon, minimizeIcon, maximizeIcon].forEach { icon in
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
            return Preferences.appearanceThemeParameters.highlightFocusedBackgroundColor
        }
        if isHovered {
            return Preferences.appearanceThemeParameters.highlightHoveredBackgroundColor
        }
        return NSColor.clear
    }

    private func setBorder(isFocused: Bool, isHovered: Bool) {
        if isFocused {
            vStackView?.layer!.borderColor = Preferences.appearanceThemeParameters.highlightInnerFocusedBorderColor.cgColor
            vStackView?.layer!.borderWidth = Preferences.appearanceThemeParameters.highlightInnerBorderWidth
            vBorderStackView?.layer!.borderColor = Preferences.appearanceThemeParameters.highlightFocusedBorderColor.cgColor
            vBorderStackView?.layer!.borderWidth = Preferences.appearanceThemeParameters.highlightBorderWidth
        } else if isHovered {
            vStackView?.layer!.borderColor = Preferences.appearanceThemeParameters.highlightInnerHoveredBorderColor.cgColor
            vStackView?.layer!.borderWidth = Preferences.appearanceThemeParameters.highlightInnerBorderWidth
            vBorderStackView?.layer!.borderColor = Preferences.appearanceThemeParameters.highlightHoveredBorderColor.cgColor
            vBorderStackView?.layer!.borderWidth = Preferences.appearanceThemeParameters.highlightBorderWidth
        } else {
            vStackView?.layer!.borderColor = NSColor.clear.cgColor
            vBorderStackView?.layer!.borderColor = NSColor.clear.cgColor
            vStackView?.layer!.borderWidth = 0
        }
    }

    private func setShadow(isFocused: Bool, isHovered: Bool) {
        if (isFocused || isHovered) && Preferences.appearanceThemeParameters.highlightBorderShadowColor != .clear {
            vBorderStackView?.layer!.shadowColor = Preferences.appearanceThemeParameters.highlightBorderShadowColor.cgColor
            vBorderStackView?.layer!.shadowOpacity = 0.25
            vBorderStackView?.layer!.shadowOffset = .zero
            vBorderStackView?.layer!.shadowRadius = 1
        }
    }

    func drawHighlight(_ i: Int) {
        let isFocused = indexInRecycledViews == Windows.focusedWindowIndex
        let isHovered = indexInRecycledViews == Windows.hoveredWindowIndex
        vStackView?.layer!.backgroundColor = getBackgroundColor(isFocused: isFocused, isHovered: isHovered).cgColor
        setBorder(isFocused: isFocused, isHovered: isHovered)
        setShadow(isFocused: isFocused, isHovered: isHovered)
        if Preferences.appearanceStyle == .appIcons {
            label.isHidden = !(isFocused || isHovered)
        }
    }

    func updateRecycledCellWithNewContent(_ element: Window, _ index: Int, _ newHeight: CGFloat, _ screen: NSScreen) {
        window_ = element
        assignIfDifferent(&thumbnail.isHidden, Preferences.hideThumbnails || element.isWindowlessApp)
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
        assignIfDifferent(&vStackView.spacing, Preferences.hideThumbnails ? 0 : Preferences.intraCellPadding)
        assignIfDifferent(&spacing, Preferences.intraCellPadding)
        assignIfDifferent(&hStackView.spacing, Preferences.fontHeight == 0 ? 0 : Preferences.intraCellPadding)
        let title = getAppOrAndWindowTitle()
        let appIconChanged = appIcon.image != element.icon || appIcon.toolTip != title
        if appIconChanged {
            appIcon.image = element.icon
            let appIconSize = ThumbnailView.iconSize(screen)
            appIcon.image?.size = appIconSize
            appIcon.frame.size = appIconSize
            appIcon.setAccessibilityLabel(title)
            appIcon.toolTip = title
        }
        let labelChanged = label.string != title
        if labelChanged {
            label.string = title
            // workaround: setting string on NSTextView changes the font (most likely a Cocoa bug)
            label.font = Preferences.font
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
        assignIfDifferent(&windowlessIcon.isHidden, !element.isWindowlessApp || Preferences.hideThumbnails)
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
        self.mouseUpCallback = { () -> Void in App.app.focusSelectedWindow(element) }
        self.mouseMovedCallback = { () -> Void in Windows.updateFocusedAndHoveredWindowIndex(index, true) }
        [quitIcon, closeIcon, minimizeIcon, maximizeIcon].forEach { $0.window_ = element }
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
        var width = CGFloat(0)
        if Preferences.appearanceStyle == .thumbnails {
            // Preferred to the width of the image, and the minimum width may be set to be large.
            if element.isWindowlessApp {
                width = (windowlessIcon.frame.size.width + leftRightEdgeInsetsSize).rounded()
            } else {
                width = (thumbnail.frame.size.width + leftRightEdgeInsetsSize).rounded()
            }
            assignIfDifferent(&vStackView.frame.size.width, width - leftRightEdgeInsetsSize)
            assignIfDifferent(&vStackView.frame.size.height, newHeight - leftRightEdgeInsetsSize)
        } else {
            let contentWidth = max(hStackView.frame.size.width, Preferences.iconSize)
            let frameWidth = contentWidth + leftRightEdgeInsetsSize
            width = max(frameWidth, widthMin).rounded()
        }
        assignIfDifferent(&frame.size.width, width)
        assignIfDifferent(&frame.size.height, newHeight)
    }

    func setLabelWidth() {
        if Preferences.appearanceStyle == .appIcons {
            assignIfDifferent(&label.textContainer!.size.width, frame.width)
        } else {
            let visibleCount = [fullscreenIcon, minimizedIcon, hiddenIcon, spaceIcon].filter { !$0.isHidden }.count
            let fontIconWidth = CGFloat(visibleCount) * (Preferences.fontHeight + Preferences.intraCellPadding)
            let labelWidth = max(vBorderStackView.frame.width, frame.width)
                    - Preferences.appearanceThemeParameters.highlightBorderWidth * 2
                    - Preferences.edgeInsetsSize * 2
                    - Preferences.iconSize
                    - Preferences.intraCellPadding - fontIconWidth
            assignIfDifferent(&label.textContainer!.size.width, labelWidth)
        }
    }

    @discardableResult
    func updateDockLabelIcon(_ dockLabel: String?) -> Bool {
        assignIfDifferent(&dockLabelIcon.isHidden, dockLabel == nil || Preferences.hideAppBadges || Preferences.iconSize == 0)
        if !dockLabelIcon.isHidden, let dockLabel = dockLabel {
            let view = dockLabelIcon.subviews[1] as! ThumbnailFontIconView
            let dockLabelInt = Int(dockLabel)
            if dockLabelInt == nil || dockLabelInt! > 30 {
                view.setFilledStar()
            } else {
                view.setNumber(dockLabelInt!, true)
            }
            let badgeOffsetOnSmallSize = Preferences.appearanceSize == .small ? CGFloat(1) : CGFloat(0)
            dockLabelIcon.setFrameOrigin(NSPoint(
                x: appIcon.frame.maxX - (dockLabelIcon.fittingSize.width / 2) - (appIcon.frame.width / 7) - badgeOffsetOnSmallSize,
                y: appIcon.frame.maxY - (dockLabelIcon.fittingSize.height / 2) - (appIcon.frame.height / 5) - badgeOffsetOnSmallSize))
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
        return (max(Double(Preferences.defaultValues["iconSize"]!)!, Preferences.iconSize) * 0.43).rounded()
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
        return ThumbnailsPanel.maxThumbnailsWidth(screen) * Preferences.windowMaxWidthInRow - Preferences.interCellPadding * 2
    }

    static func minThumbnailWidth(_ screen: NSScreen) -> CGFloat {
        return ThumbnailsPanel.maxThumbnailsWidth(screen) * Preferences.windowMinWidthInRow - Preferences.interCellPadding * 2
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
        return (ThumbnailsPanel.maxThumbnailsHeight(screen) - Preferences.interCellPadding) / Preferences.rowsCount - Preferences.interCellPadding
    }

    static func thumbnailSize(_ image: NSImage?, _ screen: NSScreen) -> NSSize {
        guard let image = image else { return NSSize(width: 0, height: 0) }
        let thumbnailHeightMax = ThumbnailView.maxThumbnailHeight(screen)
                - Preferences.appearanceThemeParameters.highlightBorderWidth * 2
                - Preferences.edgeInsetsSize * 2
                - Preferences.intraCellPadding
                - Preferences.iconSize
        let thumbnailWidthMax = ThumbnailView.maxThumbnailWidth(screen)
                - Preferences.appearanceThemeParameters.highlightBorderWidth * 2
                - Preferences.edgeInsetsSize * 2
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
            let contentWidth = Preferences.iconSize
            let leftRightEdgeInsetsSize = ThumbnailView.getTopBottomEdgeInsetsSize()
            let frameWidth = contentWidth + leftRightEdgeInsetsSize
            let width = max(frameWidth, widthMin).rounded()
            if widthMin > frameWidth {
                let iconSize = width - leftRightEdgeInsetsSize
                return NSSize(width: iconSize, height: iconSize)
            }
        }
        return NSSize(width: Preferences.iconSize, height: Preferences.iconSize)
    }

    static func height(_ screen: NSScreen) -> CGFloat {
        let topBottomEdgeInsetsSize = ThumbnailView.getTopBottomEdgeInsetsSize()
        if Preferences.appearanceStyle == .titles {
            return max(ThumbnailView.iconSize(screen).height, ThumbnailTitleView.maxHeight()) + topBottomEdgeInsetsSize
        } else if Preferences.appearanceStyle == .appIcons {
            return ThumbnailView.iconSize(screen).height + topBottomEdgeInsetsSize + Preferences.intraCellPadding + Preferences.fontHeight
        }
        return ThumbnailView.maxThumbnailHeight(screen).rounded(.down)
    }

    static func getLeftRightEdgeInsetsSize() -> CGFloat {
        return Preferences.appearanceThemeParameters.highlightBorderWidth * 2 + Preferences.edgeInsetsSize * 2
    }

    static func getTopBottomEdgeInsetsSize() -> CGFloat {
        return Preferences.appearanceThemeParameters.highlightBorderWidth * 2 + Preferences.edgeInsetsSize * 2
    }
}
