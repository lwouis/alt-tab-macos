import Cocoa

class TitleLabel: NSTextField {
    convenience init(_ string: String) {
        self.init(wrappingLabelWithString: string)
        font = .systemFont(ofSize: NSFont.labelFontSize * 2)
        stringValue = string
    }
}
