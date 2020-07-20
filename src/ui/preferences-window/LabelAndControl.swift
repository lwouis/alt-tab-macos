import Cocoa
import ShortcutRecorder

enum LabelPosition {
    case leftWithSeparator
    case leftWithoutSeparator
    case right
}

class LabelAndControl: NSObject {
    static func makeLabelWithRecorder(_ labelText: String, _ rawName: String, _ shortcutString: String, _ clearable: Bool = true, labelPosition: LabelPosition = .leftWithSeparator) -> [NSView] {
        let input = CustomRecorderControl(shortcutString, clearable)
        let views = makeLabelWithProvidedControl(labelText, rawName, input, labelPosition: labelPosition, extraAction: GeneralTab.shortcutChangedCallback)
        GeneralTab.shortcutChangedCallback(input)
        return views
    }

    static func makeLabelWithCheckbox(_ labelText: String, _ rawName: String, extraAction: ActionClosure? = nil, labelPosition: LabelPosition = .leftWithSeparator) -> [NSView] {
        let checkbox = NSButton(checkboxWithTitle: labelPosition == .right ? labelText : "", target: nil, action: nil)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.state = (Preferences.getString(rawName)! as NSString).boolValue ? .on : .off
        let views = makeLabelWithProvidedControl(labelText, rawName, checkbox, labelPosition: labelPosition, extraAction: extraAction)
        return views
    }

    static func makeTextArea(_ nCharactersWide: CGFloat, _ nLinesHigh: Int, _ placeholder: String, _ rawName: String, extraAction: ActionClosure? = nil) -> [NSView] {
        let textArea = TextArea(nCharactersWide, nLinesHigh, placeholder)
        textArea.callback = {
            controlWasChanged(textArea)
            extraAction?(textArea)
        }
        textArea.identifier = NSUserInterfaceItemIdentifier(rawName)
        textArea.stringValue = Preferences.getString(rawName)!
        return [textArea]
    }

    static func makeLabelWithDropdown(_ labelText: String, _ rawName: String, _ values: [MacroPreference], _ suffixText: String? = nil) -> [NSView] {
        return makeLabelWithProvidedControl(labelText, rawName, makeDropDown(rawName, values), suffixText)
    }

    static func makeDropDown(_ rawName: String, _ macroPreferences: [MacroPreference]) -> NSPopUpButton {
        let popUp = NSPopUpButton()
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.addItems(withTitles: macroPreferences.map { $0.localizedString })
        popUp.selectItem(at: Int(Preferences.getString(rawName)!)!)
        return popUp
    }

    static func makeLabelWithSlider(_ labelText: String, _ rawName: String, _ minValue: Double, _ maxValue: Double, _ numberOfTickMarks: Int, _ allowsTickMarkValuesOnly: Bool, _ unitText: String = "") -> [NSView] {
        let value = Preferences.getString(rawName)!
        let suffixText = MeasurementFormatter().string(from: Measurement(value: Double(value)!, unit: Unit(symbol: unitText)))
        let slider = NSSlider()
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.stringValue = value
//        slider.numberOfTickMarks = numberOfTickMarks
//        slider.allowsTickMarkValuesOnly = allowsTickMarkValuesOnly
//        slider.tickMarkPosition = .below
        // TODO: update suffix continuously, but only trigger action on mouse release
        slider.isContinuous = true
        return makeLabelWithProvidedControl(labelText, rawName, slider, suffixText)
    }

    static func makeLabelWithProvidedControl(_ labelText: String, _ rawName: String, _ control: NSControl, _ suffixText: String? = nil, _ suffixUrl: String? = nil, labelPosition: LabelPosition = .leftWithSeparator, extraAction: ActionClosure? = nil) -> [NSView] {
        _ = setupControl(control, rawName, extraAction)
        if labelPosition == .right && control is NSButton {
            return [control]
        }
        let label = makeLabel(labelText, labelPosition)
        if labelPosition == .right {
            if let suffixText = suffixText {
                return [control, label, makeSuffix(rawName, suffixText, suffixUrl)]
            }
            return [control, label]
        }
        if let suffixText = suffixText {
            return [label, control, makeSuffix(rawName, suffixText, suffixUrl)]
        }
        return [label, control]
    }

    static func setupControl(_ control: NSControl, _ rawName: String, _ extraAction: ActionClosure? = nil) -> NSControl {
        control.identifier = NSUserInterfaceItemIdentifier(rawName)
        control.onAction = {
            controlWasChanged($0)
            extraAction?($0)
        }
        return control
    }

    static func controlWasChanged(_ senderControl: NSControl) {
        let newValue = LabelAndControl.getControlValue(senderControl)
        LabelAndControl.updateControlExtras(senderControl, newValue)
        Preferences.set(senderControl.identifier!.rawValue, newValue)
        // some preferences require re-creating some components
        if ["iconSize", "fontHeight", "theme", "titleTruncation"].contains(where: { (pref: String) -> Bool in pref == senderControl.identifier!.rawValue }) {
            (App.shared as! App).resetPreferencesDependentComponents()
        }
    }

    static func makeLabel(_ labelText: String, _ labelPosition: LabelPosition = .leftWithoutSeparator) -> NSTextField {
        let label = TextField(labelText)
        label.isSelectable = false
        label.usesSingleLineMode = true
        label.alignment = .right
        return label
    }

    private static func makeSuffix(_ controlName: String, _ text: String, _ url: String? = nil) -> NSTextField {
        let suffix: NSTextField
        if url == nil {
            suffix = NSTextField(labelWithString: text)
        } else {
            suffix = HyperlinkLabel(text, url!)
        }
        suffix.textColor = .gray
        suffix.identifier = NSUserInterfaceItemIdentifier(controlName + ControlIdentifierDiscriminator.SUFFIX.rawValue)
        suffix.fit()
        return suffix
    }

    static func getControlValue(_ control: NSControl) -> String {
        if control is NSPopUpButton {
            return String((control as! NSPopUpButton).indexOfSelectedItem)
        } else if control is NSSlider {
            return String(format: "%.0f", control.doubleValue) // we are only interested in decimals of the provided double
        } else if control is NSButton {
            return String((control as! NSButton).state == NSButton.StateValue.on)
        } else {
            return control.stringValue
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
    case SUFFIX = "_suffix"
}

class TabView: NSTabView {
    // without the left/right value, the whole view is shifted to the right for some reason
//    let insets = NSEdgeInsets(top: 0, left: 7, bottom: 0, right: 7)
//    override var alignmentRectInsets: NSEdgeInsets { get { insets } }

    convenience init() {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }
}
