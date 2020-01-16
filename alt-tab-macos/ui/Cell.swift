import Cocoa
import WebKit

typealias MouseDownCallback = (Window) -> Void
typealias MouseMovedCallback = (Cell) -> Void

class Cell: NSCollectionViewItem {
    var thumbnail = NSImageView()
    var appIcon = NSImageView()
    var label = CellTitle(Preferences.fontHeight)
    var minimizedIcon = FontIcon(FontIcon.sfSymbolCircledMinusSign, Preferences.fontIconSize, .white)
    var hiddenIcon = FontIcon(FontIcon.sfSymbolCircledDotSign, Preferences.fontIconSize, .white)
    var spaceIcon = FontIcon(FontIcon.sfSymbolCircledNumber0, Preferences.fontIconSize, .white)
    var window: Window?
    var mouseDownCallback: MouseDownCallback?
    var mouseMovedCallback: MouseMovedCallback?

    override func loadView() {
        let hStackView = makeHStackView()
        let vStackView = makeVStackView(hStackView)
        let shadow = Cell.makeShadow(.gray)
        thumbnail.shadow = shadow
        appIcon.shadow = shadow
        view = vStackView
    }

    override func mouseMoved(with event: NSEvent) {
        mouseMovedCallback!(self)
    }

    override func mouseDown(with theEvent: NSEvent) {
        mouseDownCallback!(window!)
    }

    override var isSelected: Bool {
        didSet {
            view.layer!.backgroundColor = isSelected ? Preferences.highlightBackgroundColor!.cgColor : .clear
            view.layer!.borderColor = isSelected ? Preferences.highlightBorderColor!.cgColor : .clear
        }
    }

    func updateRecycledCellWithNewContent(_ element: Window, _ mouseDownCallback: @escaping MouseDownCallback, _ mouseMovedCallback: @escaping MouseMovedCallback, _ screen: NSScreen) {
        window = element
        thumbnail.image = element.thumbnail
        let thumbnailSize = Cell.thumbnailSize(element.thumbnail, screen)
        thumbnail.image?.size = thumbnailSize
        thumbnail.frame.size = thumbnailSize
        appIcon.image = element.icon
        let appIconSize = NSSize(width: Preferences.iconSize, height: Preferences.iconSize)
        appIcon.image?.size = appIconSize
        appIcon.frame.size = appIconSize
        label.string = element.title
        // workaround: setting string on NSTextView change the font (most likely a Cocoa bug)
        label.font = Preferences.font
        hiddenIcon.isHidden = !window!.isHidden
        minimizedIcon.isHidden = !window!.isMinimized
        spaceIcon.isHidden = element.spaceIndex == nil || Spaces.isSingleSpace || Preferences.hideSpaceNumberLabels!
        if !spaceIcon.isHidden {
            if element.isOnAllSpaces {
                spaceIcon.setStar()
            } else {
                spaceIcon.setNumber(UInt32(element.spaceIndex!))
            }
        }
        let fontIconWidth = CGFloat([minimizedIcon, hiddenIcon, spaceIcon].filter { !$0.isHidden }.count) * (Preferences.fontIconSize + Preferences.cellPadding)
        label.textContainer!.size.width = view.frame.width - Preferences.iconSize - Preferences.cellPadding * 3 - fontIconWidth
        self.mouseDownCallback = mouseDownCallback
        self.mouseMovedCallback = mouseMovedCallback
        if view.trackingAreas.count > 0 {
            view.removeTrackingArea(view.trackingAreas[0])
        }
        view.addTrackingArea(NSTrackingArea(rect: view.bounds, options: [.mouseMoved, .activeAlways], owner: self, userInfo: nil))
    }

    static func makeShadow(_ color: NSColor) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 1
        return shadow
    }

    private func makeHStackView() -> NSStackView {
        let hStackView = NSStackView()
        hStackView.spacing = Preferences.cellPadding
        hStackView.setViews([appIcon, label, hiddenIcon, minimizedIcon, spaceIcon], in: .leading)
        return hStackView
    }

    private func makeVStackView(_ hStackView: NSStackView) -> NSStackView {
        let vStackView = NSStackView()
        vStackView.wantsLayer = true
        vStackView.layer!.backgroundColor = .clear
        vStackView.layer!.cornerRadius = Preferences.cellCornerRadius!
        vStackView.layer!.borderWidth = Preferences.cellBorderWidth!
        vStackView.layer!.borderColor = .clear
        vStackView.edgeInsets = NSEdgeInsets(top: Preferences.cellPadding, left: Preferences.cellPadding, bottom: Preferences.cellPadding, right: Preferences.cellPadding)
        vStackView.orientation = .vertical
        vStackView.spacing = Preferences.cellPadding
        vStackView.setViews([hStackView, thumbnail], in: .leading)
        return vStackView
    }

    static func downscaleFactor() -> CGFloat {
        let nCellsBeforePotentialOverflow = Preferences.nCellsRows * Preferences.minCellsPerRow
        guard CGFloat(Windows.list.count) > nCellsBeforePotentialOverflow else { return 1 }
        // TODO: replace this buggy heuristic with a correct implementation of downscaling
        return nCellsBeforePotentialOverflow / (nCellsBeforePotentialOverflow + (sqrt(CGFloat(Windows.list.count) - nCellsBeforePotentialOverflow) * 2))
    }

    static func widthMax(_ screen: NSScreen) -> CGFloat {
        return floor((ThumbnailsPanel.widthMax(screen) / Preferences.minCellsPerRow - Preferences.cellPadding) * Cell.downscaleFactor())
    }

    static func widthMin(_ screen: NSScreen) -> CGFloat {
        return floor((ThumbnailsPanel.widthMax(screen) / Preferences.maxCellsPerRow - Preferences.cellPadding) * Cell.downscaleFactor())
    }

    static func height(_ screen: NSScreen) -> CGFloat {
        return floor((ThumbnailsPanel.heightMax(screen) / Preferences.nCellsRows - Preferences.cellPadding) * Cell.downscaleFactor())
    }

    static func width(_ image: NSImage?, _ screen: NSScreen) -> CGFloat {
        return floor(max(thumbnailSize(image, screen).width + Preferences.cellPadding * 2, ThumbnailsPanel.widthMin(screen)))
    }

    static func thumbnailSize(_ image: NSImage?, _ screen: NSScreen) -> NSSize {
        let (width, height) = thumbnailSize_(image, screen)
        return NSSize(width: floor(width), height: floor(height))
    }

    static func thumbnailSize_(_ image: NSImage?, _ screen: NSScreen) -> (CGFloat, CGFloat) {
        let thumbnailWidthMin = Cell.widthMin(screen) - Preferences.cellPadding * 2
        let thumbnailHeightMax = Cell.height(screen) - Preferences.cellPadding * 3 - Preferences.iconSize
        let thumbnailWidthMax = Cell.widthMax(screen) - Preferences.cellPadding * 2
        guard let image = image else { return (thumbnailWidthMin, thumbnailHeightMax) }
        let imageRatio = image.size.width / image.size.height
        let thumbnailRatio = thumbnailWidthMax / thumbnailHeightMax
        if thumbnailRatio > imageRatio {
            return (image.size.width * thumbnailHeightMax / image.size.height, thumbnailHeightMax)
        }
        return (thumbnailWidthMax, image.size.height * thumbnailWidthMax / image.size.width)
    }
}
