import Cocoa
import ShortcutRecorder

enum LabelPosition {
    case leftWithSeparator
    case leftWithoutSeparator
    case right
}

typealias EventClosure = (NSEvent, NSView) -> Void

class MouseHoverView: NSView {
    var onMouseEntered: EventClosure?
    var onMouseExited: EventClosure?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        let newTrackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(newTrackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?(event, self)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?(event, self)
    }
}

class ClickHoverImageView: MouseHoverView {
    var infoCircle: NSView!
    var onClick: EventClosure?

    init(infoCircle: NSView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        self.infoCircle = infoCircle
        addSubview(infoCircle)
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        addGestureRecognizer(clickGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    @objc private func handleClick(_ sender: NSClickGestureRecognizer) {
        if let event = sender.view?.window?.currentEvent {
            onClick?(event, self)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

class LabelAndControl: NSObject {
    // periphery:ignore
    static func makeLabelWithImageRadioButtons(_ labelText: String,
                                               _ rawName: String,
                                               _ macroPreferences: [ImageMacroPreference],
                                               extraAction: ActionClosure? = nil,
                                               buttonSpacing: CGFloat = 15) -> [NSView] {
        let view = makeImageRadioButtons(rawName, macroPreferences, extraAction: extraAction, buttonSpacing: buttonSpacing)
        return [makeLabel(labelText), view]
    }

    static func makeImageRadioButtons(_ rawName: String,
                                      _ macroPreferences: [ImageMacroPreference],
                                      extraAction: ActionClosure? = nil,
                                      buttonSpacing: CGFloat = 15) -> NSStackView {
        var buttons = [ImageTextButtonView]()
        let buttonViews = macroPreferences.enumerated().map { (index, preference) -> ImageTextButtonView in
            let state: NSControl.StateValue = CachedUserDefaults.intFromMacroPref(rawName, macroPreferences) == index ? .on : .off
            let buttonView = ImageTextButtonView(title: preference.localizedString, rawName: rawName, image: preference.image, state: state)
            buttons.append(buttonView)
            buttonView.onClick = { control in
                buttons.enumerated().forEach { (i, otherButtonView) in
                    if otherButtonView != buttonView {
                        otherButtonView.state = i == index ? .on : .off
                    }
                }
                controlWasChanged(buttonView.button, String(index))
                extraAction?(buttonView.button)
            }
            return buttonView
        }
        let view = NSStackView(views: buttonViews)
        view.orientation = .horizontal
        view.spacing = buttonSpacing
        view.alignment = .centerY
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

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
        checkbox.state = CachedUserDefaults.bool(rawName) ? .on : .off
        let views = makeLabelWithProvidedControl(labelText, rawName, checkbox, labelPosition: labelPosition, extraAction: extraAction)
        return views
    }

    static func makeSwitch(_ rawName: String, extraAction: ActionClosure? = nil) -> Switch {
        let button = Switch(CachedUserDefaults.bool(rawName))
        _ = setupControl(button, rawName, extraAction: extraAction)
        return button
    }

    // periphery:ignore
    static func makeCheckbox(_ rawName: String, extraAction: ActionClosure? = nil) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        checkbox.state = CachedUserDefaults.bool(rawName) ? .on : .off
        _ = setupControl(checkbox, rawName, extraAction: extraAction)
        return checkbox
    }

    static func makeInfoButton(size: CGFloat = 16,
                               onClick: EventClosure? = nil,
                               onMouseEntered: EventClosure? = nil,
                               onMouseExited: EventClosure? = nil) -> ClickHoverImageView {
        let imageView = ThumbnailFontIconView(symbol: .circledInfo, size: size, color: .labelColor)
        let view = ClickHoverImageView(infoCircle: imageView)
        view.onClick = onClick
        view.onMouseEntered = onMouseEntered
        view.onMouseExited = onMouseExited
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        return view
    }

    // periphery:ignore
    static func makeLabelWithCheckboxAndInfoButton(_ labelText: String,
                                                   _ rawName: String,
                                                   extraAction: ActionClosure? = nil,
                                                   labelPosition: LabelPosition = .leftWithSeparator,
                                                   onClick: EventClosure? = nil,
                                                   onMouseEntered: EventClosure? = nil,
                                                   onMouseExited: EventClosure? = nil,
                                                   size: CGFloat = 15) -> [NSView] {
        let labelCheckboxViews = makeLabelWithCheckbox(labelText, rawName, extraAction: extraAction, labelPosition: labelPosition)
        let infoButtonView = makeInfoButton(size: size, onClick: onClick, onMouseEntered: onMouseEntered, onMouseExited: onMouseExited)
        var views: [NSView] = []
        labelCheckboxViews.forEach { view in
            views.append(view)
        }
        views.append(infoButtonView)
        let hStack = NSStackView(views: views)
        hStack.orientation = .horizontal
        hStack.spacing = 8
        hStack.alignment = .centerY
        hStack.translatesAutoresizingMaskIntoConstraints = false
        return [hStack]
    }

    // periphery:ignore
    static func makeTextArea(_ nCharactersWide: CGFloat, _ nLinesHigh: Int, _ placeholder: String, _ rawName: String, extraAction: ActionClosure? = nil) -> [NSView] {
        let textArea = TextArea(nCharactersWide, nLinesHigh, placeholder)
        textArea.callback = {
            controlWasChanged(textArea, nil)
            extraAction?(textArea)
        }
        textArea.identifier = NSUserInterfaceItemIdentifier(rawName)
        textArea.stringValue = CachedUserDefaults.string(rawName)
        return [textArea]
    }

    static func dropdown_(_ rawName: String, _ macroPreferences: [MacroPreference]) -> NSPopUpButton {
        let popUp = PopupButtonLikeSystemSettings()
        popUp.addItems(withTitles: macroPreferences.map {
            $0.localizedString
        })
        popUp.selectItem(at: CachedUserDefaults.intFromMacroPref(rawName, macroPreferences))
        return popUp
    }

    static func makeDropdown(_ rawName: String, _ macroPreferences: [MacroPreference], extraAction: ActionClosure? = nil) -> NSPopUpButton {
        let dropdown = dropdown_(rawName, macroPreferences)
        return setupControl(dropdown, rawName, extraAction: extraAction) as! NSPopUpButton
    }

    // periphery:ignore
    static func makeLabelWithRadioButtons(_ labelText: String,
                                          _ rawName: String,
                                          _ values: [MacroPreference],
                                          extraAction: ActionClosure? = nil,
                                          buttonSpacing: CGFloat = 30) -> [NSView] {
        let buttons = makeRadioButtons(rawName, values, extraAction: extraAction)
        let horizontalStackView = NSStackView(views: buttons)
        horizontalStackView.translatesAutoresizingMaskIntoConstraints = false
        horizontalStackView.orientation = .horizontal
        horizontalStackView.spacing = buttonSpacing
        horizontalStackView.alignment = .centerY
        horizontalStackView.translatesAutoresizingMaskIntoConstraints = false
        return [makeLabel(labelText), horizontalStackView]
    }

    static func makeRadioButtons(_ rawName: String, _ macroPreferences: [MacroPreference], extraAction: ActionClosure? = nil) -> [NSButton] {
        var i = 0
        return macroPreferences.map {
            let button = NSButton(radioButtonWithTitle: $0.localizedString, target: nil, action: nil)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.state = CachedUserDefaults.intFromMacroPref(rawName, macroPreferences) == i ? .on : .off
            _ = setupControl(button, rawName, String(i), extraAction: extraAction)
            i += 1
            return button
        }
    }

    static func makeSegmentedControl(_ rawName: String, _ macroPreferences: [MacroPreference], segmentWidth: CGFloat = -1, extraAction: ActionClosure? = nil) -> NSSegmentedControl {
        let button = NSSegmentedControl(labels: macroPreferences.map {
            $0.localizedString
        }, trackingMode: .selectOne, target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.segmentStyle = .automatic
        for (i, preference) in macroPreferences.enumerated() {
            if segmentWidth > 0 {
                button.setWidth(segmentWidth, forSegment: i)
            }
            if #available(macOS 11.0, *) {
                if let preference = preference as? SfSymbolMacroPreference,
                   // each systemSymbolName has a different minimum macOS requirements; we need to make sure it exists
                   let symbolImage = NSImage(systemSymbolName: preference.symbolName, accessibilityDescription: nil) {
                    button.setImage(symbolImage, forSegment: i)
                }
            }
            let selectedSegment = CachedUserDefaults.intFromMacroPref(rawName, macroPreferences)
            if selectedSegment >= 0 && selectedSegment < macroPreferences.count {
                button.selectedSegment = selectedSegment
            }
            _ = setupControl(button, rawName, String(i), extraAction: extraAction)
        }
        return button
    }

    static func makeLabelWithSlider(_ labelText: String, _ rawName: String, _ minValue: Double, _ maxValue: Double,
                                    _ numberOfTickMarks: Int = 0, _ allowsTickMarkValuesOnly: Bool = false,
                                    _ unitText: String = "", width: CGFloat = 200, extraAction: ActionClosure? = nil) -> [NSView] {
        let value = CachedUserDefaults.int(rawName)
        let formatter = MeasurementFormatter()
        formatter.numberFormatter = NumberFormatter()
        let suffixText = formatter.string(from: Measurement(value: Double(value), unit: Unit(symbol: unitText)))
        let slider = NSSlider()
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.stringValue = String(value)
        slider.isContinuous = true
        if numberOfTickMarks > 0 {
            slider.numberOfTickMarks = numberOfTickMarks
        }
        slider.allowsTickMarkValuesOnly = allowsTickMarkValuesOnly
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addOrUpdateConstraint(slider.widthAnchor, width)
        return makeLabelWithProvidedControl(labelText, rawName, slider, suffixText, extraAction: extraAction)
    }

    static func makeLabelWithProvidedControl(_ labelText: String, _ rawName: String, _ control: NSControl,
                                             _ suffixText: String? = nil, labelPosition: LabelPosition = .leftWithSeparator,
                                             extraAction: ActionClosure? = nil) -> [NSView] {
        _ = setupControl(control, rawName, extraAction: extraAction)
        if labelPosition == .right && control is NSButton {
            return [control]
        }
        let label = makeLabel(labelText)
        if labelPosition == .right {
            if let suffixText {
                return [control, label, makeSuffix(rawName, suffixText)]
            }
            return [control, label]
        }
        if let suffixText {
            return [label, control, makeSuffix(rawName, suffixText)]
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
            if let oldValue = UserDefaults.standard.string(forKey: senderControl.identifier!.rawValue), newValue == oldValue {
                return
            }
            if senderControl is NSSlider {
                updateSuffixWithValue(senderControl as! NSSlider, newValue)
            }
            Preferences.set(senderControl.identifier!.rawValue, newValue)
        }
        // some preferences require re-creating some components
        if (!(senderControl is NSSlider) || (NSEvent.pressedMouseButtons & (1 << 0)) == 0) &&
               (["appearanceStyle", "appearanceSize", "appearanceTheme", "showOnScreen", "showAppsOrWindows"].contains { (pref: String) -> Bool in
                   pref == senderControl.identifier!.rawValue
               }) {
            (App.shared as! App).resetPreferencesDependentComponents()
        }
    }

    static func makeLabel(_ labelText: String, shouldFit: Bool = true) -> NSTextField {
        let label = TextField(labelText)
        label.isSelectable = false
        label.usesSingleLineMode = true
        label.alignment = .right
        if shouldFit {
            label.fit()
        }
        return label
    }

    private static func makeSuffix(_ controlName: String, _ text: String) -> NSTextField {
        let suffix = NSTextField(labelWithString: text)
        suffix.textColor = .gray
        suffix.identifier = NSUserInterfaceItemIdentifier(controlName + ControlIdentifierDiscriminator.SUFFIX.rawValue)
        return suffix
    }

    static func getControlValue(_ control: NSControl, _ controlId: String?) -> String? {
        if control is NSPopUpButton {
            return String((control as! NSPopUpButton).indexOfSelectedItem)
        } else if control is NSSlider {
            return String(format: "%.0f", control.doubleValue) // we are only interested in decimals of the provided double
        } else if control is NSButton {
            if let controlId {
                return ((control as! NSButton).state == NSButton.StateValue.on) ? controlId : nil
            } else {
                return String((control as! NSButton).state == NSButton.StateValue.on)
            }
        } else if control is Switch {
            if let controlId {
                return ((control as! Switch).state == NSButton.StateValue.on) ? controlId : nil
            } else {
                return String((control as! Switch).state == NSButton.StateValue.on)
            }
        } else if control is NSSegmentedControl {
            return String((control as! NSSegmentedControl).selectedSegment)
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
