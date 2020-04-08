import Cocoa

class ThumbnailView: NSStackView {
    var window_: Window?
    var thumbnail = NSImageView()
    var appIcon = NSImageView()
    var label = ThumbnailTitleView(Preferences.fontHeight)
    var minimizedIcon = ThumbnailFontIconView(ThumbnailFontIconView.sfSymbolCircledMinusSign, Preferences.fontIconSize, .white)
    var hiddenIcon = ThumbnailFontIconView(ThumbnailFontIconView.sfSymbolCircledDotSign, Preferences.fontIconSize, .white)
    var spaceIcon = ThumbnailFontIconView(ThumbnailFontIconView.sfSymbolCircledNumber0, Preferences.fontIconSize, .white)
    var mouseDownCallback: MouseDownCallback!
    var mouseMovedCallback: MouseMovedCallback!
    var dragAndDropTimer: Timer?

    convenience init() {
        self.init(frame: .zero)
        let hStackView = makeHStackView()
        setupView(hStackView)
        let shadow = ThumbnailView.makeShadow(.gray)
        thumbnail.shadow = shadow
        appIcon.shadow = shadow
        observeDragAndDrop()
    }

    func updateRecycledCellWithNewContent(_ element: Window, _ mouseDownCallback: @escaping MouseDownCallback, _ mouseMovedCallback: @escaping MouseMovedCallback, _ newHeight: CGFloat, _ screen: NSScreen) {
        window_ = element
//        element.itemView = self
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
        if label.string != element.title {
            label.string = element.title
            // workaround: setting string on NSTextView change the font (most likely a Cocoa bug)
            label.font = Preferences.font
            // force a display to avoid flickering; see https://github.com/lwouis/alt-tab-macos/issues/197
            label.display()
        }
        assignIfDifferent(&hiddenIcon.isHidden, !window_!.isHidden)
        assignIfDifferent(&minimizedIcon.isHidden, !window_!.isMinimized)
        assignIfDifferent(&spaceIcon.isHidden, element.spaceIndex == nil || Spaces.isSingleSpace || Preferences.hideSpaceNumberLabels)
        if !spaceIcon.isHidden {
            if element.isOnAllSpaces {
                spaceIcon.setStar()
            } else {
                spaceIcon.setNumber(UInt32(element.spaceIndex!))
            }
        }
        assignIfDifferent(&frame.size.width, thumbnail.frame.size.width + Preferences.intraCellPadding * 2)
        assignIfDifferent(&frame.size.height, newHeight)
        let fontIconWidth = CGFloat([minimizedIcon, hiddenIcon, spaceIcon].filter { !$0.isHidden }.count) * (Preferences.fontIconSize + Preferences.intraCellPadding)
        assignIfDifferent(&label.textContainer!.size.width, frame.width - Preferences.iconSize - Preferences.intraCellPadding * 3 - fontIconWidth)
        assignIfDifferent(&subviews.first!.frame.size, frame.size)
        self.mouseDownCallback = mouseDownCallback
        self.mouseMovedCallback = mouseMovedCallback
        if trackingAreas.count == 0 {
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways], owner: self, userInfo: nil))
        } else if trackingAreas.count > 0 && trackingAreas[0].rect != bounds {
            removeTrackingArea(trackingAreas[0])
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways], owner: self, userInfo: nil))
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
        return ThumbnailsPanel.widthMax(screen) / Preferences.minCellsPerRow - Preferences.interCellPadding
    }

    static func widthMin(_ screen: NSScreen) -> CGFloat {
        return ThumbnailsPanel.widthMax(screen) / Preferences.maxCellsPerRow - Preferences.interCellPadding
    }

    static func height(_ screen: NSScreen) -> CGFloat {
        return ThumbnailsPanel.heightMax(screen) / Preferences.rowsCount - Preferences.interCellPadding
    }

    static func width(_ image: NSImage?, _ screen: NSScreen) -> CGFloat {
        return max(thumbnailSize(image, screen).0 + Preferences.intraCellPadding * 2, ThumbnailView.widthMin(screen))
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

    private func makeHStackView() -> NSStackView {
        let hStackView = NSStackView()
        hStackView.spacing = Preferences.intraCellPadding
        hStackView.setViews([appIcon, label, hiddenIcon, minimizedIcon, spaceIcon], in: .leading)
        return hStackView
    }

    private func setupView(_ hStackView: NSStackView) {
        wantsLayer = true
        layer!.backgroundColor = .clear
        layer!.cornerRadius = Preferences.cellCornerRadius
        layer!.borderWidth = Preferences.cellBorderWidth
        layer!.borderColor = .clear
        edgeInsets = NSEdgeInsets(top: Preferences.intraCellPadding, left: Preferences.intraCellPadding, bottom: Preferences.intraCellPadding, right: Preferences.intraCellPadding)
        orientation = .vertical
        spacing = Preferences.intraCellPadding
        setViews([hStackView, thumbnail], in: .leading)
    }
}

typealias MouseDownCallback = () -> Void
typealias MouseMovedCallback = () -> Void
