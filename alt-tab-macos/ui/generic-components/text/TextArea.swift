import Cocoa

class TextArea: NSTextView {
    static let padding = CGFloat(10)
    static let magicOffset = CGFloat(3)
    @objc var placeholderAttributedString: NSAttributedString?

    convenience init(_ width: CGFloat, _ height: CGFloat, _ placeholder: String) {
        self.init(frame: .zero)
        font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textContainerInset = NSSize(width: TextArea.padding, height: TextArea.padding)
        textContainer!.lineFragmentPadding = 0
        let paragraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraphStyle.maximumLineHeight = NSFont.systemFontSize + TextArea.magicOffset
        placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            NSAttributedString.Key.font : NSFont.systemFont(ofSize: NSFont.systemFontSize),
            NSAttributedString.Key.foregroundColor: NSColor.gray,
            NSAttributedString.Key.paragraphStyle: paragraphStyle,
        ])
        fit(font!.xHeight * width + TextArea.padding * 2, NSFont.systemFontSize * height + TextArea.padding * 2 + TextArea.magicOffset)
    }
}
