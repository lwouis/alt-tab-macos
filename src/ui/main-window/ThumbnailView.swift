import Cocoa

class ThumbnailView: NSStackView {
    static let windowsControlSize = CGFloat(16)
    static let windowsControlSpacing = CGFloat(8)
    var window_: Window?
    var thumbnail = NSImageView()
    var appIcon = NSImageView()
    var label = ThumbnailTitleView(Preferences.fontHeight)
    var fullscreenIcon = ThumbnailFontIconView(.circledPlusSign, NSLocalizedString("Window is fullscreen", comment: ""))
    var minimizedIcon = ThumbnailFontIconView(.circledMinusSign, NSLocalizedString("Window is minimized", comment: ""))
    var hiddenIcon = ThumbnailFontIconView(.circledSlashSign, NSLocalizedString("App is hidden", comment: ""))
    var spaceIcon = ThumbnailFontIconView(.circledNumber0, nil)
    var dockLabelIcon = ThumbnailFilledFontIconView(ThumbnailFontIconView(.filledCircledNumber0, nil, 14, NSColor(srgbRed: 1, green: 0.30, blue: 0.25, alpha: 1), nil), NSColor.white)
    var quitIcon = TrafficLightButton(.quit, NSLocalizedString("Quit app", comment: ""), windowsControlSize)
    var closeIcon = TrafficLightButton(.close, NSLocalizedString("Close window", comment: ""), windowsControlSize)
    var minimizeIcon = TrafficLightButton(.miniaturize, NSLocalizedString("Minimize/Deminimize window", comment: ""), windowsControlSize)
    var maximizeIcon = TrafficLightButton(.fullscreen, NSLocalizedString("Fullscreen window", comment: ""), windowsControlSize)
    var hStackView: NSStackView!
    var mouseUpCallback: (() -> Void)!
    var mouseMovedCallback: (() -> Void)!
    var dragAndDropTimer: Timer?
    var isHighlighted = false
    var shouldShowWindowControls = false
    var isShowingWindowControls = false
    var windowlessIcon = FontIcon(.newWindow, NSLocalizedString("App is running but has no open window", comment: ""))

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
        wantsLayer = true
        layer!.backgroundColor = .clear
        layer!.borderColor = .clear
        layer!.cornerRadius = Preferences.cellCornerRadius
        layer!.borderWidth = Preferences.cellBorderWidth
        edgeInsets = NSEdgeInsets(top: Preferences.intraCellPadding, left: Preferences.intraCellPadding, bottom: Preferences.intraCellPadding, right: Preferences.intraCellPadding)
        orientation = .vertical
        let shadow = ThumbnailView.makeShadow(.gray)
        thumbnail.shadow = shadow
        windowlessIcon.shadow = shadow
        appIcon.shadow = shadow
        hStackView = NSStackView(views: [appIcon, label, hiddenIcon, fullscreenIcon, minimizedIcon, spaceIcon])
        setViews([hStackView, thumbnail, windowlessIcon], in: .leading)
        addWindowControls()
        addDockLabelIcon()
        setAccessibilityChildren([])
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
                    ((window_?.isWindowlessApp ?? true) && icon.type != .quit) ||
                    (icon.type == .quit && window_?.application.runningApplication.bundleIdentifier == "com.apple.finder" && !Preferences.finderShowsQuitMenuItem)
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
            }
        }
    }

    func highlight(_ highlight: Bool) {
        if isHighlighted != highlight {
            isHighlighted = highlight
            if frame != NSRect.zero {
                highlightOrNot()
            }
        }
        showOrHideWindowControls(false)
    }

    func highlightOrNot() {
        layer!.backgroundColor = isHighlighted ? Preferences.highlightBackgroundColor.cgColor : .clear
        layer!.borderColor = isHighlighted ? Preferences.highlightBorderColor.cgColor : .clear
        let frameInset: CGFloat = Preferences.intraCellPadding * (isHighlighted ? -1 : 1)
        frame = frame.insetBy(dx: frameInset, dy: frameInset)
        let edgeInsets_: CGFloat = Preferences.intraCellPadding * (isHighlighted ? 2 : 1)
        edgeInsets.top = edgeInsets_
        edgeInsets.right = edgeInsets_
        edgeInsets.bottom = edgeInsets_
        edgeInsets.left = edgeInsets_
    }

    func updateRecycledCellWithNewContent(_ element: Window, _ index: Int, _ newHeight: CGFloat, _ screen: NSScreen) {
        window_ = element
        assignIfDifferent(&thumbnail.isHidden, Preferences.hideThumbnails || element.isWindowlessApp)
        if !thumbnail.isHidden {
            thumbnail.image = element.thumbnail
            if let image = thumbnail.image {
                image.size = element.thumbnailFullSize!
            }
            let (thumbnailWidth, thumbnailHeight) = ThumbnailView.thumbnailSize(element.thumbnail, screen)
            let thumbnailSize = NSSize(width: thumbnailWidth.rounded(), height: thumbnailHeight.rounded())
            thumbnail.image?.size = thumbnailSize
            thumbnail.frame.size = thumbnailSize
            // for Accessibility > "speak items under the pointer"
            thumbnail.setAccessibilityLabel(element.title)
        }
        assignIfDifferent(&spacing, Preferences.hideThumbnails ? 0 : Preferences.intraCellPadding)
        assignIfDifferent(&hStackView.spacing, Preferences.fontHeight == 0 ? 0 : Preferences.intraCellPadding)
        let appIconChanged = appIcon.image != element.icon
        if appIconChanged {
            appIcon.image = element.icon
            let appIconSize = NSSize(width: Preferences.iconSize, height: Preferences.iconSize)
            appIcon.image?.size = appIconSize
            appIcon.frame.size = appIconSize
            appIcon.setAccessibilityLabel(element.application.runningApplication.localizedName)
            appIcon.toolTip = element.application.runningApplication.localizedName
        }
        let labelChanged = label.string != element.title
        if labelChanged {
            label.string = element.title
            // workaround: setting string on NSTextView changes the font (most likely a Cocoa bug)
            label.font = Preferences.font
            setAccessibilityLabel(element.title)
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
        let widthMin = ThumbnailView.widthMin(screen)
        assignIfDifferent(&frame.size.width, max((Preferences.hideThumbnails || element.isWindowlessApp ? hStackView.fittingSize.width : thumbnail.frame.size.width) + Preferences.intraCellPadding * 2, widthMin).rounded())
        assignIfDifferent(&frame.size.height, newHeight)
        let fontIconWidth = CGFloat([fullscreenIcon, minimizedIcon, hiddenIcon, spaceIcon].filter { !$0.isHidden }.count) * (Preferences.fontHeight + Preferences.intraCellPadding)
        assignIfDifferent(&label.textContainer!.size.width, frame.width - Preferences.iconSize - Preferences.intraCellPadding * 3 - fontIconWidth)
        label.toolTip = label.textStorage!.size().width >= label.textContainer!.size.width ? label.string : nil
        assignIfDifferent(&windowlessIcon.isHidden, !element.isWindowlessApp || Preferences.hideThumbnails)
        if element.isWindowlessApp {
            let maxWidth = (frame.size.width - Preferences.intraCellPadding * 2).rounded()
            let maxHeight = (frame.size.height - hStackView.fittingSize.height - Preferences.intraCellPadding * 2).rounded()
            // heuristic to determine font size based on bounding box
            let fontSize = (min(maxWidth - Preferences.intraCellPadding * 2, maxHeight - Preferences.intraCellPadding * 2) * 0.6).rounded()
            // heuristic to fit the SF Symbol into the bounding box
            let labelViewHeight = (fontSize * 1.4).rounded()
            windowlessIcon.labelView.frame = NSRect(x: Preferences.intraCellPadding, y: ((maxHeight - labelViewHeight) / 2).rounded(), width: maxWidth - Preferences.intraCellPadding * 2, height: labelViewHeight - Preferences.intraCellPadding * 2)
            windowlessIcon.labelView.font = NSFont(name: windowlessIcon.labelView.font!.fontName, size: fontSize)
            windowlessIcon.needsDisplay = true
        }
        self.mouseUpCallback = { () -> Void in App.app.focusSelectedWindow(element) }
        self.mouseMovedCallback = { () -> Void in Windows.updateFocusedWindowIndex(index) }
        [quitIcon, closeIcon, minimizeIcon, maximizeIcon].forEach { $0.window_ = element }
        showOrHideWindowControls(false)
        // force a display to avoid flickering; see https://github.com/lwouis/alt-tab-macos/issues/197
        // quirk: display() should be called last as it resets thumbnail.frame.size somehow
        if labelChanged {
            label.display()
        }
    }

    @discardableResult
    func updateDockLabelIcon(_ dockLabel: Int?) -> Bool {
        assignIfDifferent(&dockLabelIcon.isHidden, dockLabel == nil || Preferences.hideAppBadges || Preferences.iconSize == 0)
        if !dockLabelIcon.isHidden, let dockLabel = dockLabel {
            let view = dockLabelIcon.subviews[1] as! ThumbnailFontIconView
            if dockLabel > 30 {
                view.setFilledStar()
            } else {
                view.setNumber(dockLabel, true)
            }
            dockLabelIcon.setFrameOrigin(NSPoint(x: appIcon.frame.maxX - dockLabelIcon.fittingSize.width - 1, y: appIcon.frame.maxY - dockLabelIcon.fittingSize.height + 4))
            view.setAccessibilityLabel(getAccessibilityTextForBadge(dockLabel))
            return true
        }
        return false
    }

    func getAccessibilityHelp(_ appName: String?, _ dockLabel: Int?) -> String {
        [appName, dockLabel.map { getAccessibilityTextForBadge($0) }]
                .compactMap { $0 }
                .joined(separator: " - ")
    }

    func getAccessibilityTextForBadge(_ dockLabel: Int) -> String {
        "Red badge with number \(dockLabel)"
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
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as! [URL]
        let appUrl = window_!.application.runningApplication.bundleURL!
        let open = try? NSWorkspace.shared.open(urls, withApplicationAt: appUrl, options: [], configuration: [:])
        App.app.hideUi()
        return open != nil
    }

    func mouseMoved() {
        showOrHideWindowControls(true)
        if Preferences.mouseHoverEnabled && !isHighlighted {
            mouseMovedCallback()
        }
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

    static func makeShadow(_ color: NSColor) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 1
        return shadow
    }

    static func widthMax(_ screen: NSScreen) -> CGFloat {
        return ThumbnailsPanel.widthMax(screen) * Preferences.windowMaxWidthInRow - Preferences.interCellPadding * 2
    }

    static func widthMin(_ screen: NSScreen) -> CGFloat {
        return ThumbnailsPanel.widthMax(screen) * Preferences.windowMinWidthInRow - Preferences.interCellPadding * 2
    }

    static func height(_ screen: NSScreen) -> CGFloat {
        return (ThumbnailsPanel.heightMax(screen) - Preferences.interCellPadding) / Preferences.rowsCount - Preferences.interCellPadding
    }

    static func thumbnailSize(_ image: NSImage?, _ screen: NSScreen) -> (CGFloat, CGFloat) {
        guard let image = image else { return (0, 0) }
        let thumbnailHeightMax = ThumbnailView.height(screen) - Preferences.intraCellPadding * 3 - Preferences.iconSize
        let thumbnailWidthMax = ThumbnailView.widthMax(screen) - Preferences.intraCellPadding * 2
        let thumbnailHeight = min(image.size.height, thumbnailHeightMax)
        let thumbnailWidth = min(image.size.width, thumbnailWidthMax)
        let imageRatio = image.size.width / image.size.height
        let thumbnailRatio = thumbnailWidth / thumbnailHeight
        if thumbnailRatio > imageRatio {
            return (image.size.width * thumbnailHeight / image.size.height, thumbnailHeight)
        }
        return (thumbnailWidth, image.size.height * thumbnailWidth / image.size.width)
    }
}
