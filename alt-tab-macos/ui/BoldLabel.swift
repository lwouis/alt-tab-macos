import Cocoa

class BoldLabel: NSTextField {
    convenience init(_ string: String) {
        self.init(labelWithString: string)
        allowsEditingTextAttributes = true
        attributedStringValue = NSAttributedString(string: string, attributes: [
            NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
        ])
    }
}
