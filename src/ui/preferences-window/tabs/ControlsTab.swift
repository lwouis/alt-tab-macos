import Cocoa
import ShortcutRecorder

class ControlsTab {
    static var shortcuts = [String: ATShortcut]()
    static var shortcutControls = [String: (CustomRecorderControl, String)]()
    static var shortcutsActions = [
        "holdShortcut": { App.app.focusTarget() },
        "holdShortcut2": { App.app.focusTarget() },
        "focusWindowShortcut": { App.app.focusTarget() },
        "nextWindowShortcut": { App.app.showUiOrCycleSelection(0) },
        "nextWindowShortcut2": { App.app.showUiOrCycleSelection(1) },
        "previousWindowShortcut": { App.app.previousWindowShortcutWithRepeatingKey() },
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
        let focusWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Focus selected window", comment: ""), "focusWindowShortcut", Preferences.focusWindowShortcut, labelPosition: .right)
        let previousWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select previous window", comment: ""), "previousWindowShortcut", Preferences.previousWindowShortcut, labelPosition: .right)
        let cancelShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Cancel and hide", comment: ""), "cancelShortcut", Preferences.cancelShortcut, labelPosition: .right)
        let closeWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Close window", comment: ""), "closeWindowShortcut", Preferences.closeWindowShortcut, labelPosition: .right)
        let minDeminWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Minimize/Deminimize window", comment: ""), "minDeminWindowShortcut", Preferences.minDeminWindowShortcut, labelPosition: .right)
        let quitAppShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Quit app", comment: ""), "quitAppShortcut", Preferences.quitAppShortcut, labelPosition: .right)
        let hideShowAppShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hide/Show app", comment: ""), "hideShowAppShortcut", Preferences.hideShowAppShortcut, labelPosition: .right)
        let enableArrows = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Arrow keys", comment: ""), "arrowKeysEnabled", extraAction: ControlsTab.arrowKeysEnabledCallback, labelPosition: .right)
        let enableMouse = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Mouse hover", comment: ""), "mouseHoverEnabled", labelPosition: .right)
        let enableCursorFollowFocus = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Cursor follows focus", comment: ""), "cursorFollowFocusEnabled", labelPosition: .right)
        let selectWindowcheckboxesExplanations = LabelAndControl.makeLabel(NSLocalizedString("Also select windows using:", comment: ""))
        let selectWindowCheckboxes = StackView([StackView(enableArrows), StackView(enableMouse)], .vertical)
        let miscCheckboxesExplanations = LabelAndControl.makeLabel(NSLocalizedString("Miscellaneous:", comment: ""))
        let miscCheckboxes = StackView([StackView(enableCursorFollowFocus)], .vertical)
        let shortcuts = StackView([focusWindowShortcut, previousWindowShortcut, cancelShortcut, closeWindowShortcut, minDeminWindowShortcut, quitAppShortcut, hideShowAppShortcut].map { (view: [NSView]) in StackView(view) }, .vertical)
        let orPress = LabelAndControl.makeLabel(NSLocalizedString("While open, press:", comment: ""), shouldFit: false)
        let (holdShortcut, nextWindowShortcut, tab1View) = toShowSection("")
        let (holdShortcut2, nextWindowShortcut2, tab2View) = toShowSection("2")
        let tabView = TabView([(NSLocalizedString("Shortcut 1", comment: ""), tab1View), (NSLocalizedString("Shortcut 2", comment: ""), tab2View)])

        ControlsTab.arrowKeysEnabledCallback(enableArrows[0] as! NSControl)
        // trigger shortcutChanged for these shortcuts to trigger .restrictModifiers
        [holdShortcut, holdShortcut2].forEach { ControlsTab.shortcutChangedCallback($0[1] as! NSControl) }
        [nextWindowShortcut, nextWindowShortcut2].forEach { ControlsTab.shortcutChangedCallback($0[0] as! NSControl) }

        let grid = GridView([
            [tabView],
            [orPress, shortcuts],
            [selectWindowcheckboxesExplanations, selectWindowCheckboxes],
            [miscCheckboxesExplanations, miscCheckboxes]
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

    private static func toShowSection(_ postfix: String) -> ([NSView], [NSView], GridView) {
        let toShowExplanations = LabelAndControl.makeLabel(NSLocalizedString("Show windows from:", comment: ""))
        let toShowExplanations2 = LabelAndControl.makeLabel(NSLocalizedString("Minimized windows:", comment: ""))
        let toShowExplanations3 = LabelAndControl.makeLabel(NSLocalizedString("Hidden windows:", comment: ""))
        let toShowExplanations4 = LabelAndControl.makeLabel(NSLocalizedString("Fullscreen windows:", comment: ""))
        var holdShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hold", comment: ""), "holdShortcut" + postfix, Preferences.holdShortcut[postfix == "" ? 0 : 1], false, labelPosition: .leftWithoutSeparator)
        holdShortcut.append(LabelAndControl.makeLabel(NSLocalizedString("and press:", comment: "")))
        let holdAndPress = StackView(holdShortcut)
        let appsToShow = LabelAndControl.makeDropdown("appsToShow" + postfix, AppsToShowPreference.allCases)
        let spacesToShow = LabelAndControl.makeDropdown("spacesToShow" + postfix, SpacesToShowPreference.allCases)
        let screensToShow = LabelAndControl.makeDropdown("screensToShow" + postfix, ScreensToShowPreference.allCases)
        let showMinimizedWindows = LabelAndControl.makeDropdown("showMinimizedWindows" + postfix, ShowHowPreference.allCases)
        let showHiddenWindows = LabelAndControl.makeDropdown("showHiddenWindows" + postfix, ShowHowPreference.allCases)
        let showFullscreenWindows = LabelAndControl.makeDropdown("showFullscreenWindows" + postfix, ShowHowPreference.allCases.filter { $0 != .showAtTheEnd })
        let separator = NSBox()
        separator.boxType = .separator
        let nextWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select next window", comment: ""), "nextWindowShortcut" + postfix, Preferences.nextWindowShortcut[postfix == "" ? 0 : 1], labelPosition: .right)
        let shortcutStyle = LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Then release:", comment: ""), "shortcutStyle" + postfix, ShortcutStylePreference.allCases)
        let toShowDropdowns = StackView([appsToShow, spacesToShow, screensToShow], .vertical, false)
        toShowDropdowns.spacing = TabView.padding
        toShowDropdowns.fit()
        let tab = GridView([
            [toShowExplanations, toShowDropdowns],
            [toShowExplanations2, showMinimizedWindows],
            [toShowExplanations3, showHiddenWindows],
            [toShowExplanations4, showFullscreenWindows],
            [separator],
            [holdAndPress, StackView(nextWindowShortcut)],
            shortcutStyle,
        ], TabView.padding)
        tab.column(at: 0).xPlacement = .trailing
        tab.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: 4, length: 1))
        tab.fit()
        return (holdShortcut, nextWindowShortcut, tab)
    }

    private static func addShortcut(_ triggerPhase: ShortcutTriggerPhase, _ scope: ShortcutScope, _ shortcut: Shortcut, _ controlId: String, _ index: Int?) {
        let atShortcut = ATShortcut(shortcut, controlId, scope, triggerPhase, index)
        removeShortcutIfExists(controlId) // remove the previous shortcut
        shortcuts[controlId] = atShortcut
        if scope == .global {
            KeyboardEvents.addGlobalShortcut(controlId, atShortcut.shortcut)
        }
        toggleNativeCommandTabIfNeeded()
    }

    private static func toggleNativeCommandTabIfNeeded() {
        for atShortcut in shortcuts.values {
            let shortcut = atShortcut.shortcut
            if (shortcut.carbonModifierFlags == cmdKey || shortcut.carbonModifierFlags == (cmdKey | shiftKey)) && shortcut.carbonKeyCode == kVK_Tab {
                setNativeCommandTabEnabled(false)
                return
            }
        }
        setNativeCommandTabEnabled(true)
    }

    @objc static func shortcutChangedCallback(_ sender: NSControl) {
        let controlId = sender.identifier!.rawValue
        if controlId.hasPrefix("holdShortcut") {
            let i = controlId == "holdShortcut" ? 0 : 1
            addShortcut(.up, .global, Shortcut(keyEquivalent: Preferences.holdShortcut[i])!, controlId, i)
            if let nextWindowShortcut = shortcutControls["nextWindowShortcut" + (i == 0 ? "" : "2")]?.0 {
                nextWindowShortcut.restrictModifiers([(sender as! CustomRecorderControl).objectValue!.modifierFlags])
                shortcutChangedCallback(nextWindowShortcut)
            }
        } else {
            let newValue = combineHoldAndNextWindow(controlId, sender)
            if newValue.isEmpty {
                removeShortcutIfExists(controlId)
                restrictModifiersOfHoldShortcut(controlId, [])
            } else {
                let i = controlId.hasPrefix("nextWindowShortcut") ? (controlId == "nextWindowShortcut" ? 0 : 1) : nil
                addShortcut(.down, controlId.hasPrefix("nextWindowShortcut") ? .global : .local, Shortcut(keyEquivalent: newValue)!, controlId, i)
                restrictModifiersOfHoldShortcut(controlId, [(sender as! CustomRecorderControl).objectValue!.modifierFlags])
            }
        }
    }

    private static func restrictModifiersOfHoldShortcut(_ controlId: String, _ modifiers: NSEvent.ModifierFlags) {
        if controlId.hasPrefix("nextWindowShortcut") {
            let i = controlId == "nextWindowShortcut" ? "" : "2"
            if let holdShortcut = shortcutControls["holdShortcut" + i]?.0 {
                holdShortcut.restrictModifiers(modifiers)
            }
        }
    }

    static func combineHoldAndNextWindow(_ controlId: String, _ sender: NSControl) -> String {
        let baseValue = (sender as! RecorderControl).stringValue
        if baseValue == "" {
            return ""
        }
        if controlId.starts(with: "nextWindowShortcut") {
            let holdShortcut = controlId.last == "2" ? Preferences.holdShortcut[1] : Preferences.holdShortcut[0]
            return holdShortcut + baseValue
        }
        return baseValue
    }

    @objc static func arrowKeysEnabledCallback(_ sender: NSControl) {
        let keys = ["←", "→", "↑", "↓"]
        if (sender as! NSButton).state == .on {
            keys.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $0, nil) }
        } else {
            keys.forEach { removeShortcutIfExists($0) }
        }
    }

    private static func removeShortcutIfExists(_ controlId: String) {
        if let atShortcut = shortcuts[controlId] {
            if atShortcut.scope == .global {
                KeyboardEvents.removeGlobalShortcut(controlId, atShortcut.shortcut)
            }
            shortcuts.removeValue(forKey: controlId)
        }
    }
}
