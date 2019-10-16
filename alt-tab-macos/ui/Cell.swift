import Cocoa

class Cell: NSCollectionViewItem {
    var thumbnail = NSImageView()
    var icon = NSImageView()
    var text = NSTextView()
    var openWindow: OpenWindow?
    var mouseDownCallback: ((OpenWindow) -> Void)?

    override func mouseDown(with theEvent: NSEvent) {
        mouseDownCallback!(openWindow!)
    }

    override func loadView() {
        let vStackView = NSStackView()
        vStackView.wantsLayer = true
        vStackView.layer!.borderWidth = Preferences.cellBorderWidth
        vStackView.layer!.borderColor = .clear
        vStackView.edgeInsets = NSEdgeInsets(top: Preferences.cellPadding, left: Preferences.cellPadding, bottom: Preferences.cellPadding, right: Preferences.cellPadding)
        vStackView.orientation = .vertical
        vStackView.spacing = Preferences.interItemPadding
        let hStackView = NSStackView()
        hStackView.spacing = Preferences.interItemPadding
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.maximumNumberOfLines = 1
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        text = NSTextView.init(frame: NSRect.zero, textContainer: textContainer)
        text.drawsBackground = true
        text.backgroundColor = .clear
        text.isSelectable = false
        text.isEditable = false
        text.font = Preferences.font
        text.textColor = Preferences.highlightColor
        let shadow = NSShadow()
        shadow.shadowColor = .darkGray
        shadow.shadowOffset = NSMakeSize(0, 0)
        shadow.shadowBlurRadius = 1
        text.shadow = shadow
        text.enabledTextCheckingTypes = 0
        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.maximumLineHeight = Preferences.fontHeight
        paragraphStyle.minimumLineHeight = Preferences.fontHeight
        paragraphStyle.allowsDefaultTighteningForTruncation = false
        text.defaultParagraphStyle = paragraphStyle
        text.heightAnchor.constraint(equalToConstant: Preferences.fontHeight).isActive = true
        let shadow2 = NSShadow()
        shadow2.shadowColor = .gray
        shadow2.shadowOffset = NSMakeSize(0, 0)
        shadow2.shadowBlurRadius = 1
        thumbnail.shadow = shadow2
        icon.shadow = shadow2
        hStackView.addView(icon, in: .leading)
        hStackView.addView(text, in: .leading)
        vStackView.addView(hStackView, in: .leading)
        vStackView.addView(thumbnail, in: .leading)
        view = vStackView
    }

    override var isSelected: Bool {
        didSet {
            view.layer!.borderColor = isSelected ? Preferences.highlightColor.cgColor : .clear
        }
    }

    func updateWithNewContent(_ element: OpenWindow, _ fn: @escaping (OpenWindow) -> Void) {
        openWindow = element
        thumbnail.image = element.thumbnail
        let (width, height) = computeDownscaledSize(element.thumbnail)
        thumbnail.image!.size = NSSize(width: width, height: height)
        thumbnail.frame.size = NSSize(width: width, height: height)
        icon.image = element.icon
        icon.image!.size = NSSize(width: Preferences.iconSize, height: Preferences.iconSize)
        icon.frame.size = NSSize(width: Preferences.iconSize, height: Preferences.iconSize)
        text.string = element.cgTitle
        // workaround: setting string on NSTextView change the font (most likely a Cocoa bug)
        text.font = Preferences.font
        text.textContainer!.size.width = thumbnail.frame.size.width - Preferences.iconSize - Preferences.interItemPadding
        mouseDownCallback = fn
    }
}
