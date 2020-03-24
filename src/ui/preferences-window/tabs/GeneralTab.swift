import Cocoa

class GeneralTab {
    private static let rowHeight = CGFloat(22) // height of the "Tab key" input

    static func make() -> NSTabViewItem {
        return TabViewItem.make(NSLocalizedString("General", comment: ""), NSImage.preferencesGeneralName, makeView())
    }

    private static func makeView() -> NSGridView {
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

        let startAtLogin = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Start at login", comment: ""), "startAtLogin", extraAction: startAtLoginCallback)
        let view = GridView.make([
            startAtLogin,
            LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Alt key", comment: ""), "metaKey", MacroPreferences.metaKeyList.values.map { $0.label }),
            LabelAndControl.makeLabelWithInput(NSLocalizedString("Tab key", comment: ""), "tabKeyCode", 33, NSLocalizedString("KeyCodes Reference", comment: ""), "https://eastmanreference.com/complete-list-of-applescript-key-codes", tabKeyCodeValidator),
        ])
        view.column(at: 0).xPlacement = .trailing
        view.rowAlignment = .lastBaseline
        view.fit()
        setLoginItemIfCheckboxIsOn(startAtLogin[1] as! NSButton)
        return view
    }

    private static func setLoginItemIfCheckboxIsOn(_ startAtLoginCheckbox: NSButton) {
        if startAtLoginCheckbox.state == .on {
            startAtLoginCallback(startAtLoginCheckbox)
        }
    }

    // adding/removing login item depending on the checkbox state
    @available(OSX, deprecated: 10.11)
    @objc static func startAtLoginCallback(_ sender: NSControl) {
        let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue()
        let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItems, nil).takeRetainedValue() as! [LSSharedFileListItem]
        if (sender as! NSButton).state == .on {
            LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemBeforeFirst.takeRetainedValue(), nil, nil, App.url, nil, nil)
        } else {
            loginItemsSnapshot.forEach {
                if LSSharedFileListItemCopyResolvedURL($0, 0, nil).takeRetainedValue() == App.url {
                    LSSharedFileListItemRemove(loginItems, $0)
                }
            }
        }
    }
}
