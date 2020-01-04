import Cocoa
import WebKit

typealias MouseDownCallback = (TrackedWindow) -> Void
typealias MouseMovedCallback = (Cell) -> Void

class Cell: NSCollectionViewItem {
    var thumbnail = NSImageView()
    var appIcon = NSImageView()
    var label = CellTitle(Preferences.fontHeight!)
    var minimizedIcon = FontIcon(FontIcon.sfSymbolCircledMinusSign, Preferences.fontIconSize, .white)
    var hiddenIcon = FontIcon(FontIcon.sfSymbolCircledDotSign, Preferences.fontIconSize, .white)
    var spaceIcon = FontIcon(FontIcon.sfSymbolCircledNumber0, Preferences.fontIconSize, .white)
    var openWindow: TrackedWindow?
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
        mouseDownCallback!(openWindow!)
    }

    override var isSelected: Bool {
        didSet {
            view.layer!.backgroundColor = isSelected ? Preferences.highlightBackgroundColor!.cgColor : .clear
            view.layer!.borderColor = isSelected ? Preferences.highlightBorderColor!.cgColor : .clear
        }
    }

    func updateWithNewContent(_ element: TrackedWindow, _ mouseDownCallback: @escaping MouseDownCallback, _ mouseMovedCallback: @escaping MouseMovedCallback, _ screen: NSScreen) {
        openWindow = element
        thumbnail.image = element.thumbnail
        let (width, height) = Cell.computeDownscaledSize(element.thumbnail, screen)
        thumbnail.image?.size = NSSize(width: width, height: height)
        thumbnail.frame.size = NSSize(width: width, height: height)
        appIcon.image = element.icon
        appIcon.image?.size = NSSize(width: Preferences.iconSize!, height: Preferences.iconSize!)
        appIcon.frame.size = NSSize(width: Preferences.iconSize!, height: Preferences.iconSize!)
        label.string = element.title
        // workaround: setting string on NSTextView change the font (most likely a Cocoa bug)
        label.font = Preferences.font!
        hiddenIcon.isHidden = !openWindow!.isHidden
        minimizedIcon.isHidden = !openWindow!.isMinimized
        spaceIcon.isHidden = element.spaceIndex == nil || Spaces.singleSpace || Preferences.hideSpaceNumberLabels
        if !spaceIcon.isHidden {
            spaceIcon.setNumber(UInt32(element.spaceIndex!))
        }
        let fontIconWidth = CGFloat([minimizedIcon, hiddenIcon, spaceIcon].filter { !$0.isHidden }.count) * (Preferences.fontIconSize + Preferences.interItemPadding)
        label.textContainer!.size.width = thumbnail.frame.width - Preferences.iconSize! - Preferences.interItemPadding - fontIconWidth
        self.mouseDownCallback = mouseDownCallback
        self.mouseMovedCallback = mouseMovedCallback
        if view.trackingAreas.count > 0 {
            view.removeTrackingArea(view.trackingAreas[0])
        }
        view.addTrackingArea(NSTrackingArea(rect: view.bounds, options: [.mouseMoved, .activeAlways], owner: self, userInfo: nil))
    }

    static func computeDownscaledSize(_ image: NSImage?, _ screen: NSScreen) -> (Int, Int) {
        if let image_ = image {
            let imageRatio = image_.size.width / image_.size.height
            let thumbnailMaxSize = Screen.thumbnailMaxSize(screen)
            let thumbnailWidth = Int(floor(thumbnailMaxSize.height * imageRatio))
            if thumbnailWidth <= Int(thumbnailMaxSize.width) {
                return (thumbnailWidth, Int(thumbnailMaxSize.height))
            } else {
                return (Int(thumbnailMaxSize.width), Int(floor(thumbnailMaxSize.width / imageRatio)))
            }
        }
        return (Int(Preferences.emptyThumbnailWidth), Int((Preferences.emptyThumbnailHeight)))
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
        hStackView.spacing = Preferences.interItemPadding
        hStackView.addView(appIcon, in: .leading)
        hStackView.addView(label, in: .leading)
        hStackView.addView(hiddenIcon, in: .leading)
        hStackView.addView(minimizedIcon, in: .leading)
        hStackView.addView(spaceIcon, in: .leading)
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
        vStackView.spacing = Preferences.interItemPadding
        vStackView.addView(hStackView, in: .leading)
        vStackView.addView(thumbnail, in: .leading)
        return vStackView
    }
}
