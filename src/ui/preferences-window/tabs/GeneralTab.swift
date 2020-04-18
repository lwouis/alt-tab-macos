import Cocoa
import ShortcutRecorder

class GeneralTab {
    private static let rowHeight = CGFloat(22) // height of the "Tab key" input
    static var shortcutActions = [String: ShortcutAction]()
    static var shortcutsDependentOnHoldShortcut = [NSControl]()

    static func makeView() -> NSView {
        let startAtLogin = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Start at login", comment: ""), "startAtLogin", extraAction: startAtLoginCallback)
        var holdShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hold", comment: ""), "holdShortcut", Preferences.holdShortcut, false, labelPosition: .leftWithoutSeparator)
        holdShortcut.append(LabelAndControl.makeLabel(NSLocalizedString("then press:", comment: "")))
        let nextWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select next window", comment: ""), "nextWindowShortcut", Preferences.nextWindowShortcut, labelPosition: .right)
        let previousWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select previous window", comment: ""), "previousWindowShortcut", Preferences.previousWindowShortcut, labelPosition: .right)
        let cancelShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Cancel and hide", comment: ""), "cancelShortcut", Preferences.cancelShortcut, labelPosition: .right)
        let enableArrows = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Arrow keys", comment: ""), "arrowKeysEnabled", extraAction: arrowKeysEnabledCallback, labelPosition: .right)
        let enableMouse = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Mouse hover", comment: ""), "mouseHoverEnabled", labelPosition: .right)
        let holdAndPress = StackView(holdShortcut)
        let checkboxesExplanations = LabelAndControl.makeLabel(NSLocalizedString("Select windows using:", comment: ""))
        let checkboxes = StackView([StackView(enableArrows), StackView(enableMouse)], .vertical)
        let appsToShow = dropdown("appsToShow", AppsToShowPreference.allCases)
        let spacesToShow = dropdown("spacesToShow", SpacesToShowPreference.allCases)
        let screensToShow = dropdown("screensToShow", ScreensToShowPreference.allCases)
        let showMinimizedWindows = StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Minimized", comment: ""), "showMinimizedWindows", labelPosition: .right))
        let showHiddenWindows = StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hidden", comment: ""), "showHiddenWindows", labelPosition: .right))
        let shortcuts = StackView([nextWindowShortcut, previousWindowShortcut, cancelShortcut].map { StackView($0) }, .vertical)
        let toShowDropdowns = StackView([appsToShow, spacesToShow, screensToShow], .vertical)
        let toShowCheckboxes = StackView([showMinimizedWindows, showHiddenWindows], .vertical)
        let toShowExplanations = LabelAndControl.makeLabel(NSLocalizedString("Show the following windows:", comment: ""))
        let toShow = StackView([toShowDropdowns, toShowCheckboxes], .vertical)

        let grid = GridView([
            startAtLogin,
            [holdAndPress, shortcuts],
            [checkboxesExplanations, checkboxes],
            [toShowExplanations, toShow],
        ])
        grid.column(at: 0).xPlacement = .trailing
        [1, 2, 3].forEach { grid.row(at: $0).topPadding = GridView.interPadding }
        grid.fit()

        shortcutsDependentOnHoldShortcut.append(contentsOf: [enableArrows[0] as! NSControl] + [nextWindowShortcut, previousWindowShortcut, cancelShortcut].map { $0[0] as! NSControl })
        arrowKeysEnabledCallback(enableArrows[0] as! NSControl)
        startAtLoginCallback(startAtLogin[1] as! NSControl)

        return grid
    }

    private static func dropdown(_ rawName: String, _ macroPreferences: [MacroPreference]) -> NSControl {
        let dropdown = LabelAndControl.makeDropDown(rawName, macroPreferences)
        return LabelAndControl.setupControl(dropdown, rawName)
    }

