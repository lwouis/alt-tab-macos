import Cocoa

class CollectionViewItemView: NSView {
    var window_: Window?
    var thumbnail = NSImageView()
    var appIcon = NSImageView()
    var label = CellTitle(Preferences.fontHeight)
    var minimizedIcon = FontIcon(FontIcon.sfSymbolCircledMinusSign, Preferences.fontIconSize, .white)
    var hiddenIcon = FontIcon(FontIcon.sfSymbolCircledDotSign, Preferences.fontIconSize, .white)
    var spaceIcon = FontIcon(FontIcon.sfSymbolCircledNumber0, Preferences.fontIconSize, .white)
    var mouseDownCallback: MouseDownCallback!
    var mouseMovedCallback: MouseMovedCallback!
    var dragAndDropTimer: Timer?

    convenience init() {
        self.init(frame: .zero)
        let hStackView = makeHStackView()
        let vStackView = makeVStackView(hStackView)
        let shadow = CollectionViewItemView.makeShadow(.gray)
        thumbnail.shadow = shadow
        appIcon.shadow = shadow
        observeDragAndDrop()
        subviews.append(vStackView)
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
        (App.shared as! App).hideUi()
        return open != nil
    }

    override func mouseMoved(with event: NSEvent) {
        mouseMovedCallback()
    }

    override func mouseDown(with theEvent: NSEvent) {
        mouseDownCallback()
    }

    func updateRecycledCellWithNewContent(_ element: Window, _ mouseDownCallback: @escaping MouseDownCallback, _ mouseMovedCallback: @escaping MouseMovedCallback, _ screen: NSScreen) {
        window_ = element
        thumbnail.image = element.thumbnail
        let (thumbnailWidth, thumbnailHeight) = CollectionViewItemView.thumbnailSize(element.thumbnail, screen)
        let thumbnailSize = NSSize(width: thumbnailWidth.rounded(), height: thumbnailHeight.rounded())
        thumbnail.image?.size = thumbnailSize
        thumbnail.frame.size = thumbnailSize
        appIcon.image = element.icon
        let appIconSize = NSSize(width: Preferences.iconSize, height: Preferences.iconSize)
        appIcon.image?.size = appIconSize
        appIcon.frame.size = appIconSize
        label.string = element.title
        // workaround: setting string on NSTextView change the font (most likely a Cocoa bug)
        label.font = Preferences.font
        hiddenIcon.isHidden = !window_!.isHidden
        minimizedIcon.isHidden = !window_!.isMinimized
        spaceIcon.isHidden = element.spaceIndex == nil || Spaces.isSingleSpace || Preferences.hideSpaceNumberLabels
        if !spaceIcon.isHidden {
            if element.isOnAllSpaces {
                spaceIcon.setStar()
            } else {
                spaceIcon.setNumber(UInt32(element.spaceIndex!))
            }
        }
        let fontIconWidth = CGFloat([minimizedIcon, hiddenIcon, spaceIcon].filter { !$0.isHidden }.count) * (Preferences.fontIconSize + Preferences.intraCellPadding)
        label.textContainer!.size.width = frame.width - Preferences.iconSize - Preferences.intraCellPadding * 3 - fontIconWidth
        subviews.first!.frame.size = frame.size
        self.mouseDownCallback = mouseDownCallback
        self.mouseMovedCallback = mouseMovedCallback
        if trackingAreas.count > 0 {
            removeTrackingArea(trackingAreas[0])
        }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways], owner: self, userInfo: nil))
    }

    static func makeShadow(_ color: NSColor) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 1
        return shadow
    }

    static func downscaleFactor() -> CGFloat {
        let nCellsBeforePotentialOverflow = Preferences.minRows * Preferences.minCellsPerRow
        guard CGFloat(Windows.list.count) > nCellsBeforePotentialOverflow else { return 1 }
        // TODO: replace this buggy heuristic with a correct implementation of downscaling
        return nCellsBeforePotentialOverflow / (nCellsBeforePotentialOverflow + (sqrt(CGFloat(Windows.list.count) - nCellsBeforePotentialOverflow) * 2))
    }

    static func widthMax(_ screen: NSScreen) -> CGFloat {
        return (ThumbnailsPanel.widthMax(screen) / Preferences.minCellsPerRow - Preferences.interCellPadding) * CollectionViewItemView.downscaleFactor()
    }

    static func widthMin(_ screen: NSScreen) -> CGFloat {
        return (ThumbnailsPanel.widthMax(screen) / Preferences.maxCellsPerRow - Preferences.interCellPadding) * CollectionViewItemView.downscaleFactor()
    }

    static func height(_ screen: NSScreen) -> CGFloat {
        return (ThumbnailsPanel.heightMax(screen) / Preferences.minRows - Preferences.interCellPadding) * CollectionViewItemView.downscaleFactor()
    }

    static func width(_ image: NSImage?, _ screen: NSScreen) -> CGFloat {
        return max(thumbnailSize(image, screen).0 + Preferences.intraCellPadding * 2, CollectionViewItemView.widthMin(screen))
    }

    static func thumbnailSize(_ image: NSImage?, _ screen: NSScreen) -> (CGFloat, CGFloat) {
        guard let image = image else { return (0, 0) }
        let thumbnailHeightMax = CollectionViewItemView.height(screen) - Preferences.intraCellPadding * 3 - Preferences.iconSize
        let thumbnailWidthMax = CollectionViewItemView.widthMax(screen) - Preferences.intraCellPadding * 2
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

    private func makeVStackView(_ hStackView: NSStackView) -> NSStackView {
        let vStackView = NSStackView()
        vStackView.wantsLayer = true
        vStackView.layer!.backgroundColor = .clear
        vStackView.layer!.cornerRadius = Preferences.cellCornerRadius
        vStackView.layer!.borderWidth = Preferences.cellBorderWidth
        vStackView.layer!.borderColor = .clear
        vStackView.edgeInsets = NSEdgeInsets(top: Preferences.intraCellPadding, left: Preferences.intraCellPadding, bottom: Preferences.intraCellPadding, right: Preferences.intraCellPadding)
        vStackView.orientation = .vertical
        vStackView.spacing = Preferences.intraCellPadding
        vStackView.setViews([hStackView, thumbnail], in: .leading)
        return vStackView
    }
}

typealias MouseDownCallback = () -> Void
typealias MouseMovedCallback = () -> Void
