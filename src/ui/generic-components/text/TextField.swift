import Cocoa

class TextField: NSTextField {
    let insets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    convenience init(_ attributedString: NSAttributedString) {
        self.init(labelWithAttributedString: attributedString)
    }

    // NSTextField has 2px insets left and right by default; we remove those
    override var alignmentRectInsets: NSEdgeInsets { insets }
}
