import Cocoa
import ShortcutRecorder

class ControlsTab {
    static var nextWindowShortcut: [NSControl]!
    static var localShortcuts = [String: Shortcut]()
    static var globalShortcuts = [String: Shortcut]()
    static var shortcutsActions = [
        "holdShortcut": { App.app.focusTarget() },
        "holdShortcut2": { App.app.focusTarget() },
        "focusWindowShortcut": { App.app.focusTarget() },
        "nextWindowShortcut": { App.app.showUiOrCycleSelection(0) },
        "nextWindowShortcut2": { App.app.showUiOrCycleSelection(1) },
        "previousWindowShortcut": { App.app.cycleSelection(.trailing) },
        "→": { App.app.cycleSelection(.right) },
        "←": { App.app.cycleSelection(.left) },
        "↑": { App.app.cycleSelection(.up) },
        "↓": { App.app.cycleSelection(.down) },
        "cancelShortcut": { App.app.hideUi() },
        "closeWindowShortcut": { App.app.closeSelectedWindow() },
        "minDeminWindowShortcut": { App.app.minDeminSelectedWindow() },
        "quitAppShortcut": { App.app.quitSelectedApp() },
        "hideShowAppShortcut": { App.app.hideShowSelectedApp() },
    ]

    static func initTab() -> NSView {
        let shortcutStyle = LabelAndControl.makeLabelWithDropdown(NSLocalizedString("then release:", comment: ""), "shortcutStyle", ShortcutStylePreference.allCases)
        let focusWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Focus selected window", comment: ""), "focusWindowShortcut", Preferences.focusWindowShortcut, labelPosition: .right)
        let previousWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select previous window", comment: ""), "previousWindowShortcut", Preferences.previousWindowShortcut, labelPosition: .right)
        let cancelShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Cancel and hide", comment: ""), "cancelShortcut", Preferences.cancelShortcut, labelPosition: .right)
        let closeWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Close window", comment: ""), "closeWindowShortcut", Preferences.closeWindowShortcut, labelPosition: .right)
        let minDeminWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Minimize/Deminimize window", comment: ""), "minDeminWindowShortcut", Preferences.minDeminWindowShortcut, labelPosition: .right)
        let quitAppShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Quit app", comment: ""), "quitAppShortcut", Preferences.quitAppShortcut, labelPosition: .right)
        let hideShowAppShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hide/Show app", comment: ""), "hideShowAppShortcut", Preferences.hideShowAppShortcut, labelPosition: .right)
        let enableArrows = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Arrow keys", comment: ""), "arrowKeysEnabled", extraAction: ControlsTab.arrowKeysEnabledCallback, labelPosition: .right)
        let enableMouse = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Mouse hover", comment: ""), "mouseHoverEnabled", labelPosition: .right)
        let checkboxesExplanations = LabelAndControl.makeLabel(NSLocalizedString("Also select windows using:", comment: ""))
        let checkboxes = StackView([StackView(enableArrows), StackView(enableMouse)], .vertical)
        let shortcuts = StackView([focusWindowShortcut, previousWindowShortcut, cancelShortcut, closeWindowShortcut, minDeminWindowShortcut, quitAppShortcut, hideShowAppShortcut].map { (view: [NSView]) in StackView(view) }, .vertical)
        let orPress = LabelAndControl.makeLabel(NSLocalizedString("While open, press:", comment: ""), shouldFit: false)
        let (nextWindowShortcut, tab1View) = toShowSection("")
        let (nextWindowShortcut2, tab2View) = toShowSection("2")
        let tabView = TabView([(NSLocalizedString("Shortcut 1", comment: ""), tab1View), (NSLocalizedString("Shortcut 2", comment: ""), tab2View)])

        ControlsTab.nextWindowShortcut = [nextWindowShortcut, nextWindowShortcut2].map { $0[0] as! NSControl }
        ControlsTab.arrowKeysEnabledCallback(enableArrows[0] as! NSControl)

        let grid = GridView([
            [tabView],
            shortcutStyle,
            [orPress, shortcuts],
            [checkboxesExplanations, checkboxes],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: 0, length: 1))
        grid.cell(atColumnIndex: 0, rowIndex: 0).xPlacement = .leading

        // TODO: better layout logic. Maybe freeze the width of the preference window and have labels wrap on multiple lines
        // currently this looks bad if the right column inside the tabView is larger than the right column of the top gridView
        let leftColumnWidthTabView = tab1View.column(at: 0).width()
        let leftColumnWidthTopView = grid.column(at: 0).width(0)
        if leftColumnWidthTabView > leftColumnWidthTopView {
            orPress.fit(tab1View.column(at: 0).width() + GridView.interPadding + TabView.padding, orPress.fittingSize.height)
        } else {
            orPress.fit()
            tabView.leftAnchor.constraint(equalTo: tabView.superview!.leftAnchor, constant: leftColumnWidthTopView - leftColumnWidthTabView + 3).isActive = true
        }

        return grid
    }

