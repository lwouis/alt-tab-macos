import Cocoa

class ThumbnailTitleView: BaseLabel {
    var magicOffset = CGFloat(0)

    convenience init(_ size: CGFloat, _ magicOffset: CGFloat = 0) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.maximumNumberOfLines = 1
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        self.init(NSRect.zero, textContainer)
        font = Preferences.font
        self.magicOffset = magicOffset
        textColor = Preferences.fontColor
        shadow = ThumbnailView.makeShadow(.darkGray)
        defaultParagraphStyle = makeParagraphStyle(size)
        heightAnchor.constraint(equalToConstant: size + magicOffset).isActive = true
    }

    private func makeParagraphStyle(_ size: CGFloat) -> NSMutableParagraphStyle {
        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.lineBreakMode = .byTruncatingTail
        paragraphStyle.maximumLineHeight = size + magicOffset
        paragraphStyle.minimumLineHeight = size + magicOffset
        paragraphStyle.allowsDefaultTighteningForTruncation = false
        return paragraphStyle
    }
}
