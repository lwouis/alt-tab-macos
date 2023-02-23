import Cocoa
import ShortcutRecorder

enum LabelPosition {
    case leftWithSeparator
    case leftWithoutSeparator
    case right
}

class LabelAndControl: NSObject {
    static func makeLabelWithRecorder(_ labelText: String, _ rawName: String, _ shortcutString: String, _ clearable: Bool = true, labelPosition: LabelPosition = .leftWithSeparator) -> [NSView] {
        let input = CustomRecorderControl(shortcutString, clearable, rawName)
        let views = makeLabelWithProvidedControl(labelText, rawName, input, labelPosition: labelPosition, extraAction: { _ in ControlsTab.shortcutChangedCallback(input) })
        ControlsTab.shortcutChangedCallback(input)
        ControlsTab.shortcutControls[rawName] = (input, labelText)
        return views
    }

    static func makeLabelWithCheckbox(_ labelText: String, _ rawName: String, extraAction: ActionClosure? = nil, labelPosition: LabelPosition = .leftWithSeparator) -> [NSView] {
        let checkbox = NSButton(checkboxWithTitle: labelPosition == .right ? labelText : " ", target: nil, action: nil)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.state = defaults.bool(rawName) ? .on : .off
        let views = makeLabelWithProvidedControl(labelText, rawName, checkbox, labelPosition: labelPosition, extraAction: extraAction)
        return views
    }

    static func makeTextArea(_ nCharactersWide: CGFloat, _ nLinesHigh: Int, _ placeholder: String, _ rawName: String, extraAction: ActionClosure? = nil) -> [NSView] {
        let textArea = TextArea(nCharactersWide, nLinesHigh, placeholder)
        textArea.callback = {
            controlWasChanged(textArea, nil)
            extraAction?(textArea)
        }
        textArea.identifier = NSUserInterfaceItemIdentifier(rawName)
        textArea.stringValue = defaults.string(rawName)
        return [textArea]
    }

    static func makeLabelWithDropdown(_ labelText: String, _ rawName: String, _ values: [MacroPreference], _ suffixText: String? = nil, extraAction: ActionClosure? = nil) -> [NSView] {
        return makeLabelWithProvidedControl(labelText, rawName, dropdown_(rawName, values), suffixText, extraAction: extraAction)
    }

    static func dropdown_(_ rawName: String, _ macroPreferences: [MacroPreference]) -> NSPopUpButton {
        let popUp = NSPopUpButton()
        popUp.translatesAutoresizingMaskIntoConstraints = false
        popUp.addItems(withTitles: macroPreferences.map { $0.localizedString })
        popUp.selectItem(at: defaults.int(rawName))
        return popUp
    }

    static func makeDropdown(_ rawName: String, _ macroPreferences: [MacroPreference]) -> NSControl {
        let dropdown = dropdown_(rawName, macroPreferences)
        return setupControl(dropdown, rawName)
    }

    static func makeRadioButtons(_ macroPreferences: [MacroPreference], _ rawName: String, extraAction: ActionClosure? = nil) -> [NSButton] {
        var i = 0
        return macroPreferences.map {
            let button = NSButton(radioButtonWithTitle: $0.localizedString, target: nil, action: nil)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.state = defaults.int(rawName) == i ? .on : .off
            _ = setupControl(button, rawName, String(i), extraAction: extraAction)
            i += 1
            return button
        }
    }

    static func makeLabelWithSlider(_ labelText: String, _ rawName: String, _ minValue: Double, _ maxValue: Double, _ numberOfTickMarks: Int, _ allowsTickMarkValuesOnly: Bool, _ unitText: String = "", extraAction: ActionClosure? = nil) -> [NSView] {
        let value = defaults.double(rawName)
        let formatter = MeasurementFormatter()
        formatter.numberFormatter = NumberFormatter()
        let suffixText = formatter.string(from: Measurement(value: value, unit: Unit(symbol: unitText)))
        let slider = NSSlider()
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.stringValue = String(value)
        slider.isContinuous = true
        return makeLabelWithProvidedControl(labelText, rawName, slider, suffixText, extraAction: extraAction)
    }

