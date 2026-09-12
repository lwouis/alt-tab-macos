import Cocoa

class TextField: NSTextField {
    // NSTextField has 2px insets left and right by default; we remove those
    let insets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    override var alignmentRectInsets: NSEdgeInsets { insets }

    convenience init(_ labelWithString: String) {
        self.init(labelWithString: labelWithString)
        translatesAutoresizingMaskIntoConstraints = false
    }
}
