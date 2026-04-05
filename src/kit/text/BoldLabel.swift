import Cocoa

class BoldLabel: NSTextField {
    convenience init(_ string: String) {
        self.init(labelWithString: string)
        font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        stringValue = string
    }
}
