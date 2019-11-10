import Cocoa

class HyperlinkLabel: NSTextField {

    public convenience init(labelWithUrl stringValue: String, nsUrl: NSURL) {
        self.init(labelWithString: stringValue)
        isSelectable = true
        allowsEditingTextAttributes = true
        let linkTextAttributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.link: nsUrl as Any,
            NSAttributedString.Key.font: NSFont.labelFont(ofSize: NSFont.systemFontSize),
        ]

        attributedStringValue = NSAttributedString(string: stringValue, attributes: linkTextAttributes)
    }

    // the whole point for this sub-class: always display a pointing-hand cursor (not only when the TextField is focused)
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: NSCursor.pointingHand)
    }
}