    private static func addShortcut(_ fn: @escaping () -> Void, _ type: KeyEventType, _ shortcut: Shortcut, _ controlId: String) {
        removeShortcutIfExists(controlId, type) // remove the previous shortcut
        shortcutActions[controlId] = ShortcutAction(shortcut: shortcut, actionHandler: { _ in
            let shortcutThatInitiatesTheApp = controlId == "previousWindowShortcut" || controlId == "nextWindowShortcut"
            App.app.uiWorkShouldBeDone = shortcutThatInitiatesTheApp
            if shortcutThatInitiatesTheApp {
                App.app.appIsBeingUsed = true
                DispatchQueue.main.async { () -> () in fn() }
            } else if App.app.appIsBeingUsed {
                fn()
            }
            return true
        })
        App.shortcutMonitor.addAction(shortcutActions[controlId]!, forKeyEvent: type)
    }

    @objc static func shortcutChangedCallback(_ sender: NSControl) {
        let controlId = sender.identifier!.rawValue
        if controlId == "holdShortcut" {
            addShortcut({ App.app.focusTarget() }, .up, Shortcut(keyEquivalent: Preferences.holdShortcut)!, controlId)
            shortcutsDependentOnHoldShortcut.forEach { $0.sendAction($0.action, to: $0.target) }
        } else {
            // remove the holdShortcut character in case they also use it in the other shortcuts
            let newValue = Preferences.holdShortcut.reduce((sender as! RecorderControl).stringValue, { $0.replacingOccurrences(of: String($1), with: "") })
            if newValue.isEmpty {
                removeShortcutIfExists(controlId, .down)
                return
            }
            if controlId == "nextWindowShortcut" {
                addShortcut({ App.app.showUiOrCycleSelection(1) }, .down, Shortcut(keyEquivalent: Preferences.holdShortcut + newValue)!, controlId)
            } else if controlId == "previousWindowShortcut" {
                addShortcut({ App.app.showUiOrCycleSelection(-1) }, .down, Shortcut(keyEquivalent: Preferences.holdShortcut + newValue)!, controlId)
            } else if controlId == "cancelShortcut" {
                addShortcut({ App.app.hideUi() }, .down, Shortcut(keyEquivalent: Preferences.holdShortcut + newValue)!, controlId)
            }
        }
    }

    @objc static func arrowKeysEnabledCallback(_ sender: NSControl) {
        if (sender as! NSButton).state == .on {
            addShortcut({ App.app.cycleSelection(1) }, .down, Shortcut(keyEquivalent: Preferences.holdShortcut + "→")!, "→")
            addShortcut({ App.app.cycleSelection(-1) }, .down, Shortcut(keyEquivalent: Preferences.holdShortcut + "←")!, "←")
        } else {
            removeShortcutIfExists("→", .down)
            removeShortcutIfExists("←", .down)
        }
    }

    private static func removeShortcutIfExists(_ controlId: String, _ type: KeyEventType) {
        if let a = shortcutActions[controlId] {
            App.shortcutMonitor.removeAction(_: a, forKeyEvent: type)
            shortcutActions.removeValue(forKey: controlId)
        }
    }

    // adding/removing login item depending on the checkbox state
    @available(OSX, deprecated: 10.11)
    static func startAtLoginCallback(_ sender: NSControl) {
        let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue()
        let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItems, nil).takeRetainedValue() as! [LSSharedFileListItem]
        let itemName = Bundle.main.bundleURL.lastPathComponent as CFString
        let itemUrl = URL(fileURLWithPath: Bundle.main.bundlePath) as CFURL
        loginItemsSnapshot.forEach {
            if (LSSharedFileListItemCopyDisplayName($0)?.takeRetainedValue() == itemName) ||
                       (LSSharedFileListItemCopyResolvedURL($0, 0, nil)?.takeRetainedValue() == itemUrl) {
                LSSharedFileListItemRemove(loginItems, $0)
            }
        }
        if (sender as! NSButton).state == .on {
            LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemBeforeFirst.takeRetainedValue(), nil, nil, itemUrl, nil, nil)
        }
    }
}
