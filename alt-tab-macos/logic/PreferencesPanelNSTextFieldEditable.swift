import Cocoa

class PreferencesPanelNSTextFieldEditable: NSTextField, NSTextFieldDelegate {

    var validationHandler: ((String)->Bool)?

    // protocol method
    func controlTextDidChange(_ obj: Notification) {
        visualizeValidationState(isValid())
        let textField = obj.object as! PreferencesPanelNSTextFieldEditable
        sendAction(textField.action, to: textField.target)
    }

    // custom method
    func visualizeValidationState(_ isValid: Bool) -> Void {
        if !isValid {
            wantsLayer = true
            layer?.borderColor = NSColor.systemRed.cgColor
            layer?.borderWidth = 1
        } else {
            wantsLayer = false
        }
    }

    // custom method
    func isValid() -> Bool {
        if let handler = validationHandler {
            return handler(stringValue)
        }

        return true
    }

}