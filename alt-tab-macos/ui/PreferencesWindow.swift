import Cocoa
import Foundation

class PreferencesWindow: NSWindow, NSWindowDelegate {
    let tabViewController = TabViewController()
    let padding = CGFloat(20)
    let interPadding = CGFloat(10)
    var windowCloseRequested = false

    override init(contentRect: NSRect, styleMask style: StyleMask, backing backingStoreType: BackingStoreType, defer flag: Bool) {
        super.init(contentRect: .zero, styleMask: style, backing: backingStoreType, defer: flag)
        title = App.name + " Preferences"
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        styleMask.insert([.miniaturizable, .closable])
        tabViewController.tabStyle = .toolbar
        contentViewController = tabViewController
        makeTabViews()
    }

    private func makeTabViews() {
        for tabTuple in [
            ("Shortcuts", makeShortcutsView(), NSImage.preferencesGeneralName),
            ("Appearance", makeAppearanceView(), NSImage.colorPanelName),
            ("About", makeAboutView(), NSImage.infoName)
        ] {
            let viewController = NSViewController()
            viewController.view = tabTuple.1
            let tabViewItem = NSTabViewItem(viewController: viewController)
            tabViewItem.label = tabTuple.0
            tabViewItem.image = NSImage(named: tabTuple.2)!
            tabViewController.addTabViewItem(tabViewItem)
        }
    }

