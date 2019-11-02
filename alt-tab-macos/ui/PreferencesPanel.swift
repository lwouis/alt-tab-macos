import Cocoa

class PreferencesPanel: NSPanel {
    // ui: base layout
    let panelWidth = CGFloat(400)
    let panelHeight = CGFloat(400) // gets auto adjusted to content height
    let panelPadding = CGFloat(40)

    // ui: preferences elements
    var maxScreenUsage: NSTextField?
    var maxThumbnailsPerRow: NSTextField?
    var iconSize: NSTextField?
    var fontHeight: NSTextField?
    var tabKeyCode: NSTextField?
    var windowDisplayDelay: NSTextField?
    var metaKey: NSPopUpButton?
    var theme: NSPopUpButton?
    var showOnScreen: NSPopUpButton?

    var invisibleTextField: NSTextField? // default firstResponder and used for triggering of focus loose
    var inputsMap = [NSTextField: String]()

    override init(contentRect: NSRect, styleMask style: StyleMask, backing backingStoreType: BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
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
        wrappingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: panelPadding * 0.5 * -1).isActive = true
        wrappingView.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: panelPadding * 0.5).isActive = true
        wrappingView.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: panelPadding * 0.5 * -1).isActive = true

        return contentView
    }

    private func makePreferencesViews() -> [NSView] {
        return [
            makeLabelWithDropdown(\PreferencesPanel.metaKey, "Meta key to activate the app", "metaKey", Preferences.metaKeyMacro.labels),
            makeLabelWithInput(\PreferencesPanel.tabKeyCode, "Tab key", "tabKeyCode", "KeyCode"),
            makeHorizontalSeparator(),
            makeLabelWithDropdown(\PreferencesPanel.theme, "Main window theme", "theme", Preferences.themeMacro.labels),
            makeLabelWithInput(\PreferencesPanel.maxScreenUsage, "Max window size", "maxScreenUsage", "% of screen"),
            makeLabelWithInput(\PreferencesPanel.maxThumbnailsPerRow, "Max thumbnails per row", "maxThumbnailsPerRow"),
            makeLabelWithInput(\PreferencesPanel.iconSize, "Apps icon size", "iconSize", "px"),
            makeLabelWithInput(\PreferencesPanel.fontHeight, "Font size", "fontHeight", "px"),
            makeHorizontalSeparator(),
            makeLabelWithInput(\PreferencesPanel.windowDisplayDelay, "Window apparition delay", "windowDisplayDelay", "ms"),
            makeLabelWithDropdown(\PreferencesPanel.showOnScreen, "Show on", "showOnScreen", Preferences.showOnScreenMacro.labels),
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
        field.widthAnchor.constraint(equalToConstant: (panelWidth - panelPadding) * 0.5).isActive = true

        let button = NSButton()
        button.title = "↻  Restart"
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(restartButtonAction)

        let container = NSStackView(views: [field, button])
        container.alignment = .bottom
        return container
    }

    private func makeLabelWithInput(_ keyPath: ReferenceWritableKeyPath<PreferencesPanel, NSTextField?>, _ labelText: String, _ rawName: String, _ suffixText: String? = nil) -> NSStackView {
        let label = NSTextField(wrappingLabelWithString: labelText + ": ")
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: (panelWidth - panelPadding) * 0.5).isActive = true

        let input = NSTextField(string: Preferences.rawValues[rawName]!)
        input.target = self
        input.action = #selector(textDidEndEditing)
        input.widthAnchor.constraint(equalToConstant: 32).isActive = true
        let containerView = NSStackView(views: [label, input])

        if suffixText != nil {
            let suffix = NSTextField(labelWithString: suffixText!)
            suffix.textColor = .gray
            containerView.addView(suffix, in: .leading)
        }

        self[keyPath: keyPath] = input
        inputsMap[input] = rawName

        return containerView
    }

    private func makeLabelWithDropdown(_ keyPath: ReferenceWritableKeyPath<PreferencesPanel, NSPopUpButton?>, _ labelText: String, _ rawName: String, _ values: [String]) -> NSStackView {
        let label = NSTextField(wrappingLabelWithString: labelText + ": ")
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: (panelWidth - panelPadding) * 0.5).isActive = true

        let input = NSPopUpButton()
        input.addItems(withTitles: values)
        input.selectItem(withTitle: Preferences.rawValues[rawName]!)
        input.action = #selector(dropdownDidChange)
        input.target = self

        self[keyPath: keyPath] = input

        return NSStackView(views: [label, input])
    }

    @objc func dropdownDidChange(sender: AnyObject) throws {
        if let popUpButton = sender as? NSPopUpButton {
            switch popUpButton {
            case theme:
                try! Preferences.updateAndValidateFromString("theme", popUpButton.titleOfSelectedItem!)
            case metaKey:
                try! Preferences.updateAndValidateFromString("metaKey", popUpButton.titleOfSelectedItem!)
            case showOnScreen:
                try! Preferences.updateAndValidateFromString("showOnScreen", popUpButton.titleOfSelectedItem!)
            default:
                throw "Tried to update an unknown popUpButton: '\(popUpButton)' = '\(popUpButton.titleOfSelectedItem!)'"
            }
            try! Preferences.saveRawToDisk()
        }
    }

    @objc func textDidEndEditing(sender: AnyObject) {
        if let textField = sender as? NSTextField {
            let key = inputsMap[textField]!
            do {
                try Preferences.updateAndValidateFromString(key, textField.stringValue)
                try Preferences.saveRawToDisk()
            } catch {
                debugPrint(key, error)
                textField.stringValue = Preferences.rawValues[key]!
            }
        }
    }
}
