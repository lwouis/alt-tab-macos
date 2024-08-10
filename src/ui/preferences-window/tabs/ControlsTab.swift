import Cocoa
import ShortcutRecorder

class ControlsShortcutsWindow: SheetWindow {

    override func setupView() {
        let view = TableGroupSetView(originalViews: [ControlsTab.shortcutsView], toolsViews: [doneButton])
        view.widthAnchor.constraint(equalToConstant: SheetWindow.width + TableGroupSetView.leftRightPadding).isActive = true
        contentView = view
    }
}

class ControlsAdvancedWindow: SheetWindow {

    override func setupView() {
        let view = TableGroupSetView(originalViews: [ControlsTab.selectWindowsView, ControlsTab.miscellaneousView], toolsViews: [doneButton])
        view.widthAnchor.constraint(equalToConstant: SheetWindow.width + TableGroupSetView.leftRightPadding).isActive = true
        contentView = view
    }

}

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
        "previousWindowShortcut": { App.app.previousWindowShortcutWithRepeatingKey() },
        "→": { App.app.cycleSelection(.right) },
        "←": { App.app.cycleSelection(.left) },
        "↑": { App.app.cycleSelection(.up) },
        "↓": { App.app.cycleSelection(.down) },
        "vimCycleRight": { App.app.cycleSelection(.right) },
        "vimCycleLeft": { App.app.cycleSelection(.left) },
        "vimCycleUp": { App.app.cycleSelection(.up) },
        "vimCycleDown": { App.app.cycleSelection(.down) },
        "cancelShortcut": { App.app.hideUi() },
        "closeWindowShortcut": { App.app.closeSelectedWindow() },
        "minDeminWindowShortcut": { App.app.minDeminSelectedWindow() },
        "toggleFullscreenWindowShortcut": { App.app.toggleFullscreenSelectedWindow() },
        "quitAppShortcut": { App.app.quitSelectedApp() },
        "hideShowAppShortcut": { App.app.hideShowSelectedApp() },
    ]
    static var arrowKeysCheckbox: NSButton!
    static var vimKeysCheckbox: NSButton!

    static var tabViews: [TableGroupSetView]!
    static var selectWindowsView: TableGroupView!
    static var shortcutsView: TableGroupView!
    static var miscellaneousView: TableGroupView!

    static func initTab() -> NSView {
        makeComponents()
        let shortcutsButton = NSButton(title: NSLocalizedString("Shortcuts…", comment: ""), target: self, action: #selector(ControlsTab.showShortcutsSettings))
        let advancedButton = NSButton(title: NSLocalizedString("Advanced…", comment: ""), target: self, action: #selector(ControlsTab.showAdvancedSettings))
        let orPress = LabelAndControl.makeLabel(NSLocalizedString("While open, press:", comment: ""), shouldFit: false)
        let (holdShortcut, nextWindowShortcut, tab1View) = toShowSection(0)
        let (holdShortcut2, nextWindowShortcut2, tab2View) = toShowSection(1)
        let (holdShortcut3, nextWindowShortcut3, tab3View) = toShowSection(2)
        let (holdShortcut4, nextWindowShortcut4, tab4View) = toShowSection(3)
        let (holdShortcut5, nextWindowShortcut5, tab5View) = toShowSection(4)
        tabViews = [tab1View, tab2View, tab3View, tab4View, tab5View]
        // trigger shortcutChanged for these shortcuts to trigger .restrictModifiers
        [holdShortcut, holdShortcut2, holdShortcut3, holdShortcut4, holdShortcut5].forEach { ControlsTab.shortcutChangedCallback($0[1] as! NSControl) }
        [nextWindowShortcut, nextWindowShortcut2, nextWindowShortcut3, nextWindowShortcut4, nextWindowShortcut5].forEach { ControlsTab.shortcutChangedCallback($0[0] as! NSControl) }


        let tab = NSSegmentedControl(labels: [
            NSLocalizedString("Shortcut 1", comment: ""),
            NSLocalizedString("Shortcut 2", comment: ""),
            NSLocalizedString("Shortcut 3", comment: ""),
            NSLocalizedString("Shortcut 4", comment: ""),
            NSLocalizedString("Shortcut 5", comment: ""),
        ], trackingMode: .selectOne, target: self, action: #selector(switchTab(_:)))
        tab.selectedSegment = 0
        tab.segmentStyle = .automatic
        tab.widthAnchor.constraint(equalToConstant: PreferencesWindow.width).isActive = true

        let buttons = StackView([shortcutsButton, advancedButton])
        let view = TableGroupSetView(originalViews: [tab, tab1View, tab2View, tab3View, tab4View, tab5View, buttons])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        ControlsTab.switchTab(tab)
        return view
    }

    static func makeComponents() {
        selectWindowsView = makeSelectWindowsView()
        shortcutsView = makeShortcutsView()
        miscellaneousView = makeMiscellaneousView()
    }

    static func makeSelectWindowsView() -> TableGroupView {
        let enableArrows = TableGroupView.Row(leftTitle: NSLocalizedString("Select windows using arrow keys", comment: ""),
                rightViews: [LabelAndControl.makeCheckbox("arrowKeysEnabled", extraAction: ControlsTab.arrowKeysEnabledCallback)])
        let enableVimKeys = TableGroupView.Row(leftTitle: NSLocalizedString("Select windows using vim keys", comment: ""),
                rightViews: [LabelAndControl.makeCheckbox("vimKeysEnabled", extraAction: ControlsTab.vimKeysEnabledCallback)])
        let enableMouse = TableGroupView.Row(leftTitle: NSLocalizedString("Select windows on mouse hover", comment: ""),
                rightViews: [LabelAndControl.makeCheckbox("mouseHoverEnabled")])

        ControlsTab.arrowKeysCheckbox = enableArrows.rightViews[0] as? NSButton
        ControlsTab.vimKeysCheckbox = enableVimKeys.rightViews[0] as? NSButton
        ControlsTab.arrowKeysEnabledCallback(ControlsTab.arrowKeysCheckbox)
        ControlsTab.vimKeysEnabledCallback(ControlsTab.vimKeysCheckbox)

        let table = TableGroupView(title: NSLocalizedString("Select Windows", comment: ""),
                width: SheetWindow.width)
        _ = table.addRow(enableArrows)
        _ = table.addRow(enableVimKeys)
        _ = table.addRow(enableMouse)
        return table
    }

    static func makeMiscellaneousView() -> TableGroupView {
        let enableCursorFollowFocus = TableGroupView.Row(leftTitle: NSLocalizedString("Cursor follows focus", comment: ""),
                rightViews: [LabelAndControl.makeCheckbox("cursorFollowFocusEnabled")])
        let table = TableGroupView(title: NSLocalizedString("Miscellaneous", comment: ""),
                width: SheetWindow.width)
        _ = table.addRow(enableCursorFollowFocus)
        return table
    }

    static func makeShortcutsView() -> TableGroupView {
        let focusWindowShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Focus selected window", comment: ""),
                rightViews: [LabelAndControl.makeLabelWithRecorder("", "focusWindowShortcut", Preferences.focusWindowShortcut, labelPosition: .right)[0]])
        let previousWindowShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Select previous window", comment: ""),
                rightViews: [LabelAndControl.makeLabelWithRecorder("", "previousWindowShortcut", Preferences.previousWindowShortcut, labelPosition: .right)[0]])
        let cancelShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Cancel and hide", comment: ""),
                rightViews: [LabelAndControl.makeLabelWithRecorder("", "cancelShortcut", Preferences.cancelShortcut, labelPosition: .right)[0]])
        let closeWindowShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Close window", comment: ""),
                rightViews: [LabelAndControl.makeLabelWithRecorder("", "closeWindowShortcut", Preferences.closeWindowShortcut, labelPosition: .right)[0]])
        let minDeminWindowShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Minimize/Deminimize window", comment: ""),
                rightViews: [LabelAndControl.makeLabelWithRecorder("", "minDeminWindowShortcut", Preferences.minDeminWindowShortcut, labelPosition: .right)[0]])
        let toggleFullscreenWindowShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Fullscreen/Defullscreen window", comment: ""),
                rightViews: [LabelAndControl.makeLabelWithRecorder("", "toggleFullscreenWindowShortcut", Preferences.toggleFullscreenWindowShortcut, labelPosition: .right)[0]])
        let quitAppShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Quit app", comment: ""),
                rightViews: [LabelAndControl.makeLabelWithRecorder("", "quitAppShortcut", Preferences.quitAppShortcut, labelPosition: .right)[0]])
        let hideShowAppShortcut = TableGroupView.Row(leftTitle: NSLocalizedString("Hide/Show app", comment: ""),
                rightViews: [LabelAndControl.makeLabelWithRecorder("", "hideShowAppShortcut", Preferences.hideShowAppShortcut, labelPosition: .right)[0]])

        let table = TableGroupView(title: NSLocalizedString("Shortcuts", comment: ""),
                subTitle: NSLocalizedString("The shortcuts for opening AltTab to manage windows or applications ", comment: ""),
                width: SheetWindow.width)
        _ = table.addRow(focusWindowShortcut)
        _ = table.addRow(previousWindowShortcut)
        _ = table.addRow(cancelShortcut)
        _ = table.addRow(closeWindowShortcut)
        _ = table.addRow(minDeminWindowShortcut)
        _ = table.addRow(toggleFullscreenWindowShortcut)
        _ = table.addRow(quitAppShortcut)
        _ = table.addRow(hideShowAppShortcut)
        return table
    }

    private static func toShowSection(_ index: Int) -> ([NSView], [NSView], TableGroupSetView) {
        let appsToShow = LabelAndControl.makeDropdown(Preferences.indexToName("appsToShow", index), AppsToShowPreference.allCases)
        let spacesToShow = LabelAndControl.makeDropdown(Preferences.indexToName("spacesToShow", index), SpacesToShowPreference.allCases)
        let screensToShow = LabelAndControl.makeDropdown(Preferences.indexToName("screensToShow", index), ScreensToShowPreference.allCases)
        let showMinimizedWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showMinimizedWindows", index), ShowHowPreference.allCases)
        let showHiddenWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showHiddenWindows", index), ShowHowPreference.allCases)
        let showFullscreenWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showFullscreenWindows", index), ShowHowPreference.allCases.filter { $0 != .showAtTheEnd })
        let windowOrder = LabelAndControl.makeDropdown(Preferences.indexToName("windowOrder", index), WindowOrderPreference.allCases)

        let table1 = TableGroupView(title: NSLocalizedString("Show Windows", comment: ""), width: PreferencesWindow.width)
        _ = table1.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show windows from applications", comment: ""), rightViews: [appsToShow]))
        _ = table1.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show windows from spaces", comment: ""), rightViews: [spacesToShow]))
        _ = table1.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show windows from screens", comment: ""), rightViews: [screensToShow]))
        _ = table1.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show minimized windows", comment: ""), rightViews: [showMinimizedWindows]))
        _ = table1.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show hidden windows", comment: ""), rightViews: [showHiddenWindows]))
        _ = table1.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show fullscreen windows", comment: ""), rightViews: [showFullscreenWindows]))
        _ = table1.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show window order", comment: ""), rightViews: [windowOrder]))

        var holdShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hold", comment: ""), Preferences.indexToName("holdShortcut", index), Preferences.holdShortcut[index], false, labelPosition: .leftWithoutSeparator)
        holdShortcut.append(LabelAndControl.makeLabel(NSLocalizedString("and press", comment: "")))
        let nextWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select next window", comment: ""), Preferences.indexToName("nextWindowShortcut", index), Preferences.nextWindowShortcut[index], labelPosition: .right)
        let shortcutStyle = LabelAndControl.makeDropdown(Preferences.indexToName("shortcutStyle", index), ShortcutStylePreference.allCases)

        let table2 = TableGroupView(title: NSLocalizedString("Trigger Shortcuts", comment: ""), width: PreferencesWindow.width)
        _ = table2.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("AltTab shortcuts", comment: ""), rightViews: holdShortcut + [nextWindowShortcut[0]]))
        _ = table2.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("After release the shortcuts", comment: ""), rightViews: [shortcutStyle]))

        let view = TableGroupSetView(originalViews: [table2, table1], padding: 0)
        return (holdShortcut, nextWindowShortcut, view)
    }

    @objc static func switchTab(_ sender: NSSegmentedControl) {
        let selectedIndex = sender.selectedSegment
        ControlsTab.tabViews.enumerated().forEach { (index, view) in
            if selectedIndex == index {
                view.isHidden = false
            } else {
                view.isHidden = true
            }
        }
    }

    @objc static func showAdvancedSettings() {
        App.app.preferencesWindow.beginSheet(ControlsAdvancedWindow())
    }

    @objc static func showShortcutsSettings() {
        App.app.preferencesWindow.beginSheet(ControlsShortcutsWindow())
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
                addShortcut(.down, controlId.hasPrefix("nextWindowShortcut") ? .global : .local, Shortcut(keyEquivalent: newValue)!, controlId, nil)
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

    @objc static func vimKeysEnabledCallback(_ sender: NSControl) {
        let keyActions = [
            "h": "vimCycleLeft",
            "l": "vimCycleRight",
            "k": "vimCycleUp",
            "j": "vimCycleDown"
        ]
        if (sender as! NSButton).state == .on {
            if isClearVimKeysSuccessful() {
                keyActions.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $1, nil) }
            } else {
                (sender as! NSButton).state = .off
                Preferences.remove("vimKeysEnabled")
            }
        } else {
            keyActions.forEach { removeShortcutIfExists($1) }
        }
    }

    private static func isClearVimKeysSuccessful() -> Bool {
        let vimKeys = ["h", "l", "j", "k"]
        var conflicts = [String: String]()
        shortcuts.forEach {
            let keymap = $1.shortcut.characters
            if keymap != nil && vimKeys.contains(keymap!) {
                let control_id = $1.id
                conflicts[control_id] = shortcutControls[control_id]!.1
            }
        }
        if !conflicts.isEmpty {
            // if the app is still launching (App.app.preferencesWindow == nil) and we have a conflict
            // then we don't show the user a dialog, and simply disable vim keys
            if App.app.preferencesWindow == nil || !shouldClearConflictingShortcuts(conflicts.map { $0.value }) {
                return false
            }
            conflicts.forEach {
                removeShortcutIfExists($0.key)
                let existing = shortcutControls[$0.key]
                if existing != nil {
                    existing!.0.objectValue = nil
                    shortcutChangedCallback(existing!.0)
                    LabelAndControl.controlWasChanged(existing!.0, $0.key)
                }
            }
        }
        return true
    }

    private static func shouldClearConflictingShortcuts(_ conflicts: [String]) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("Conflicting shortcut", comment: "")
        let informativeText = conflicts.map { "• " + $0 }.joined(separator: "\n")
        alert.informativeText = String(format: NSLocalizedString("Vim keys already assigned to other actions:\n%@", comment: ""), informativeText.replacingOccurrences(of: " ", with: "\u{00A0}"))
        alert.addButton(withTitle: NSLocalizedString("Unassign existing shortcut and continue", comment: "")).setAccessibilityFocused(true)
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}"
        let userChoice = alert.runModal()
        return userChoice == .alertFirstButtonReturn
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
