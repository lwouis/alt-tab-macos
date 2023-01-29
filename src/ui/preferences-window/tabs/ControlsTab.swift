import Cocoa
import ShortcutRecorder

class ControlsTab {
    static var shortcuts = [String: ATShortcut]()
    static var shortcutControls = [String: (CustomRecorderControl, String)]()
    static var shortcutsActions = [
        "holdShortcut": { App.app.focusTarget() },
        "holdShortcut2": { App.app.focusTarget() },
        "holdShortcut3": { App.app.focusTarget() },
        "holdShortcut4": { App.app.focusTarget() },
        "holdShortcut5": { App.app.focusTarget() },
        "focusWindowShortcut": { App.app.focusTarget() },
        "nextWindowShortcut": { App.app.showUiOrCycleSelection(0) },
        "nextWindowShortcut2": { App.app.showUiOrCycleSelection(1) },
        "nextWindowShortcut3": { App.app.showUiOrCycleSelection(2) },
        "nextWindowShortcut4": { App.app.showUiOrCycleSelection(3) },
        "nextWindowShortcut5": { App.app.showUiOrCycleSelection(4) },
        "openNextWindowShortcut": { App.app.nextWindowShortcutWithRepeatingKey() },
        "previousWindowShortcut": { App.app.previousWindowShortcutWithRepeatingKey() },
        "previousWindowShortcut2": { App.app.previousWindowShortcutWithRepeatingKey() },
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
    static var arrowKeysCheckbox: NSButton!

    static func initTab() -> NSView {
        let focusWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Focus selected window", comment: ""), "focusWindowShortcut", Preferences.focusWindowShortcut, labelPosition: .right)
        let openNextWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select next window", comment: ""), "openNextWindowShortcut", Preferences.openNextWindowShortcut, labelPosition: .right)
        let previousWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select previous window", comment: ""), "previousWindowShortcut", Preferences.previousWindowShortcut, labelPosition: .right)
        let previousWindowShortcut2 = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select previous window", comment: ""), "previousWindowShortcut2", Preferences.previousWindowShortcut2, labelPosition: .right)
        let cancelShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Cancel and hide", comment: ""), "cancelShortcut", Preferences.cancelShortcut, labelPosition: .right)
        let closeWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Close window", comment: ""), "closeWindowShortcut", Preferences.closeWindowShortcut, labelPosition: .right)
        let minDeminWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Minimize/Deminimize window", comment: ""), "minDeminWindowShortcut", Preferences.minDeminWindowShortcut, labelPosition: .right)
        let quitAppShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Quit app", comment: ""), "quitAppShortcut", Preferences.quitAppShortcut, labelPosition: .right)
        let hideShowAppShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hide/Show app", comment: ""), "hideShowAppShortcut", Preferences.hideShowAppShortcut, labelPosition: .right)
        let enableArrows = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Arrow keys", comment: ""), "arrowKeysEnabled", extraAction: ControlsTab.arrowKeysEnabledCallback, labelPosition: .right)
        arrowKeysCheckbox = enableArrows[0] as? NSButton
        let enableMouse = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Mouse hover", comment: ""), "mouseHoverEnabled", labelPosition: .right)
        let enableCursorFollowFocus = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Cursor follows focus", comment: ""), "cursorFollowFocusEnabled", labelPosition: .right)
        let selectWindowcheckboxesExplanations = LabelAndControl.makeLabel(NSLocalizedString("Also select windows using:", comment: ""))
        let selectWindowCheckboxes = StackView([StackView(enableArrows), StackView(enableMouse)], .vertical)
        let miscCheckboxesExplanations = LabelAndControl.makeLabel(NSLocalizedString("Miscellaneous:", comment: ""))
        let miscCheckboxes = StackView([StackView(enableCursorFollowFocus)], .vertical)
        let shortcuts = StackView([focusWindowShortcut, openNextWindowShortcut, previousWindowShortcut, previousWindowShortcut2, cancelShortcut, closeWindowShortcut, minDeminWindowShortcut, quitAppShortcut, hideShowAppShortcut].map { (view: [NSView]) in StackView(view) }, .vertical)
        let orPress = LabelAndControl.makeLabel(NSLocalizedString("While open, press:", comment: ""), shouldFit: false)
        let (holdShortcut, nextWindowShortcut, tab1View) = toShowSection(0)
        let (holdShortcut2, nextWindowShortcut2, tab2View) = toShowSection(1)
        let (holdShortcut3, nextWindowShortcut3, tab3View) = toShowSection(2)
        let (holdShortcut4, nextWindowShortcut4, tab4View) = toShowSection(3)
        let (holdShortcut5, nextWindowShortcut5, tab5View) = toShowSection(4)
        let tabView = TabView([
            (NSLocalizedString("Shortcut 1", comment: ""), tab1View),
            (NSLocalizedString("Shortcut 2", comment: ""), tab2View),
            (NSLocalizedString("Shortcut 3", comment: ""), tab3View),
            (NSLocalizedString("Shortcut 4", comment: ""), tab4View),
            (NSLocalizedString("Shortcut 5", comment: ""), tab5View),
        ])

        ControlsTab.arrowKeysEnabledCallback(arrowKeysCheckbox)
        // trigger shortcutChanged for these shortcuts to trigger .restrictModifiers
        [holdShortcut, holdShortcut2, holdShortcut3, holdShortcut4, holdShortcut5].forEach { ControlsTab.shortcutChangedCallback($0[1] as! NSControl) }
        [nextWindowShortcut, nextWindowShortcut2, nextWindowShortcut3, nextWindowShortcut4, nextWindowShortcut5].forEach { ControlsTab.shortcutChangedCallback($0[0] as! NSControl) }

        let grid = GridView([
            [tabView],
            [orPress, shortcuts],
            [selectWindowcheckboxesExplanations, selectWindowCheckboxes],
            [miscCheckboxesExplanations, miscCheckboxes]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: 0, length: 1))
        grid.cell(atColumnIndex: 0, rowIndex: 0).xPlacement = .leading
        tabView.rightAnchor.constraint(equalTo: grid.rightAnchor, constant: -GridView.padding).isActive = true

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

    private static func toShowSection(_ index: Int) -> ([NSView], [NSView], GridView) {
        let toShowExplanations = LabelAndControl.makeLabel(NSLocalizedString("Show windows from:", comment: ""))
        let toShowExplanations2 = LabelAndControl.makeLabel(NSLocalizedString("Minimized windows:", comment: ""))
        let toShowExplanations3 = LabelAndControl.makeLabel(NSLocalizedString("Hidden windows:", comment: ""))
        let toShowExplanations4 = LabelAndControl.makeLabel(NSLocalizedString("Fullscreen windows:", comment: ""))
        var holdShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hold", comment: ""), Preferences.indexToName("holdShortcut", index), Preferences.holdShortcut[index], false, labelPosition: .leftWithoutSeparator)
        holdShortcut.append(LabelAndControl.makeLabel(NSLocalizedString("and press:", comment: "")))
        let holdAndPress = StackView(holdShortcut)
        let appsToShow = LabelAndControl.makeDropdown(Preferences.indexToName("appsToShow", index), AppsToShowPreference.allCases)
        let spacesToShow = LabelAndControl.makeDropdown(Preferences.indexToName("spacesToShow", index), SpacesToShowPreference.allCases)
        let screensToShow = LabelAndControl.makeDropdown(Preferences.indexToName("screensToShow", index), ScreensToShowPreference.allCases)
        let showMinimizedWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showMinimizedWindows", index), ShowHowPreference.allCases)
        let showHiddenWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showHiddenWindows", index), ShowHowPreference.allCases)
        let showFullscreenWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showFullscreenWindows", index), ShowHowPreference.allCases.filter { $0 != .showAtTheEnd })
        let separator = NSBox()
        separator.boxType = .separator
        let nextWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select next window", comment: ""), Preferences.indexToName("nextWindowShortcut", index), Preferences.nextWindowShortcut[index], labelPosition: .right)
        let shortcutStyle = LabelAndControl.makeLabelWithDropdown(NSLocalizedString("Then release:", comment: ""), Preferences.indexToName("shortcutStyle", index), ShortcutStylePreference.allCases)
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

    /// commandTab and commandKeyAboveTab are self-contained in the "nextWindowShortcut" shortcuts
    /// but the keys of commandShiftTab can be spread between holdShortcut and a local shortcut
    static func combinedModifiersMatch(_ modifiers1: UInt32, _ modifiers2: UInt32) -> Bool {
        return (0..<5).contains {
            if let holdShortcut = shortcuts[Preferences.indexToName("holdShortcut", $0)] {
                return (holdShortcut.shortcut.carbonModifierFlags | modifiers1) == (holdShortcut.shortcut.carbonModifierFlags | modifiers2)
            }
            return false
        }
    }

    private static func toggleNativeCommandTabIfNeeded() {
        let nativeHotkeys: [CGSSymbolicHotKey: (Shortcut) -> Bool] = [
            .commandTab: { (shortcut) in shortcut.carbonKeyCode == kVK_Tab && shortcut.carbonModifierFlags == cmdKey },
            .commandShiftTab: { (shortcut) in shortcut.carbonKeyCode == kVK_Tab && combinedModifiersMatch(shortcut.carbonModifierFlags, UInt32(cmdKey | shiftKey)) },
            .commandKeyAboveTab: { (shortcut) in shortcut.carbonModifierFlags == cmdKey && shortcut.carbonKeyCode == kVK_ANSI_Grave },
        ]
        var overlappingHotkeys = shortcuts.values.compactMap { (atShortcut) in nativeHotkeys.first { $1(atShortcut.shortcut) }?.key }
        // if command+tab if bound, disable command+shift+tab always, to avoid confused users
        if overlappingHotkeys.contains(.commandTab) && !overlappingHotkeys.contains(.commandShiftTab) {
            overlappingHotkeys.append(.commandShiftTab)
        }
        let nonOverlappingHotkeys: [CGSSymbolicHotKey] = Array(Set(nativeHotkeys.keys).symmetricDifference(Set(overlappingHotkeys)))
        setNativeCommandTabEnabled(false, overlappingHotkeys)
        setNativeCommandTabEnabled(true, nonOverlappingHotkeys)
    }

    @objc static func shortcutChangedCallback(_ sender: NSControl) {
        let controlId = sender.identifier!.rawValue
        if controlId.hasPrefix("holdShortcut") {
            let i = Preferences.nameToIndex(controlId)
            addShortcut(.up, .global, Shortcut(keyEquivalent: Preferences.holdShortcut[i])!, controlId, i)
            if let nextWindowShortcut = shortcutControls[Preferences.indexToName("nextWindowShortcut", i)]?.0 {
                nextWindowShortcut.restrictModifiers([(sender as! CustomRecorderControl).objectValue!.modifierFlags])
                shortcutChangedCallback(nextWindowShortcut)
            }
        } else {
            let newValue = combineHoldAndNextWindow(controlId, sender)
            if newValue.isEmpty {
                removeShortcutIfExists(controlId)
                restrictModifiersOfHoldShortcut(controlId, [])
            } else {
                let i = controlId.hasPrefix("nextWindowShortcut") ? Preferences.nameToIndex(controlId) : nil
                addShortcut(.down, controlId.hasPrefix("nextWindowShortcut") ? .global : .local, Shortcut(keyEquivalent: newValue)!, controlId, i)
                restrictModifiersOfHoldShortcut(controlId, [(sender as! CustomRecorderControl).objectValue!.modifierFlags])
            }
        }
    }

    private static func restrictModifiersOfHoldShortcut(_ controlId: String, _ modifiers: NSEvent.ModifierFlags) {
        if controlId.hasPrefix("nextWindowShortcut") {
            let i = Preferences.nameToIndex(controlId)
            if let holdShortcut = shortcutControls[Preferences.indexToName("holdShortcut", i)]?.0 {
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
            let holdShortcut = Preferences.holdShortcut[Preferences.nameToIndex(controlId)]
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
