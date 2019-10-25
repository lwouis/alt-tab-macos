import Cocoa

class Cell: NSCollectionViewItem {
    var thumbnail = NSImageView()
    var icon = NSImageView()
    var label = CellTitle()
    var openWindow: OpenWindow?
    var mouseDownCallback: ((OpenWindow) -> Void)?

    static func makeShadow(_ color: NSColor) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowOffset = NSMakeSize(0, 0)
        shadow.shadowBlurRadius = 1
        return shadow
    }

    override func mouseDown(with theEvent: NSEvent) {
        mouseDownCallback!(openWindow!)
    }

    override func loadView() {
        let hStackView = makeHStackView()
        let vStackView = makeVStackView(hStackView)
        let shadow = Cell.makeShadow(.gray)
        thumbnail.shadow = shadow
        icon.shadow = shadow
        view = vStackView
    }

    private func makeHStackView() -> NSStackView {
        let hStackView = NSStackView()
        hStackView.spacing = Preferences.interItemPadding
        hStackView.addView(icon, in: .leading)
        hStackView.addView(label, in: .leading)
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

    override var isSelected: Bool {
        didSet {
            view.layer!.backgroundColor = isSelected ? Preferences.highlightBackgroundColor!.cgColor : .clear
            view.layer!.borderColor = isSelected ? Preferences.highlightBorderColor!.cgColor : .clear
        }
    }

    func updateWithNewContent(_ element: OpenWindow, _ fn: @escaping (OpenWindow) -> Void) {
        openWindow = element
        thumbnail.image = element.thumbnail
        let (width, height) = computeDownscaledSize(element.thumbnail)
        thumbnail.image!.size = NSSize(width: width, height: height)
        thumbnail.frame.size = NSSize(width: width, height: height)
        icon.image = element.icon
        icon.image?.size = NSSize(width: Preferences.iconSize!, height: Preferences.iconSize!)
        icon.frame.size = NSSize(width: Preferences.iconSize!, height: Preferences.iconSize!)
        label.string = element.cgTitle
        // workaround: setting string on NSTextView change the font (most likely a Cocoa bug)
        label.font = Preferences.font!
        label.textContainer!.size.width = thumbnail.frame.size.width - Preferences.iconSize! - Preferences.interItemPadding
        mouseDownCallback = fn
    }
}
