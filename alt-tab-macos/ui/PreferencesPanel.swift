import Cocoa
import Foundation

class PreferencesPanel: NSPanel, NSWindowDelegate {
    let panelWidth = CGFloat(496)
    let panelHeight = CGFloat(256) // auto expands to content height (but does not auto shrink)
    let panelPadding = CGFloat(40)
    var labelWidth: CGFloat {
        return (panelWidth - panelPadding) * CGFloat(0.45)
    }
    var windowCloseRequested = false

    override init(contentRect: NSRect, styleMask style: StyleMask, backing backingStoreType: BackingStoreType, defer flag: Bool) {
        let initialRect = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        super.init(contentRect: initialRect, styleMask: style, backing: backingStoreType, defer: flag)
        title = Application.name + " Preferences"
        hidesOnDeactivate = false
        contentView = makeContentView()
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        windowCloseRequested = true
        challengeNextInvalidEditableTextField()
        return attachedSheet == nil // depends if user is challenged with a sheet
    }

    private func challengeNextInvalidEditableTextField() {
        let invalidFields = (contentView?
                .findNestedViews(subclassOf: TextField.self)
                .filter({ !$0.isValid() })
        )
        let focusedField = invalidFields?.filter({ $0.currentEditor() != nil }).first
        let fieldToNotify = focusedField ?? invalidFields?.first
        fieldToNotify?.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: fieldToNotify))

        if fieldToNotify != focusedField {
            makeFirstResponder(fieldToNotify)
        }
    }

    private func makeContentView() -> NSView {
        let wrappingView = NSStackView(views: makePreferencesViews())
        let contentView = NSView()
        contentView.addSubview(wrappingView)

        // visual setup
        wrappingView.orientation = .vertical
        wrappingView.alignment = .left
        wrappingView.spacing = panelPadding * 0.3
        wrappingView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: panelPadding * 0.5).isActive = true
        wrappingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: panelPadding * -0.5).isActive = true
        wrappingView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: panelPadding * 0.5).isActive = true
        wrappingView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: panelPadding * -0.5).isActive = true

        return contentView
    }

    private func makePreferencesViews() -> [NSView] {
        // TODO: make the validators be a part of each Preference
        let tabKeyCodeValidator: ((String) -> Bool) = {
            guard let int = Int($0) else {
                return false
            }
            // non-special keys (mac & pc keyboards): https://eastmanreference.com/complete-list-of-applescript-key-codes
            var whitelistedKeycodes: [Int] = Array(0...53)
            whitelistedKeycodes.append(contentsOf: [65, 67, 69, 75, 76, 78, ])
            whitelistedKeycodes.append(contentsOf: Array(81...89))
            whitelistedKeycodes.append(contentsOf: [91, 92, 115, 116, 117, 119, 121])
            whitelistedKeycodes.append(contentsOf: Array(123...126))
            return whitelistedKeycodes.contains(int)
        }

        return [
            makeLabelWithDropdown("Alt key", rawName: "metaKey", values: Preferences.metaKeyMacro.labels),
            makeLabelWithInput("Tab key", rawName: "tabKeyCode", width: 33, suffixText: "KeyCodes Reference", suffixUrl: "https://eastmanreference.com/complete-list-of-applescript-key-codes", validator: tabKeyCodeValidator),
            makeHorizontalSeparator(),
            makeLabelWithDropdown("Theme", rawName: "theme", values: Preferences.themeMacro.labels),
            makeLabelWithSlider("Max screen usage", rawName: "maxScreenUsage", minValue: 10, maxValue: 100, numberOfTickMarks: 0, unitText: "%"),
            makeLabelWithSlider("Max thumbnails per row", rawName: "maxThumbnailsPerRow", minValue: 3, maxValue: 16, numberOfTickMarks: 0),
            makeLabelWithSlider("Apps icon size", rawName: "iconSize", minValue: 12, maxValue: 64, numberOfTickMarks: 0, unitText: "px"),
            makeLabelWithSlider("Window font size", rawName: "fontHeight", minValue: 12, maxValue: 64, numberOfTickMarks: 0, unitText: "px"),
            makeLabelWithCheckbox("Hide space number labels", rawName: "hideSpaceNumberLabels"),
            makeHorizontalSeparator(),
            makeLabelWithSlider("Window apparition delay", rawName: "windowDisplayDelay", minValue: 0, maxValue: 2000, numberOfTickMarks: 0, unitText: "ms"),
            makeLabelWithDropdown("Show on", rawName: "showOnScreen", values: Preferences.showOnScreenMacro.labels)
        ]
    }

    private func makeHorizontalSeparator() -> NSView {
        let view = NSBox()
        view.boxType = .separator

        return view
    }

    private func makeLabelWithInput(_ labelText: String, rawName: String, width: CGFloat? = nil, suffixText: String? = nil, suffixUrl: String? = nil, validator: ((String) -> Bool)? = nil) -> NSStackView {
        let input = TextField(Preferences.rawValues[rawName]!)
        input.validationHandler = validator
        input.delegate = input
        input.visualizeValidationState()
        if width != nil {
            input.widthAnchor.constraint(equalToConstant: width!).isActive = true
        }

        return makeLabelWithProvidedControl(labelText, rawName: rawName, control: input, suffixText: suffixText, suffixUrl: suffixUrl)
    }

    private func makeLabelWithCheckbox(_ labelText: String, rawName: String) -> NSStackView {
        let checkbox = NSButton.init(checkboxWithTitle: "", target: nil, action: nil)
        setControlValue(checkbox, Preferences.rawValues[rawName]!)
        return makeLabelWithProvidedControl(labelText, rawName: rawName, control: checkbox)
    }

    private func makeLabelWithDropdown(_ labelText: String, rawName: String, values: [String], suffixText: String? = nil) -> NSStackView {
        let popUp = NSPopUpButton()
        popUp.addItems(withTitles: values)
        popUp.selectItem(withTitle: Preferences.rawValues[rawName]!)

        return makeLabelWithProvidedControl(labelText, rawName: rawName, control: popUp, suffixText: suffixText)
    }

    private func makeLabelWithSlider(_ labelText: String, rawName: String, minValue: Double, maxValue: Double, numberOfTickMarks: Int, unitText: String = "") -> NSStackView {
        let value = Preferences.rawValues[rawName]!
        let suffixText = value + unitText
        let slider = NSSlider()
        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.stringValue = value
        slider.numberOfTickMarks = numberOfTickMarks
        slider.allowsTickMarkValuesOnly = numberOfTickMarks > 1
        slider.tickMarkPosition = .below
        slider.isContinuous = true

        return makeLabelWithProvidedControl(labelText, rawName: rawName, control: slider, suffixText: suffixText, suffixWidth: 60)
    }

    private func makeLabelWithProvidedControl(_ labelText: String?, rawName: String, control: NSControl, suffixText: String? = nil, suffixWidth: CGFloat? = nil, suffixUrl: String? = nil) -> NSStackView {
        let label = NSTextField(wrappingLabelWithString: (labelText != nil ? labelText! + ": " : ""))
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        label.identifier = NSUserInterfaceItemIdentifier(rawName + ControlIdentifierDiscriminator.LABEL.rawValue)
        label.isSelectable = false

        control.identifier = NSUserInterfaceItemIdentifier(rawName)
        control.target = self
        control.action = #selector(controlWasChanged)
        let containerView = NSStackView(views: [label, control])

        if suffixText != nil {
            let suffix = makeSuffix(controlName: rawName, text: suffixText!, width: suffixWidth, url: suffixUrl)
            containerView.addView(suffix, in: .leading)
        }

        return containerView
    }

    private func makeSuffix(controlName: String, text: String, width: CGFloat? = nil, url: String? = nil) -> NSTextField {
        let suffix: NSTextField
        if url == nil {
            suffix = NSTextField(labelWithString: text)
        } else {
            suffix = HyperlinkLabel(labelWithUrl: text, nsUrl: NSURL(string: url!)!)
        }
        suffix.textColor = .gray
        suffix.identifier = NSUserInterfaceItemIdentifier(controlName + ControlIdentifierDiscriminator.SUFFIX.rawValue)
        if width != nil {
            suffix.widthAnchor.constraint(equalToConstant: width!).isActive = true
        }

        return suffix
    }

    private func updateSuffixWithValue(_ control: NSControl, _ value: String) {
        let suffixIdentifierPredicate = { (view: NSView) -> Bool in
            view.identifier?.rawValue == control.identifier!.rawValue + ControlIdentifierDiscriminator.SUFFIX.rawValue
        }

        if let suffixView: NSTextField = control.superview?.subviews.first(where: suffixIdentifierPredicate) as? NSTextField {
            let regex = try! NSRegularExpression(pattern: "^[0-9]+") // first decimal
            let range = NSMakeRange(0, suffixView.stringValue.count)
            suffixView.stringValue = regex.stringByReplacingMatches(in: suffixView.stringValue, range: range, withTemplate: value)
        }
    }

    @objc
    private func controlWasChanged(senderControl: NSControl) {
        let key: String = senderControl.identifier!.rawValue
        let previousValue: String = Preferences.rawValues[key]!
        let newValue: String = getControlValue(senderControl)
        let invalidTextField = senderControl is TextField && !(senderControl as! TextField).isValid()

        if (invalidTextField && !windowCloseRequested) || (newValue == previousValue && !invalidTextField) {
            return
        }

        updateControlExtras(senderControl, newValue)

        do {
            // TODO: remove conditional as soon a Preference does validation on its own
            if invalidTextField && windowCloseRequested {
                throw NSError.make(domain: "Preferences", message: "Please enter a valid value for '" + key + "'")
            }
            try Preferences.updateAndValidateFromString(key, newValue)
            (NSApp as! Application).initPreferencesDependentComponents()
            try Preferences.saveRawToDisk()
        } catch let error {
            debugPrint("PreferencesPanel: save: error", key, newValue, error)
            showSaveErrorSheetModal(error as NSError, senderControl, key, previousValue) // allows recursive call by user choice
        }
    }

    private func showSaveErrorSheetModal(_ nsError: NSError, _ control: NSControl, _ key: String, _ previousValue: String) {
        let alert = NSAlert()
        alert.messageText = "Could not save Preference"
        alert.informativeText = nsError.localizedDescription + "\n"
        alert.addButton(withTitle: "Edit")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Check again")

        alert.beginSheetModal(for: self, completionHandler: { (modalResponse: NSApplication.ModalResponse) -> Void in
            if modalResponse == NSApplication.ModalResponse.alertFirstButtonReturn {
                debugPrint("PreferencesPanel: save: error: user choice: edit")
                self.windowCloseRequested = false
            }
            if modalResponse == NSApplication.ModalResponse.alertSecondButtonReturn {
                debugPrint("PreferencesPanel: save: error: user choice: cancel -> revert value and eventually close window")
                try! Preferences.updateAndValidateFromString(key, previousValue)
                self.setControlValue(control, previousValue)
                self.updateControlExtras(control, previousValue)
                if self.windowCloseRequested {
                    self.close()
                }
            }
            if modalResponse == NSApplication.ModalResponse.alertThirdButtonReturn {
                debugPrint("PreferencesPanel: save: error: user choice: check again")
                self.controlWasChanged(senderControl: control)
            }
        })
    }

    private func getControlValue(_ control: NSControl) -> String {
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

    private func setControlValue(_ control: NSControl, _ value: String) {
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

    private func updateControlExtras(_ control: NSControl, _ value: String) {
        if control is NSSlider {
            updateSuffixWithValue(control as! NSSlider, value)
        }
    }
}

enum ControlIdentifierDiscriminator: String {
    case LABEL = "_label"
    case SUFFIX = "_suffix"
}
