import Cocoa

class PreferencesPanel: NSPanel, NSTextViewDelegate {
    var inputsMap = [NSTextView: String]()

    override init(contentRect: NSRect, styleMask style: StyleMask, backing backingStoreType: BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        let rows = makeLabelsAndInputs()
        let gridView = makeGridView(rows)
        makeAndAddWarningLabel(gridView)
        title = Application.name + " Preferences"
        hidesOnDeactivate = false
        contentView = gridView
    }

    private func makeLabelsAndInputs() -> [[NSTextView]] {
        var rows = [[NSTextView]]()
        [
            ("maxScreenUsage", "Maximum size of the main window, in percentage of screen size"),
            ("windowPadding", "Padding in the main window"),
            ("cellPadding", "Padding in each cell"),
            ("cellBorderWidth", "Border width of each cell"),
            ("maxThumbnailsPerRow", "Maximum number of thumbnails on each row"),
            ("thumbnailMaxWidth", "Maximum width of each thumbnail"),
            ("thumbnailMaxHeight", "Maximum height of each thumbnail"),
            ("iconSize", "Width/height for each cell app icon"),
            ("fontHeight", "Font height for each cell title"),
            ("interItemPadding", "Padding between cells within the main window"),
            ("tabKey", "Tab key (NSEvent.keyCode)"),
            ("metaKey", "Meta key (NSEvent.keyCode)"),
            ("metaModifierFlag", "Meta key (NSEvent.ModifierFlags)"),
//            ("highlightColor", "Color for the currently selected cell"),
            ("thumbnailQuality", "NSImageInterpolation (e.g. none=1, low=2, medium=4, high=3)"),
            ("windowDisplayDelay", "Delay in ms before the window is displayed after pressing the shortcut"),
        ].forEach {
            let p = makePreference($1, Preferences.rawValues[$0]!)
            rows.append(p)
            inputsMap[p[1]] = $0
        }
        return rows
    }

    private func makeGridView(_ rows: [[NSTextView]]) -> NSGridView {
        let gridView = NSGridView(views: rows)
        gridView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        gridView.setContentHuggingPriority(.defaultLow, for: .vertical)
        gridView.widthAnchor.constraint(greaterThanOrEqualToConstant: 580).isActive = true
        return gridView
    }

    private func makeAndAddWarningLabel(_ gridView: NSGridView) {
        let warningLabel = makeLabel("Some settings require restarting the app to apply")
        warningLabel.textColor = .systemRed
        warningLabel.alignment = .center
        gridView.addRow(with: [warningLabel, NSGridCell.emptyContentView])
        gridView.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: gridView.numberOfRows - 1, length: 1))
    }

    private func makePreference(_ labelText: String, _ initialValue: String) -> [NSTextView] {
        let label = makeLabel(labelText)
        label.alignment = .right

        let input = NSTextView()
        input.delegate = self
        input.font = Preferences.font
        input.string = initialValue
        input.widthAnchor.constraint(equalToConstant: 65).isActive = true
        return [label, input]
    }

    private func makeLabel(_ text: String) -> NSTextView {
        let label = NSTextView()
        label.drawsBackground = true
        label.backgroundColor = .clear
        label.isSelectable = false
        label.isEditable = false
        label.font = Preferences.font
        label.string = text
        label.enabledTextCheckingTypes = 0
        label.heightAnchor.constraint(greaterThanOrEqualToConstant: Preferences.fontHeight + Preferences.interItemPadding).isActive = true
        return label
    }

    func textDidEndEditing(_ notification: Notification) {
        if let textView = notification.object as? NSTextView {
            let key = inputsMap[textView]!
            do {
                try Preferences.updateAndValidateValue(key, textView.string)
                try Preferences.saveRawToDisk()
            } catch {
                textView.string = Preferences.rawValues[key]!
            }
        }
    }
}
