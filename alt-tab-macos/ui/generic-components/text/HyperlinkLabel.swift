import Cocoa

class HyperlinkLabel: NSTextField {
    convenience init(_ string: String, _ url: String) {
        self.init(labelWithString: string)
        isSelectable = true
        allowsEditingTextAttributes = true
        attributedStringValue = NSAttributedString(string: string, attributes: [
            NSAttributedString.Key.link: NSURL(string: url)!,
            NSAttributedString.Key.font: NSFont.labelFont(ofSize: NSFont.systemFontSize),
        ])
    }

    // the whole point for this sub-class: always display a pointing-hand cursor (not only when the TextField is focused)
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: NSCursor.pointingHand)
    }
}
