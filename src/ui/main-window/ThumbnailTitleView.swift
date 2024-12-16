import Cocoa

class ThumbnailTitleView: BaseLabel {
    convenience init(_ height: CGFloat,
                     _ shadow: NSShadow? = ThumbnailView.makeShadow(Appearance.titleShadowColor)) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.maximumNumberOfLines = 1
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        self.init(NSRect.zero, textContainer)

        font = Appearance.font
        textColor = Appearance.fontColor
        self.shadow = shadow
        defaultParagraphStyle = makeParagraphStyle(height)

        // Set height constraint
        let lineHeight = height + ThumbnailTitleView.extraLineSpacing(for: height)
        heightAnchor.constraint(equalToConstant: lineHeight).isActive = true
    }

    private func makeParagraphStyle(_ size: CGFloat) -> NSMutableParagraphStyle {
        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.lineBreakMode = getTruncationMode()
        paragraphStyle.maximumLineHeight = size + ThumbnailTitleView.extraLineSpacing(for: size)
        paragraphStyle.minimumLineHeight = size
        paragraphStyle.allowsDefaultTighteningForTruncation = false
        return paragraphStyle
    }

    private func getTruncationMode() -> NSLineBreakMode {
        if Preferences.titleTruncation == .end {
            return .byTruncatingTail
        }
        if Preferences.titleTruncation == .middle {
            return .byTruncatingMiddle
        }
        return .byTruncatingHead
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let textStorage = textStorage,
              let layoutManager = textStorage.layoutManagers.first,
              let textContainer = layoutManager.textContainers.first else {
            return
        }
        textContainer.size = bounds.size

        // Get the layout rectangle for the text
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let textBoundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

        // Calculate the vertical offset to center the text within the view's bounds
        let yOffset = (bounds.height - textBoundingRect.height) / 2.0
        let drawPoint = NSPoint(x: 0, y: yOffset)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: drawPoint)
    }

    func getTitleWidth() -> CGFloat {
        guard let font = self.font else {
            return 0
        }

        let text = self.string
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: defaultParagraphStyle ?? NSParagraphStyle.default
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)

        // Use boundingRect to calculate the text size
        let textSize = attributedString.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
        ).size

        return ceil(textSize.width)
    }

    static func extraLineSpacing(for fontSize: CGFloat) -> CGFloat {
        return fontSize * 0.2
    }

    static func maxHeight() -> CGFloat {
        return Appearance.fontHeight + extraLineSpacing(for: Appearance.fontHeight)
    }
}
