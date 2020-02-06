import Cocoa

class TextArea: NSTextView {
    static let paddingX = CGFloat(5)
    static let paddingY = CGFloat(10)
    @objc var placeholderAttributedString: NSAttributedString?

    convenience init(_ width: CGFloat, _ height: CGFloat, _ placeholder: String) {
        self.init(frame: .zero)
        font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textContainerInset = NSSize(width: TextArea.paddingX, height: TextArea.paddingY)
        fit(font!.xHeight * width + TextArea.paddingX * 2, NSFont.systemFontSize * height + TextArea.paddingY * 2)
        placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [NSAttributedString.Key.foregroundColor: NSColor.gray])
    }
}
