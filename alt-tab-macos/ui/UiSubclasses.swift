import Cocoa

class HighInterpolationImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current!.imageInterpolation = .high
        super.draw(dirtyRect)
    }
}

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
        text = NSTextView.init(frame: NSRect.zero, textContainer: textContainer)
        text.drawsBackground = true
        text.backgroundColor = .clear
        text.isSelectable = false
        text.isEditable = false
        text.font = font
        text.textColor = highlightColor
        let shadow = NSShadow()
        shadow.shadowColor = .darkGray
        shadow.shadowOffset = NSMakeSize(0, 0)
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

class CollectionViewCenterFlowLayout: NSCollectionViewFlowLayout {
    override func layoutAttributesForElements(in rect: CGRect) -> [NSCollectionViewLayoutAttributes] {
        let attributes = super.layoutAttributesForElements(in: rect)
        if attributes.isEmpty {
            return attributes
        }
        var currentRow: [NSCollectionViewLayoutAttributes] = []
        var currentRowY = CGFloat(0)
        var currentRowWidth = CGFloat(0)
        var previousRowMaxY = CGFloat(0)
        var currentRowMaxY = CGFloat(0)
        var widestRow = CGFloat(0)
        var totalHeight = CGFloat(0)
        attributes.enumerated().forEach {
            let isNewRow = abs($1.frame.origin.y - currentRowY) > thumbnailMaxHeight
            if isNewRow {
                computeOriginXForAllItems(currentRowWidth - minimumInteritemSpacing, previousRowMaxY, currentRow)
                currentRow.removeAll()
                currentRowY = $1.frame.origin.y
                currentRowWidth = 0
                previousRowMaxY += currentRowMaxY + minimumLineSpacing
                currentRowMaxY = 0
            }
            currentRow.append($1)
            currentRowWidth += $1.frame.size.width + minimumInteritemSpacing
            widestRow = max(widestRow, currentRowWidth)
            currentRowMaxY = max(currentRowMaxY, $1.frame.size.height)
            if $0 == attributes.count - 1 {
                computeOriginXForAllItems(currentRowWidth - minimumInteritemSpacing, previousRowMaxY, currentRow)
                totalHeight = previousRowMaxY + currentRowMaxY
            }
        }
        collectionView!.setFrameSize(NSSize(width: widestRow - minimumInteritemSpacing, height: totalHeight))
        return attributes
    }

    func computeOriginXForAllItems(_ currentRowWidth: CGFloat, _ previousRowMaxHeight: CGFloat, _ currentRow: [NSCollectionViewLayoutAttributes]) {
        var marginLeft = floor((collectionView!.frame.size.width - currentRowWidth) / 2)
        currentRow.forEach {
            $0.frame.origin.x = marginLeft
            $0.frame.origin.y = previousRowMaxHeight
            marginLeft += $0.frame.size.width + minimumInteritemSpacing
        }
    }
}
