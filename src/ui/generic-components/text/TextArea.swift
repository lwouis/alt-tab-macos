import Cocoa

class TextArea: NSTextField, NSTextFieldDelegate {
    static let padding = CGFloat(5)
    static let interLineFactor = CGFloat(1.6)
    var callback: (() -> Void)!

    convenience init(_ nCharactersWide: CGFloat, _ nLinesHigh: Int, _ placeholder: String, _ callback: (() -> Void)? = nil) {
        self.init(frame: .zero)
        self.callback = callback
        delegate = self
        cell = TextFieldCell(placeholder, nLinesHigh == 1)
        let width: CGFloat = (font!.xHeight * nCharactersWide + TextArea.padding * 2).rounded()
        let height: CGFloat = (NSFont.systemFontSize * TextArea.interLineFactor * CGFloat(nLinesHigh) + TextArea.padding * 2).rounded()
        fit(width, height)
    }

    func controlTextDidChange(_ notification: Notification) {
        callback?()
    }

    // enter key inserts new line instead of submitting
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline) else { return false }
        textView.insertNewlineIgnoringFieldEditor(self)
        return true
    }
}

// subclassing NSTextFieldCell is done uniquely to add padding
class TextFieldCell: NSTextFieldCell {
    convenience init(_ placeholder: String, _ usesSingleLineMode: Bool) {
        self.init()
        isBordered = true
        isBezeled = true
        isEditable = true
        font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        stringValue = ""
        placeholderString = placeholder
        self.usesSingleLineMode = usesSingleLineMode
        alignment = .natural // appkit bug: the docs say default is .natural but it's .left
    }

    // add padding all around
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        return super.drawingRect(forBounds: NSMakeRect(
                rect.origin.x + TextArea.padding,
                rect.origin.y + TextArea.padding,
                rect.size.width - TextArea.padding * 2,
                rect.size.height - TextArea.padding * 2
        ))
    }
}
