import Cocoa

class PreferencesPanel: NSPanel, NSTextViewDelegate {
    var maxScreenUsage: NSTextView?
    var windowPadding: NSTextView?
    var cellPadding: NSTextView?
    var cellBorderWidth: NSTextView?
    var maxThumbnailsPerRow: NSTextView?
    var iconSize: NSTextView?
    var fontHeight: NSTextView?
    var interItemPadding: NSTextView?
    var tabKeyCode: NSTextView?
    var windowDisplayDelay: NSTextView?
    var metaKey: NSPopUpButton?
    var theme: NSPopUpButton?
    var showOnScreen: NSPopUpButton?
    var inputsMap = [NSTextView: String]()

    override init(contentRect: NSRect, styleMask style: StyleMask, backing backingStoreType: BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        title = Application.name + " Preferences"
        hidesOnDeactivate = false
        contentView = makeGridView(makeLabelsAndInputs(), makeWarningLabel())
    }

    private func makeLabelsAndInputs() -> [[NSView]] {
        return [
            makeLabelWithDropdown(\PreferencesPanel.theme, "Main window theme", "theme", Preferences.themeMacro.labels),
            makeLabelWithDropdown(\PreferencesPanel.metaKey, "Meta key to activate the app", "metaKey", Preferences.metaKeyMacro.labels),
            makeLabelWithInput(\PreferencesPanel.tabKeyCode, "Tab key (HIToolbox.Events)", "tabKeyCode"),
            makeLabelWithInput(\PreferencesPanel.maxScreenUsage, "Max window size (screen %)", "maxScreenUsage"),
            makeLabelWithInput(\PreferencesPanel.maxThumbnailsPerRow, "Max thumbnails per row", "maxThumbnailsPerRow"),
            makeLabelWithInput(\PreferencesPanel.iconSize, "Apps icon size (px)", "iconSize"),
            makeLabelWithInput(\PreferencesPanel.fontHeight, "Font size (px)", "fontHeight"),
            makeLabelWithInput(\PreferencesPanel.windowDisplayDelay, "Window apparition delay (ms)", "windowDisplayDelay"),
            makeLabelWithDropdown(\PreferencesPanel.showOnScreen, "Show on Screen", "showOnScreen", Preferences.showOnScreenMacro.labels)
        ]
    }

    private func makeGridView(_ rows: [[NSView]], _ warningLabel: BaseLabel) -> NSGridView {
        let gridView = NSGridView(views: rows)
        gridView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        gridView.setContentHuggingPriority(.defaultLow, for: .vertical)
        gridView.widthAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true
        gridView.addRow(with: [warningLabel, NSGridCell.emptyContentView])
        gridView.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: gridView.numberOfRows - 1, length: 1))
        return gridView
    }

    private func makeWarningLabel() -> BaseLabel {
        let warningLabel = BaseLabel("Some settings require restarting the app to apply")
        warningLabel.textColor = .systemRed
        warningLabel.alignment = .center
        return warningLabel
    }

    private func makeLabelWithInput(_ keyPath: ReferenceWritableKeyPath<PreferencesPanel, NSTextView?>, _ labelText: String, _ rawName: String) -> [NSTextView] {
        let label = BaseLabel(labelText)
        label.alignment = .right
        let input = NSTextView()
        input.delegate = self
        input.font = Preferences.font
        input.string = Preferences.rawValues[rawName]!
        input.widthAnchor.constraint(equalToConstant: 40).isActive = true
        self[keyPath: keyPath] = input
        inputsMap[input] = rawName
        return [label, input]
    }

    private func makeLabelWithDropdown(_ keyPath: ReferenceWritableKeyPath<PreferencesPanel, NSPopUpButton?>, _ labelText: String, _ rawName: String, _ values: [String]) -> [NSView] {
        let label = BaseLabel(labelText)
        label.alignment = .right
        let input = NSPopUpButton()
        input.addItems(withTitles: values)
        input.selectItem(withTitle: Preferences.rawValues[rawName]!)
        input.action = #selector(dropdownDidChange)
        input.target = self
        self[keyPath: keyPath] = input
        return [label, input]
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

    func textDidEndEditing(_ notification: Notification) {
        if let textView = notification.object as? NSTextView {
            let key = inputsMap[textView]!
            do {
                try Preferences.updateAndValidateFromString(key, textView.string)
                try Preferences.saveRawToDisk()
            } catch {
                debugPrint(key, error)
                textView.string = Preferences.rawValues[key]!
            }
        }
    }
}
