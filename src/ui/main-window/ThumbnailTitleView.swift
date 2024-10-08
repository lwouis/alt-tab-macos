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
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }

    private func makeParagraphStyle(_ size: CGFloat) -> NSMutableParagraphStyle {
        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.lineBreakMode = getTruncationMode()
        paragraphStyle.maximumLineHeight = size
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

    static func maxHeight() -> CGFloat {
        return Appearance.fontHeight + 3
    }
}
