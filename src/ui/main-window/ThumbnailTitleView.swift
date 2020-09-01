import Cocoa

class ThumbnailTitleView: BaseLabel {
    convenience init(_ size: CGFloat, _ shadow: NSShadow? = ThumbnailView.makeShadow(.darkGray)) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.maximumNumberOfLines = 1
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        self.init(NSRect.zero, textContainer)
        font = Preferences.font
        textColor = Preferences.fontColor
        self.shadow = shadow
        defaultParagraphStyle = makeParagraphStyle(size)
        heightAnchor.constraint(equalToConstant: size).isActive = true
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
}