    private static func toShowSection(_ postfix: String) -> ([NSView], GridView) {
        let toShowExplanations = LabelAndControl.makeLabel(NSLocalizedString("Show the following windows:", comment: ""))
        var holdShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hold", comment: ""), "holdShortcut" + postfix, Preferences.holdShortcut[postfix == "" ? 0 : 1], false, labelPosition: .leftWithoutSeparator)
        holdShortcut.append(LabelAndControl.makeLabel(NSLocalizedString("and press:", comment: "")))
        let holdAndPress = StackView(holdShortcut)
        let appsToShow = LabelAndControl.makeDropdown("appsToShow" + postfix, AppsToShowPreference.allCases)
        let spacesToShow = LabelAndControl.makeDropdown("spacesToShow" + postfix, SpacesToShowPreference.allCases)
        let screensToShow = LabelAndControl.makeDropdown("screensToShow" + postfix, ScreensToShowPreference.allCases)
        let showMinimizedWindows = StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Minimized", comment: ""), "showMinimizedWindows" + postfix, labelPosition: .right))
        let showHiddenWindows = StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hidden", comment: ""), "showHiddenWindows" + postfix, labelPosition: .right))
        let showFullscreenWindows = StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Fullscreen", comment: ""), "showFullscreenWindows" + postfix, labelPosition: .right))
        let nextWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select next window", comment: ""), "nextWindowShortcut" + postfix, Preferences.nextWindowShortcut[postfix == "" ? 0 : 1], labelPosition: .right)
        let toShowDropdowns = StackView([appsToShow, spacesToShow, screensToShow, showMinimizedWindows, showHiddenWindows, showFullscreenWindows], .vertical, false)
        toShowDropdowns.spacing = TabView.padding
        toShowDropdowns.fit()
        let tab = GridView([
            [toShowExplanations, toShowDropdowns],
            [holdAndPress, StackView(nextWindowShortcut)],
        ], TabView.padding)
        tab.column(at: 0).xPlacement = .trailing
        tab.fit()
        return (nextWindowShortcut, tab)
    }

    private static func addShortcut(_ type: KeyEventType, _ shortcut: Shortcut, _ controlId: String, _ globalId: Int?) {
        removeShortcutIfExists(controlId, type, globalId) // remove the previous shortcut
        if let globalId = globalId {
            globalShortcuts[controlId] = shortcut
            KeyboardEvents.addGlobalShortcut(shortcut, globalId)
        } else {
            localShortcuts[controlId] = shortcut
        }
    }

    @objc static func shortcutChangedCallback(_ sender: NSControl) {
        let controlId = sender.identifier!.rawValue
        let globalId = KeyboardEvents.globalShortcuts[controlId]
        if controlId.hasPrefix("holdShortcut") {
            let i = controlId == "holdShortcut" ? 0 : 1
            addShortcut(.up, Shortcut(keyEquivalent: Preferences.holdShortcut[i])!, controlId, globalId)
            // hold shortcuts need to also be local for the case of space transition reopening the ui
            addShortcut(.up, Shortcut(keyEquivalent: Preferences.holdShortcut[i])!, controlId, nil)
            if let s = nextWindowShortcut?[i] {
                shortcutChangedCallback(s)
            }
        } else {
            let newValue = shortcutStringValue(controlId, sender, globalId)
            if newValue.isEmpty {
                removeShortcutIfExists(controlId, .down, globalId)
            } else {
                addShortcut(.down, Shortcut(keyEquivalent: newValue)!, controlId, globalId)
            }
        }
    }

    static func shortcutStringValue(_ controlId: String, _ sender: NSControl, _ globalId: Int?) -> String {
        let baseValue = (sender as! RecorderControl).stringValue
        if globalId != nil {
            let holdShortcut = controlId == "nextWindowShortcut" ? Preferences.holdShortcut[0] : Preferences.holdShortcut[1]
            // remove the holdShortcut character in case they also use it in the other shortcuts
            let cleanedShortcut = holdShortcut + holdShortcut.reduce(baseValue, { $0.replacingOccurrences(of: String($1), with: "") })
            if cleanedShortcut.sorted() == holdShortcut.sorted() {
                return ""
            }
            return cleanedShortcut
        }
        return baseValue
    }

    @objc static func arrowKeysEnabledCallback(_ sender: NSControl) {
        let keys = ["←", "→", "↑", "↓"]
        if (sender as! NSButton).state == .on {
            keys.forEach { addShortcut(.down, Shortcut(keyEquivalent: $0)!, $0, nil) }
        } else {
            keys.forEach { removeShortcutIfExists($0, .down, nil) }
        }
    }

    private static func removeShortcutIfExists(_ controlId: String, _ type: KeyEventType, _ globalId: Int?) {
        if let globalId = globalId {
            if globalShortcuts[controlId] != nil {
                KeyboardEvents.removeGlobalShortcut(globalId, globalShortcuts[controlId]!)
                globalShortcuts.removeValue(forKey: controlId)
            }
        } else {
            if localShortcuts[controlId] != nil {
                localShortcuts.removeValue(forKey: controlId)
            }
        }
    }
}
