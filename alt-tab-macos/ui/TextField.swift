import Cocoa

class TextField: NSTextField, NSTextFieldDelegate {

    var validationHandler: ((String)->Bool)?

    public convenience init(_ value: String) {
        self.init(string: value)
        wantsLayer = true
        layer?.borderWidth = 1
    }

    func controlTextDidChange(_ obj: Notification) {
        visualizeValidationState()
        let textField = obj.object as! TextField
        sendAction(textField.action, to: textField.target)
    }

    func visualizeValidationState() -> Void {
        if !isValid() {
            layer?.borderColor = NSColor.systemRed.cgColor
        } else {
            layer?.borderColor = .clear
        }
    }

    func isValid() -> Bool {
        if let handler = validationHandler {
            return handler(stringValue)
        }

        return true
    }

}