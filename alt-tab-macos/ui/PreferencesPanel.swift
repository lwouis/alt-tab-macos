import Cocoa

class PreferencesPanel: NSPanel {
    // ui: base layout
    let panelWidth = CGFloat(400)
    let panelHeight = CGFloat(400) // gets auto adjusted to content height
    let panelPadding = CGFloat(40)
    let panelWidthToLabelRatio = CGFloat(0.5)

    // ui: preferences elements
    var maxScreenUsage: NSSlider?
    var maxThumbnailsPerRow: NSTextField?
    var iconSize: NSSlider?
    var fontHeight: NSSlider?
    var tabKeyCode: NSTextField?
    var windowDisplayDelay: NSTextField?
    var metaKey: NSPopUpButton?
    var theme: NSPopUpButton?
    var showOnScreen: NSPopUpButton?

    var invisibleTextField: NSTextField? // default firstResponder and used for triggering of focus loose

    override init(contentRect: NSRect, styleMask style: StyleMask, backing backingStoreType: BackingStoreType, defer flag: Bool) {
        let initialRect = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        super.init(contentRect: initialRect, styleMask: style, backing: backingStoreType, defer: flag)
        title = Application.name + " Preferences"
        titlebarAppearsTransparent = true
        hidesOnDeactivate = false
        contentView = makeContentView()

        // setup hidden element
        invisibleTextField = NSTextField()
        invisibleTextField?.isHidden = true
        contentView?.subviews.append(invisibleTextField!)
        self.initialFirstResponder = invisibleTextField
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
        return [
            makeLabelWithDropdown(\PreferencesPanel.metaKey, "Meta key to activate the app", rawName: "metaKey", values: Preferences.metaKeyMacro.labels),
            makeLabelWithInput(\PreferencesPanel.tabKeyCode, "Tab key", rawName: "tabKeyCode", suffixText: "KeyCode"),
            makeHorizontalSeparator(),
            makeLabelWithDropdown(\PreferencesPanel.theme, "Main window theme", rawName: "theme", values: Preferences.themeMacro.labels),
            makeLabelWithSlider(\PreferencesPanel.maxScreenUsage, "Max window size", rawName: "maxScreenUsage", minValue: 10, maxValue: 100, numberOfTickMarks: 10),
            makeLabelWithInput(\PreferencesPanel.maxThumbnailsPerRow, "Max thumbnails per row", rawName: "maxThumbnailsPerRow"),
            makeLabelWithSlider(\PreferencesPanel.iconSize, "Apps icon size", rawName: "iconSize", minValue: 12, maxValue: 64, numberOfTickMarks: 16),
            makeLabelWithSlider(\PreferencesPanel.fontHeight, "Font size", rawName: "fontHeight", minValue: 12, maxValue: 36, numberOfTickMarks: 16),
            makeHorizontalSeparator(),
            makeLabelWithInput(\PreferencesPanel.windowDisplayDelay, "Window apparition delay", rawName: "windowDisplayDelay", suffixText: "ms"),
            makeLabelWithDropdown(\PreferencesPanel.showOnScreen, "Show on", rawName: "showOnScreen", values: Preferences.showOnScreenMacro.labels),
            makeHorizontalSeparator(),
            makeRestartHint()
        ]
    }

    private func makeHorizontalSeparator() -> NSView {
        let view = NSBox()
        view.boxType = .separator

        return view
    }

    @objc private func restartButtonAction() {
        self.makeFirstResponder(invisibleTextField)

        if let delegate = Application.shared.delegate as? Application {
            delegate.relaunch()
        }
    }

    private func makeRestartHint() -> NSStackView {
        let field = NSTextField(wrappingLabelWithString: "Some settings require restarting the app to apply: ")
        field.textColor = .systemRed
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: calcLabelWidth()).isActive = true

        let button = NSButton()
        button.title = "↻  Restart"
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(restartButtonAction)