    func show() {
        App.shared.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
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

    private func makeShortcutsView() -> NSGridView {
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

        return makeGridLayout([
            makeLabelWithDropdown("Alt key", "metaKey", Preferences.metaKeyMacro.labels),
            makeLabelWithInput("Tab key", "tabKeyCode", 33, "KeyCodes Reference", "https://eastmanreference.com/complete-list-of-applescript-key-codes", tabKeyCodeValidator),
        ])
    }

    private func makeAppearanceView() -> NSGridView {
        return makeGridLayout([
            makeLabelWithDropdown("Theme", "theme", Preferences.themeMacro.labels),
            makeLabelWithSlider("Max size on screen", "maxScreenUsage", 10, 100, 10, true, "%"),
            makeLabelWithSlider("Min windows per row", "minCellsPerRow", 1, 20, 20, true),
            makeLabelWithSlider("Max windows per row", "maxCellsPerRow", 1, 40, 20, true),
            makeLabelWithSlider("Min rows of windows", "minRows", 1, 20, 20, true),
            makeLabelWithSlider("Window app icon size", "iconSize", 0, 64, 11, false, "px"),
            makeLabelWithSlider("Window title font size", "fontHeight", 0, 64, 11, false, "px"),
            makeLabelWithDropdown("Show on", "showOnScreen", Preferences.showOnScreenMacro.labels),
            makeLabelWithSlider("Apparition delay", "windowDisplayDelay", 0, 2000, 11, false, "ms"),
            makeLabelWithCheckbox("Hide space number labels", "hideSpaceNumberLabels"),
        ])
    }

    private func makeAboutView() -> NSGridView {
        return makeGridLayout([
            [NSTextField(wrappingLabelWithString: "\(App.name) #VERSION#"), ],
            [HyperlinkLabel(labelWithUrl: "Source code repository", nsUrl: NSURL(string: "https://github.com/lwouis/alt-tab-macos")!)],
            [HyperlinkLabel(labelWithUrl: "Latest releases", nsUrl: NSURL(string: "https://github.com/lwouis/alt-tab-macos/releases")!)],
        ])
    }

    private func makeGridLayout(_ controls: [[NSView]]) -> NSGridView {
        let gridView = NSGridView(views: controls)
        gridView.yPlacement = .fill
        gridView.columnSpacing = interPadding
        gridView.rowSpacing = interPadding
        if controls.first!.count > 1 {
            gridView.column(at: 0).xPlacement = .trailing
        }
        gridView.column(at: 0).leadingPadding = padding
        gridView.column(at: gridView.numberOfColumns - 1).trailingPadding = padding
        gridView.row(at: 0).topPadding = padding
        gridView.row(at: gridView.numberOfRows - 1).bottomPadding = padding
        gridView.fit()
        gridView.rowAlignment = .lastBaseline
        for i in 0..<gridView.numberOfRows {
            gridView.row(at: i).height = 20
        }
        return gridView
    }

    private func makeLabelWithInput(_ labelText: String, _ rawName: String, _ width: CGFloat, _ suffixText: String? = nil, _ suffixUrl: String? = nil, _ validator: ((String) -> Bool)? = nil) -> [NSView] {
        let input = TextField(Preferences.rawValues[rawName]!)
        input.validationHandler = validator
        input.delegate = input
        input.visualizeValidationState()
        input.widthAnchor.constraint(equalToConstant: width).isActive = true
        input.heightAnchor.constraint(equalToConstant: input.fittingSize.height).isActive = true
        let views = makeLabelWithProvidedControl(labelText, rawName, input)
        return [views[0], NSStackView(views: [views[1], makeSuffix(rawName, suffixText!, suffixUrl)])]
    }

    private func makeLabelWithCheckbox(_ labelText: String, _ rawName: String) -> [NSView] {
        let checkbox = NSButton.init(checkboxWithTitle: "", target: nil, action: nil)
        setControlValue(checkbox, Preferences.rawValues[rawName]!)
        return makeLabelWithProvidedControl(labelText, rawName, checkbox)
    }

    private func makeLabelWithDropdown(_ labelText: String, _ rawName: String, _ values: [String], _ suffixText: String? = nil) -> [NSView] {
        let popUp = NSPopUpButton()
        popUp.addItems(withTitles: values)
        popUp.selectItem(withTitle: Preferences.rawValues[rawName]!)
        return makeLabelWithProvidedControl(labelText, rawName, popUp, suffixText)
    }

    private func makeLabelWithSlider(_ labelText: String, _ rawName: String, _ minValue: Double, _ maxValue: Double, _ numberOfTickMarks: Int, _ allowsTickMarkValuesOnly: Bool, _ unitText: String = "") -> [NSView] {
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

    private func makeLabelWithProvidedControl(_ labelText: String?, _ rawName: String, _ control: NSControl, _ suffixText: String? = nil, _ suffixUrl: String? = nil) -> [NSView] {
        let label = makeLabel(labelText, rawName)
        control.identifier = NSUserInterfaceItemIdentifier(rawName)
        control.target = self
        control.action = #selector(controlWasChanged)
        return [label, control, suffixText != nil ? makeSuffix(rawName, suffixText!, suffixUrl) : NSView()]
    }

    private func makeLabel(_ labelText: String?, _ rawName: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: labelText != nil ? labelText! + ": " : "")
        label.fit()
        label.alignment = .right
        label.identifier = NSUserInterfaceItemIdentifier(rawName + ControlIdentifierDiscriminator.LABEL.rawValue)
        return label
    }

    private func makeSuffix(_ controlName: String, _ text: String, _ url: String? = nil) -> NSTextField {
        let suffix: NSTextField
        if url == nil {
            suffix = NSTextField(labelWithString: text)
        } else {
            suffix = HyperlinkLabel(labelWithUrl: text, nsUrl: NSURL(string: url!)!)
        }
        suffix.textColor = .gray
        suffix.identifier = NSUserInterfaceItemIdentifier(controlName + ControlIdentifierDiscriminator.SUFFIX.rawValue)
        suffix.fit()
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
            (App.shared as! App).initPreferencesDependentComponents()
            try Preferences.saveRawToDisk()
        } catch let error {
            debugPrint("PreferencesWindow: save: error", key, newValue, error)
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
                debugPrint("PreferencesWindow: save: error: user choice: edit")
                self.windowCloseRequested = false
            }
            if modalResponse == NSApplication.ModalResponse.alertSecondButtonReturn {
                debugPrint("PreferencesWindow: save: error: user choice: cancel -> revert value and eventually close window")
                try! Preferences.updateAndValidateFromString(key, previousValue)
                self.setControlValue(control, previousValue)
                self.updateControlExtras(control, previousValue)
                if self.windowCloseRequested {
                    self.close()
                }
            }
            if modalResponse == NSApplication.ModalResponse.alertThirdButtonReturn {
                debugPrint("PreferencesWindow: save: error: user choice: check again")
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
