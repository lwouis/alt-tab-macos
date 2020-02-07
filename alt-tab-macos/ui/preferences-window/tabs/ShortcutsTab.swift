import Cocoa

class ShortcutsTab {
    private static let rowHeight = CGFloat(20)

    static func make() -> NSTabViewItem {
        return TabViewItem.make(NSLocalizedString("Shortcuts", comment: ""), NSImage.preferencesGeneralName, makeView())
    }

    private static func makeView() -> NSGridView { // TODO: make the validators be a part of each Preference
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

        let view = GridView.make([
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Alt key", comment: ""), "metaKey", Preferences.metaKeyMacro.labels),
            LabelAndControl.makeLabelWithInput(NSLocalizedString("Tab key", comment: ""), "tabKeyCode", 33, NSLocalizedString("KeyCodes Reference", comment: ""), "https://eastmanreference.com/complete-list-of-applescript-key-codes", tabKeyCodeValidator),
        ])
        view.column(at: 0).xPlacement = .trailing
        view.rowAlignment = .lastBaseline
        view.setRowsHeight(rowHeight)
        view.fit()
        return view
    }
}