        let container = NSStackView(views: [field, button])
        container.alignment = .bottom
        return container
    }

    private func makeLabelWithInput(_ keyPath: ReferenceWritableKeyPath<PreferencesPanel, NSTextField?>, _ labelText: String, rawName: String, suffixText: String? = nil) -> NSStackView {
        let input = NSTextField(string: Preferences.rawValues[rawName]!)
        input.widthAnchor.constraint(equalToConstant: 32).isActive = true

        self[keyPath: keyPath] = input

        return makeLabelWithProvidedControl(labelText, rawName, input, suffixText)
    }

    private func makeLabelWithDropdown(_ keyPath: ReferenceWritableKeyPath<PreferencesPanel, NSPopUpButton?>, _ labelText: String, rawName: String, values: [String], suffixText: String? = nil) -> NSStackView {
        let popUp = NSPopUpButton()
        popUp.addItems(withTitles: values)
        popUp.selectItem(withTitle: Preferences.rawValues[rawName]!)

        self[keyPath: keyPath] = popUp

        return makeLabelWithProvidedControl(labelText, rawName, popUp, suffixText)
    }

    private func makeLabelWithSlider(_ keyPath: ReferenceWritableKeyPath<PreferencesPanel, NSSlider?>, _ labelText: String, rawName: String, minValue: Double, maxValue: Double, numberOfTickMarks: Int, suffixText: String? = nil) -> NSStackView {
        let slider = NSSlider(
                value: Double(Preferences.rawValues[rawName]!)!,
                minValue: minValue,
                maxValue: maxValue,
                target: self,
                action: #selector(controlDidEndEditing)
        )
        slider.numberOfTickMarks = numberOfTickMarks
        slider.allowsTickMarkValuesOnly = numberOfTickMarks > 1
        slider.tickMarkPosition = .below

        self[keyPath: keyPath] = slider

        return makeLabelWithProvidedControl(labelText, rawName, slider, suffixText)
    }

    private func makeLabelWithProvidedControl(_ labelText: String, _ rawName: String, _ control: NSControl, _ suffixText: String? = nil) -> NSStackView {
        let label = NSTextField(wrappingLabelWithString: labelText + ": ")
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: calcLabelWidth()).isActive = true

        control.identifier = NSUserInterfaceItemIdentifier(rawName)
        control.target = self
        control.action = #selector(controlDidEndEditing)
        let containerView = NSStackView(views: [label, control])

        if suffixText != nil {
            let suffix = NSTextField(labelWithString: suffixText!)
            suffix.textColor = .gray
            containerView.addView(suffix, in: .leading)
        }

        return containerView
    }

    /*
    usage notes:
    - NSSlider: supports on purpose currently only decimal values
    */
    @objc func controlDidEndEditing(senderControl: NSControl) {
        self.makeFirstResponder(invisibleTextField) // deselects any possibly selected NSTextField (so slider & popUp changes deselect them)

        let key: String? = senderControl.identifier?.rawValue
        var newValue: String?

        if senderControl is NSPopUpButton {
            newValue = (senderControl as! NSPopUpButton).titleOfSelectedItem!
        } else if senderControl is NSSlider {
            newValue = String(format: "%.0f", Double(senderControl.stringValue)!) // we are only interested in decimals of the provided double
        } else {
            newValue = senderControl.stringValue
        }

//        debugPrint("PreferencesPanel: save: change", key!, newValue!)

        if key != nil && newValue != nil {
            if newValue == Preferences.rawValues[key!] {
                debugPrint("PreferencesPanel: save: abort: value was not changed")
                return
            }

            let previousValue = Preferences.rawValues[key!]!

            do {
                try Preferences.updateAndValidateFromString(key!, newValue!)
                try Preferences.saveRawToDisk()
            } catch {
                debugPrint("PreferencesPanel: save: error", key!, error, "previousValue", previousValue, " | newValue", newValue!)

                // restores the previous value in Preferences and senderControl
                try! Preferences.updateAndValidateFromString(key!, previousValue)

                if senderControl is NSPopUpButton {
                    (senderControl as! NSPopUpButton).selectItem(withTitle: previousValue)
                } else {
                    senderControl.stringValue = previousValue
                }
            }
        } else {
            debugPrint("PreferencesPanel: save: error: key||newValue = nil", key!, newValue!)
        }
    }

    private func calcLabelWidth() -> CGFloat {
        return (panelWidth - panelPadding) * panelWidthToLabelRatio
    }
}
