import Cocoa

class ThumbnailView: NSStackView {
    var window_: Window?
    var thumbnail = NSImageView()
    var appIcon = NSImageView()
    var label = ThumbnailTitleView(Preferences.fontHeight)
    var fullscreenIcon = ThumbnailFontIconView(ThumbnailFontIconView.sfSymbolCircledPlusSign, Preferences.fontIconSize, .white)
    var minimizedIcon = ThumbnailFontIconView(ThumbnailFontIconView.sfSymbolCircledMinusSign, Preferences.fontIconSize, .white)
    var hiddenIcon = ThumbnailFontIconView(ThumbnailFontIconView.sfSymbolCircledSlashSign, Preferences.fontIconSize, .white)
    var spaceIcon = ThumbnailFontIconView(ThumbnailFontIconView.sfSymbolCircledNumber0, Preferences.fontIconSize, .white)
    var hStackView: NSStackView!
    var mouseDownCallback: (() -> Void)!
    var mouseMovedCallback: (() -> Void)!
    var dragAndDropTimer: Timer?
    var isHighlighted = false

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
        spacing = Preferences.intraCellPadding
        let shadow = ThumbnailView.makeShadow(.gray)
        thumbnail.shadow = shadow
        appIcon.shadow = shadow
        hStackView = NSStackView(views: [appIcon, label, hiddenIcon, fullscreenIcon, minimizedIcon, spaceIcon])
        hStackView.spacing = Preferences.intraCellPadding
        setViews([hStackView, thumbnail], in: .leading)
    }

    func highlight(_ highlight: Bool) {
        if isHighlighted != highlight {
            isHighlighted = highlight
            if frame != NSRect.zero {
                highlightOrNot()
            }
        }
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
        if thumbnail.image != element.thumbnail {
            thumbnail.image = element.thumbnail
            let (thumbnailWidth, thumbnailHeight) = ThumbnailView.thumbnailSize(element.thumbnail, screen)
            let thumbnailSize = NSSize(width: thumbnailWidth.rounded(), height: thumbnailHeight.rounded())
            thumbnail.image?.size = thumbnailSize
            thumbnail.frame.size = thumbnailSize
        }
        if appIcon.image != element.icon {
            appIcon.image = element.icon
            let appIconSize = NSSize(width: Preferences.iconSize, height: Preferences.iconSize)
            appIcon.image?.size = appIconSize
            appIcon.frame.size = appIconSize
        }
        let labelChanged = label.string != element.title
        if labelChanged {
            label.string = element.title
            // workaround: setting string on NSTextView changes the font (most likely a Cocoa bug)
            label.font = Preferences.font
        }
        assignIfDifferent(&hiddenIcon.isHidden, !element.isHidden)
        assignIfDifferent(&fullscreenIcon.isHidden, !element.isFullscreen)
        assignIfDifferent(&minimizedIcon.isHidden, !element.isMinimized)
        assignIfDifferent(&spaceIcon.isHidden, Spaces.isSingleSpace || Preferences.hideSpaceNumberLabels)
        if !spaceIcon.isHidden {
            if element.isOnAllSpaces {
                spaceIcon.setStar()
            } else {
                spaceIcon.setNumber(UInt32(element.spaceIndex))
            }
        }
        assignIfDifferent(&frame.size.width, max(thumbnail.frame.size.width + Preferences.intraCellPadding * 2, ThumbnailView.widthMin(screen)))
        assignIfDifferent(&frame.size.height, newHeight)
        let fontIconWidth = CGFloat([fullscreenIcon, minimizedIcon, hiddenIcon, spaceIcon].filter { !$0.isHidden }.count) * (Preferences.fontIconSize + Preferences.intraCellPadding)
        assignIfDifferent(&label.textContainer!.size.width, frame.width - Preferences.iconSize - Preferences.intraCellPadding * 3 - fontIconWidth)
        assignIfDifferent(&subviews.first!.frame.size, frame.size)
        self.mouseDownCallback = { () -> Void in App.app.focusSelectedWindow(element) }
        self.mouseMovedCallback = { () -> Void in Windows.updateFocusedWindowIndex(index) }
        if trackingAreas.count == 0 {
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways], owner: self, userInfo: nil))
        } else if trackingAreas.count > 0 && trackingAreas[0].rect != bounds {
            removeTrackingArea(trackingAreas[0])
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways], owner: self, userInfo: nil))
        }
        // force a display to avoid flickering; see https://github.com/lwouis/alt-tab-macos/issues/197
        // quirk: display() should be called last as it resets thumbnail.frame.size somehow
        if labelChanged {
            label.display()
        }
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
            self.mouseDownCallback()
        })
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

    override func mouseMoved(with event: NSEvent) {
        if Preferences.mouseHoverEnabled {
            mouseMovedCallback()
        }
    }

    override func mouseDown(with theEvent: NSEvent) {
        mouseDownCallback()
    }

    static func makeShadow(_ color: NSColor) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 1
        return shadow
    }

    static func widthMax(_ screen: NSScreen) -> CGFloat {
        return (ThumbnailsPanel.widthMax(screen) - Preferences.interCellPadding) / Preferences.minCellsPerRow - Preferences.interCellPadding
    }

    static func widthMin(_ screen: NSScreen) -> CGFloat {
        return (ThumbnailsPanel.widthMax(screen) - Preferences.interCellPadding) / Preferences.maxCellsPerRow - Preferences.interCellPadding
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