    static func makeLabelWithProvidedControl(_ labelText: String, _ rawName: String, _ control: NSControl, _ suffixText: String? = nil, _ suffixUrl: String? = nil, labelPosition: LabelPosition = .leftWithSeparator, extraAction: ActionClosure? = nil) -> [NSView] {
        _ = setupControl(control, rawName, extraAction: extraAction)
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

    static func setupControl(_ control: NSControl, _ rawName: String, _ controlId: String? = nil, extraAction: ActionClosure? = nil) -> NSControl {
        control.identifier = NSUserInterfaceItemIdentifier(rawName)
        control.onAction = {
            controlWasChanged($0, controlId)
            extraAction?($0)
        }
        return control
    }

    static func controlWasChanged(_ senderControl: NSControl, _ controlId: String?) {
        if let newValue = LabelAndControl.getControlValue(senderControl, controlId) {
            if senderControl is NSSlider {
                updateSuffixWithValue(senderControl as! NSSlider, newValue)
            }
            Preferences.set(senderControl.identifier!.rawValue, newValue)
        }
        // some preferences require re-creating some components
        if (!(senderControl is NSSlider) || (NSEvent.pressedMouseButtons & (1 << 0)) == 0) &&
               (["iconSize", "fontHeight", "theme", "titleTruncation"].contains { (pref: String) -> Bool in
                   pref == senderControl.identifier!.rawValue
               }) {
            (App.shared as! App).resetPreferencesDependentComponents()
        }
    }

    static func makeLabel(_ labelText: String, _ labelPosition: LabelPosition = .leftWithoutSeparator, shouldFit: Bool = true) -> NSTextField {
        let label = TextField(labelText)
        label.isSelectable = false
        label.usesSingleLineMode = true
        label.alignment = .right
        if shouldFit {
            label.fit()
        }
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

    static func getControlValue(_ control: NSControl, _ controlId: String?) -> String? {
        if control is NSPopUpButton {
            return String((control as! NSPopUpButton).indexOfSelectedItem)
        } else if control is NSSlider {
            return String(format: "%.0f", control.doubleValue) // we are only interested in decimals of the provided double
        } else if control is NSButton {
            if let controlId = controlId {
                return ((control as! NSButton).state == NSButton.StateValue.on) ? controlId : nil
            } else {
                return String((control as! NSButton).state == NSButton.StateValue.on)
            }
        } else {
            return control.stringValue
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

class TabView: NSTabView, NSTabViewDelegate {
    // removing insets fixes a bug where tab views shift to the right and bottom by 7px when switching to tab #2
    let insets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    override var alignmentRectInsets: NSEdgeInsets { get { insets } }

    // workaround: this is the only I found to have NSTabView fittingSize be correct
    override var intrinsicContentSize: NSSize {
        get {
            NSSize(width: selectedTabViewItem!.view!.fittingSize.width + TabView.padding * 2,
                height: selectedTabViewItem!.view!.fittingSize.height + TabView.padding * 2 + subviews[0].frame.height)
        }
    }

    static let padding = CGFloat(7)

    convenience init(_ labelsAndViews: [(String, NSView)]) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        labelsAndViews.enumerated().forEach { (i, tuple) in
            let containerView = NSView()
            containerView.addSubview(tuple.1)
            containerView.widthAnchor.constraint(greaterThanOrEqualTo: tuple.1.widthAnchor).isActive = true
            containerView.heightAnchor.constraint(greaterThanOrEqualTo: tuple.1.heightAnchor).isActive = true
            let tab = NSTabViewItem(identifier: i)
            tab.label = tuple.0
            tab.view = containerView
            addTabViewItem(tab)
            tuple.1.fit()
        }
    }
}
