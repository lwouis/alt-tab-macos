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
        vStackView.layer!.borderWidth = cellBorderWidth
        vStackView.layer!.borderColor = .clear
        vStackView.edgeInsets = NSEdgeInsets(top: cellPadding, left: cellPadding, bottom: cellPadding, right: cellPadding)
        vStackView.orientation = .vertical
        vStackView.spacing = interItemPadding
        let hStackView = NSStackView()
        hStackView.spacing = interItemPadding
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.maximumNumberOfLines = 1
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        text = NSTextView(frame: .zero, textContainer: textContainer)
        text.drawsBackground = true
        text.backgroundColor = .clear
        text.isSelectable = false
        text.isEditable = false
        text.font = font
        text.textColor = highlightColor
        let shadow = NSShadow()
        shadow.shadowColor = .darkGray
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = 1
        text.shadow = shadow
        text.enabledTextCheckingTypes = 0
        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.maximumLineHeight = fontHeight
        paragraphStyle.minimumLineHeight = fontHeight
        paragraphStyle.allowsDefaultTighteningForTruncation = false
        text.defaultParagraphStyle = paragraphStyle
        text.heightAnchor.constraint(equalToConstant: fontHeight).isActive = true
        let shadow2 = NSShadow()
        shadow2.shadowColor = .gray
        shadow2.shadowOffset = .zero
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
            view.layer!.borderColor = isSelected ? highlightColor.cgColor : .clear
        }
    }

    func updateWithNewContent(_ element: OpenWindow, _ fn: @escaping (OpenWindow) -> Void) {
        openWindow = element
        thumbnail.image = element.thumbnail
        let (width, height) = computeDownscaledSize(element.thumbnail)
        thumbnail.image!.size = NSSize(width: width, height: height)
        thumbnail.frame.size = NSSize(width: width, height: height)
        icon.image = element.icon
        icon.image!.size = NSSize(width: iconSize, height: iconSize)
        icon.frame.size = NSSize(width: iconSize, height: iconSize)
        text.string = element.cgTitle
        // workaround: setting string on NSTextView change the font (most likely a Cocoa bug)
        text.font = font
        text.textContainer!.size.width = thumbnail.frame.size.width - iconSize - interItemPadding
        mouseDownCallback = fn
    }
}
