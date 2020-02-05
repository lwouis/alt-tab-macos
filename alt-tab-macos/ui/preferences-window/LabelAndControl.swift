import Cocoa
import Foundation

class LabelAndControl: NSObject {
    static var callbackTarget: PreferencesWindow!

    static func makeLabelWithInput(_ labelText: String, _ rawName: String, _ width: CGFloat, _ suffixText: String? = nil, _ suffixUrl: String? = nil, _ validator: ((String) -> Bool)? = nil) -> [NSView] {
        let input = TextField(Preferences.rawValues[rawName]!)
        input.validationHandler = validator
        input.delegate = input
        input.visualizeValidationState()
        input.fit(width, input.fittingSize.height)
        let views = makeLabelWithProvidedControl(labelText, rawName, input)
        return [views[0], NSStackView(views: [views[1], makeSuffix(rawName, suffixText!, suffixUrl)])]
    }

    static func makeLabelWithCheckbox(_ labelText: String, _ rawName: String) -> [NSView] {
        let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        setControlValue(checkbox, Preferences.rawValues[rawName]!)
        return makeLabelWithProvidedControl(labelText, rawName, checkbox)
    }

    static func makeLabelWithDropdown(_ labelText: String, _ rawName: String, _ values: [String], _ suffixText: String? = nil) -> [NSView] {
        let popUp = NSPopUpButton()
        popUp.addItems(withTitles: values)
        popUp.selectItem(withTitle: Preferences.rawValues[rawName]!)
        return makeLabelWithProvidedControl(labelText, rawName, popUp, suffixText)
    }

    static func makeLabelWithSlider(_ labelText: String, _ rawName: String, _ minValue: Double, _ maxValue: Double, _ numberOfTickMarks: Int, _ allowsTickMarkValuesOnly: Bool, _ unitText: String = "") -> [NSView] {
        let value = Preferences.rawValues[rawName]!
        let suffixText = value + " " + unitText
        let slider = NSSlider()
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.stringValue = value
//        slider.numberOfTickMarks = numberOfTickMarks
//        slider.allowsTickMarkValuesOnly = allowsTickMarkValuesOnly
//        slider.tickMarkPosition = .below
        slider.isContinuous = true
        return makeLabelWithProvidedControl(labelText, rawName, slider, suffixText)
    }

    static func makeLabelWithProvidedControl(_ labelText: String?, _ rawName: String, _ control: NSControl, _ suffixText: String? = nil, _ suffixUrl: String? = nil) -> [NSView] {
        let label = makeLabel(labelText, rawName)
        control.identifier = NSUserInterfaceItemIdentifier(rawName)
        control.target = self
        control.action = #selector(controlWasChanged)
        return [label, control, suffixText != nil ? makeSuffix(rawName, suffixText!, suffixUrl) : NSView()]
    }

    @objc
    static func controlWasChanged(senderControl: NSControl) {
        callbackTarget.controlWasChanged(senderControl)
    }

    private static func makeLabel(_ labelText: String?, _ rawName: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: labelText != nil ? labelText! + ": " : "")
        label.fit()
        label.alignment = .right
        label.identifier = NSUserInterfaceItemIdentifier(rawName + ControlIdentifierDiscriminator.LABEL.rawValue)
        return label
    }

    private static func makeSuffix(_ controlName: String, _ text: String, _ url: String? = nil) -> NSTextField {
        let suffix: NSTextField
        if url == nil {
            suffix = NSTextField(labelWithString: text)
        } else {
            suffix = HyperlinkLabel(text, NSURL(string: url!)!)
        }
        suffix.textColor = .gray
        suffix.identifier = NSUserInterfaceItemIdentifier(controlName + ControlIdentifierDiscriminator.SUFFIX.rawValue)
        suffix.fit()
        return suffix
    }



    static func getControlValue(_ control: NSControl) -> String {
        if control is NSPopUpButton {
            return (control as! NSPopUpButton).titleOfSelectedItem!
        } else if control is NSSlider {
            return String(format: "%.0f", control.doubleValue) // we are only interested in decimals of the provided double
        } else if control is NSButton {
            return String((control as! NSButton).state == NSButton.StateValue.on)
        } else {
            return control.stringValue
        }
    }

    static func setControlValue(_ control: NSControl, _ value: String) {
        if control is NSPopUpButton {
            (control as! NSPopUpButton).selectItem(withTitle: value)
        } else if control is NSTextField {
            control.stringValue = value
            (control as! NSTextField).delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: control))
        } else if control is NSButton {
            (control as! NSButton).state = Bool(value) ?? false ? NSButton.StateValue.on : NSButton.StateValue.off
        } else {
            control.stringValue = value
        }
    }

    static func updateControlExtras(_ control: NSControl, _ value: String) {
        if control is NSSlider {
            updateSuffixWithValue(control as! NSSlider, value)
        }
    }



    private static func updateSuffixWithValue(_ control: NSControl, _ value: String) {
        let suffixIdentifierPredicate = { (view: NSView) -> Bool in
            view.identifier?.rawValue == control.identifier!.rawValue + ControlIdentifierDiscriminator.SUFFIX.rawValue
        }

        if let suffixView: NSTextField = control.superview?.subviews.first(where: suffixIdentifierPredicate) as? NSTextField {
            let regex = try! NSRegularExpression(pattern: "^[0-9]+") // first decimal
            let range = NSMakeRange(0, suffixView.stringValue.count)
            suffixView.stringValue = regex.stringByReplacingMatches(in: suffixView.stringValue, range: range, withTemplate: value)
        }
    }
}

enum ControlIdentifierDiscriminator: String {
    case LABEL = "_label"
    case SUFFIX = "_suffix"
}
