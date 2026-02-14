import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class ControlsTab {
    static var shortcuts = [String: ATShortcut]()
    static var shortcutControls = [String: (CustomRecorderControl, String)]()
    static var shortcutsActions = [
        "holdShortcut": { App.app.focusTarget() },
        "holdShortcut2": { App.app.focusTarget() },
        "holdShortcut3": { App.app.focusTarget() },
        "focusWindowShortcut": { App.app.focusTarget() },
        "nextWindowShortcut": { App.app.showUiOrCycleSelection(0, false) },
        "nextWindowShortcut2": { App.app.showUiOrCycleSelection(1, false) },
        "nextWindowShortcut3": { App.app.showUiOrCycleSelection(2, false) },
        "previousWindowShortcut": { App.app.previousWindowShortcutWithRepeatingKey() },
        "→": { App.app.cycleSelection(.right) },
        "←": { App.app.cycleSelection(.left) },
        "↑": { App.app.cycleSelection(.up) },
        "↓": { App.app.cycleSelection(.down) },
        "vimCycleRight": { App.app.cycleSelection(.right) },
        "vimCycleLeft": { App.app.cycleSelection(.left) },
        "vimCycleUp": { App.app.cycleSelection(.up) },
        "vimCycleDown": { App.app.cycleSelection(.down) },
        "cancelShortcut": { App.app.cancelSearchModeOrHideUi() },
        "closeWindowShortcut": { App.app.closeSelectedWindow() },
        "minDeminWindowShortcut": { App.app.minDeminSelectedWindow() },
        "toggleFullscreenWindowShortcut": { App.app.toggleFullscreenSelectedWindow() },
        "quitAppShortcut": { App.app.quitSelectedApp() },
        "hideShowAppShortcut": { App.app.hideShowSelectedApp() },
        "searchShortcut": { App.app.toggleSearchMode() },
        "lockSearchShortcut": { App.app.lockSearchMode() },
    ]
    static var arrowKeysCheckbox: Switch!
    static var vimKeysCheckbox: Switch!

    static var tableGroupViews: [TableGroupView]!

    static var shortcutsWhenActiveSheet: ShortcutsWhenActiveSheet!
    static var additionalControlsSheet: AdditionalControlsSheet!
    private static let managedShortcutPreferences = [
        "holdShortcut", "holdShortcut2", "holdShortcut3",
        "nextWindowShortcut", "nextWindowShortcut2", "nextWindowShortcut3",
        "focusWindowShortcut", "previousWindowShortcut", "cancelShortcut", "searchShortcut", "lockSearchShortcut",
        "closeWindowShortcut", "minDeminWindowShortcut", "toggleFullscreenWindowShortcut", "quitAppShortcut", "hideShowAppShortcut",
    ]
    private static let arrowKeys = ["←", "→", "↑", "↓"]
    private static let vimKeyActions = [
        "h": "vimCycleLeft",
        "l": "vimCycleRight",
        "k": "vimCycleUp",
        "j": "vimCycleDown",
    ]

    static func initializePreferencesDependentState() {
        managedShortcutPreferences.forEach { applyShortcutPreference($0) }
        applyArrowKeysPreference()
        applyVimKeysPreferenceWithoutDialogs()
    }

    static func preferenceChanged(_ key: String) {
        switch key {
        case let k where managedShortcutPreferences.contains(k): applyShortcutPreference(k)
        case "arrowKeysEnabled": applyArrowKeysPreference()
        case "vimKeysEnabled" where vimKeysCheckbox == nil: applyVimKeysPreferenceWithoutDialogs()
        default: break
        }
    }

    static func initTab() -> NSView {
        let (holdShortcut, nextWindowShortcut, tab1View) = shortcutTab(0)
        let (holdShortcut2, nextWindowShortcut2, tab2View) = shortcutTab(1)
        let (holdShortcut3, nextWindowShortcut3, tab3View) = shortcutTab(2)
        let tab6View = gestureTab(Preferences.gestureIndex)
        tableGroupViews = [tab1View, tab2View, tab3View, tab6View]
        // trigger shortcutChanged for these shortcuts to trigger .restrictModifiers
        [holdShortcut, holdShortcut2, holdShortcut3].forEach { ControlsTab.shortcutChangedCallback($0[1] as! NSControl) }
        [nextWindowShortcut, nextWindowShortcut2, nextWindowShortcut3].forEach { ControlsTab.shortcutChangedCallback($0[0] as! NSControl) }
        let tabs = StackView(tableGroupViews, .vertical)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.fit()
        let table = TableGroupView(hasHeader: true, width: PreferencesWindow.width)
        let tab = NSSegmentedControl(labels: [
            NSLocalizedString("Shortcut 1", comment: ""),
            NSLocalizedString("Shortcut 2", comment: ""),
            NSLocalizedString("Shortcut 3", comment: ""),
            NSLocalizedString("Gesture", comment: ""),
        ], trackingMode: .selectOne, target: self, action: #selector(switchTab(_:)))
        tab.selectedSegment = 0
        tab.segmentStyle = .automatic
        tab.widthAnchor.constraint(equalToConstant: PreferencesWindow.width).isActive = true
        table.addHeader(views: [tab])
        let additionalControlsButton = NSButton(title: NSLocalizedString("Additional controls…", comment: ""), target: self, action: #selector(ControlsTab.showAdditionalControlsSettings))
        let shortcutsButton = NSButton(title: NSLocalizedString("Shortcuts when active…", comment: ""), target: self, action: #selector(ControlsTab.showShortcutsSettings))
        let tools = StackView([additionalControlsButton, shortcutsButton], .horizontal)
        let view = TableGroupSetView(originalViews: [table, tab1View, tab2View, tab3View, tab6View], toolsViews: [tools], toolsAlignment: .trailing)
        view.translatesAutoresizingMaskIntoConstraints = false
        shortcutsWhenActiveSheet = ShortcutsWhenActiveSheet()
        additionalControlsSheet = AdditionalControlsSheet()
        ControlsTab.switchIndexTab(0)
        view.fit()
        return view
    }

    private static func shortcutTab(_ index: Int) -> ([NSView], [NSView], TableGroupView) {
        var holdShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hold", comment: ""), Preferences.indexToName("holdShortcut", index), Preferences.holdShortcut[index], false, labelPosition: .leftWithoutSeparator)
        holdShortcut.append(LabelAndControl.makeLabel(NSLocalizedString("and press", comment: "")))
        let nextWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select next window", comment: ""), Preferences.indexToName("nextWindowShortcut", index), Preferences.nextWindowShortcut[index], labelPosition: .right)
        let tab = controlTab(index, holdShortcut + [nextWindowShortcut[0]])
        return (holdShortcut, nextWindowShortcut, tab)
    }

    private static func gestureTab(_ index: Int) -> TableGroupView {
        let label = NSLocalizedString("You may need to disable some conflicting system gestures", comment: "")
        let button = NSButton(title: NSLocalizedString("Open Trackpad Settings…", comment: ""), target: self, action: #selector(openSystemGestures(_:)))
        let infoBtn = LabelAndControl.makeInfoButton(onMouseEntered: { event, view in
            Popover.shared.show(event: event, positioningView: view, message: label, extraView: button)
        })
        let gesture = LabelAndControl.makeDropdown("nextWindowGesture", GesturePreference.allCases)
        let gestureWithTooltip = NSStackView()
        gestureWithTooltip.orientation = .horizontal
        gestureWithTooltip.alignment = .centerY
        // this is a trick to get the height of that row to be consistent when switching between the tabs
        let dummyRecorderForHeight = CustomRecorderControl("d", true, "dummy")
        gestureWithTooltip.setViews([gesture, dummyRecorderForHeight], in: .trailing)
        gestureWithTooltip.setViews([infoBtn], in: .leading)
        gestureWithTooltip.heightAnchor.constraint(equalTo: dummyRecorderForHeight.heightAnchor).isActive = true
        dummyRecorderForHeight.isHidden = true
        return controlTab(index, [gestureWithTooltip])
    }

    private static func controlTab(_ index: Int, _ trigger: [NSView]) -> TableGroupView {
        let appsToShow = LabelAndControl.makeDropdown(Preferences.indexToName("appsToShow", index), AppsToShowPreference.allCases)
        let spacesToShow = LabelAndControl.makeDropdown(Preferences.indexToName("spacesToShow", index), SpacesToShowPreference.allCases)
        let screensToShow = LabelAndControl.makeDropdown(Preferences.indexToName("screensToShow", index), ScreensToShowPreference.allCases)
        let showMinimizedWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showMinimizedWindows", index), ShowHowPreference.allCases)
        let showHiddenWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showHiddenWindows", index), ShowHowPreference.allCases)
        let showFullscreenWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showFullscreenWindows", index), ShowHowPreference.allCases.filter { $0 != .showAtTheEnd }) // this filter is ok for serialization because the filtered value is last in the enum
        let showWindowlessApps = LabelAndControl.makeDropdown(Preferences.indexToName("showWindowlessApps", index), ShowHowPreference.allCases)
        let windowOrder = LabelAndControl.makeDropdown(Preferences.indexToName("windowOrder", index), WindowOrderPreference.allCases)
        let shortcutStyle = LabelAndControl.makeDropdown(Preferences.indexToName("shortcutStyle", index), ShortcutStylePreference.allCases)
        let table = TableGroupView(width: PreferencesWindow.width)
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Trigger shortcut", comment: ""), rightViews: trigger))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("After release", comment: ""), rightViews: [shortcutStyle]))
        table.addNewTable()
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from applications", comment: ""))], rightViews: [appsToShow])
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from Spaces", comment: ""))], rightViews: [spacesToShow])
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Show windows from screens", comment: ""))], rightViews: [screensToShow])
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show minimized windows", comment: ""), rightViews: [showMinimizedWindows]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show hidden windows", comment: ""), rightViews: [showHiddenWindows]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show fullscreen windows", comment: ""), rightViews: [showFullscreenWindows]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Show apps with no open window", comment: ""), rightViews: [showWindowlessApps]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Order windows by", comment: ""), rightViews: [windowOrder]))
        table.fit()
        return table
    }

    @objc static func switchTab(_ sender: NSSegmentedControl) {
        let selectedIndex = sender.selectedSegment
        switchIndexTab(selectedIndex)
    }

    static func switchIndexTab(_ selectedIndex: Int) {
        ControlsTab.tableGroupViews.enumerated().forEach { (index, view) in
            if selectedIndex == index {
                view.isHidden = false
            } else {
                view.isHidden = true
            }
        }
    }

    @objc static func showShortcutsSettings() {
        App.app.preferencesWindow.beginSheet(shortcutsWhenActiveSheet)
    }

    @objc static func showAdditionalControlsSettings() {
        App.app.preferencesWindow.beginSheet(additionalControlsSheet)
    }

    private static func addShortcut(_ triggerPhase: ShortcutTriggerPhase, _ scope: ShortcutScope, _ shortcut: Shortcut, _ controlId: String, _ index: Int?) {
        let atShortcut = ATShortcut(shortcut, controlId, scope, triggerPhase, index)
        removeShortcutIfExists(controlId) // remove the previous shortcut
        shortcuts[controlId] = atShortcut
        if scope == .global {
            KeyboardEvents.addGlobalShortcut(controlId, atShortcut.shortcut)
            ControlsTab.toggleNativeCommandTabIfNeeded()
        }
    }

    static func toggleNativeCommandTabIfNeeded() {
        let nativeHotkeys: [CGSSymbolicHotKey: (Shortcut) -> Bool] = [
            .commandTab: { (shortcut) in shortcut.carbonModifierFlags == cmdKey && shortcut.carbonKeyCode == kVK_Tab },
            .commandShiftTab: { (shortcut) in CustomRecorderControlTestable.combinedModifiersMatch(shortcut.carbonModifierFlags, UInt32(cmdKey | shiftKey)) && shortcut.carbonKeyCode == kVK_Tab },
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
            let newShortcut = Shortcut(keyEquivalent: newValue)
            if newValue.isEmpty || newShortcut == nil {
                removeShortcutIfExists(controlId)
                restrictModifiersOfHoldShortcut(controlId, [])
                (sender as! CustomRecorderControl).objectValue = nil
            } else {
                addShortcut(.down, controlId.hasPrefix("nextWindowShortcut") ? .global : .local, newShortcut!, controlId, nil)
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
        applyArrowKeysPreference()
    }

    @objc static func vimKeysEnabledCallback(_ sender: NSControl) {
        if (sender as! Switch).state == .on {
            if isClearVimKeysSuccessful() {
                vimKeyActions.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $1, nil) }
            } else {
                (sender as! Switch).state = .off
                Preferences.remove("vimKeysEnabled")
            }
        } else {
            vimKeyActions.forEach { removeShortcutIfExists($1) }
        }
    }

    private static func isClearVimKeysSuccessful() -> Bool {
        var conflicts = [String: String]()
        shortcuts.forEach {
            let keymap = $1.shortcut.characters
            if keymap != nil && vimKeyActions.keys.contains(keymap!) {
                let control_id = $1.id
                guard !vimKeyActions.values.contains(control_id) else { return }
                if let label = conflictLabel(control_id) {
                    conflicts[control_id] = label
                }
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

    private static func conflictLabel(_ controlId: String) -> String? {
        if let shortcutControl = shortcutControls[controlId] {
            return shortcutControl.1
        }
        if arrowKeys.contains(controlId) {
            return NSLocalizedString("Arrow keys", comment: "")
        }
        if vimKeyActions.values.contains(controlId) {
            return NSLocalizedString("Vim keys", comment: "")
        }
        return nil
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
            if atShortcut.scope == .global {
                ControlsTab.toggleNativeCommandTabIfNeeded()
            }
        }
    }

    private static func applyShortcutPreference(_ controlId: String) {
        if controlId.hasPrefix("holdShortcut") {
            applyHoldShortcutPreference(controlId)
            applyShortcutPreference(Preferences.indexToName("nextWindowShortcut", Preferences.nameToIndex(controlId)))
            return
        }
        let shortcutString = combinedShortcutString(controlId)
        guard !shortcutString.isEmpty, let shortcut = Shortcut(keyEquivalent: shortcutString) else {
            removeShortcutIfExists(controlId)
            restrictModifiersOfHoldShortcut(controlId, [])
            return
        }
        addShortcut(.down, controlId.hasPrefix("nextWindowShortcut") ? .global : .local, shortcut, controlId, nil)
        restrictModifiersOfHoldShortcut(controlId, [shortcut.modifierFlags])
    }

    private static func applyHoldShortcutPreference(_ controlId: String) {
        let i = Preferences.nameToIndex(controlId)
        guard let shortcut = Shortcut(keyEquivalent: Preferences.holdShortcut[i]) else {
            removeShortcutIfExists(controlId)
            return
        }
        addShortcut(.up, .global, shortcut, controlId, i)
    }

    private static func combinedShortcutString(_ controlId: String) -> String {
        guard let baseValue = UserDefaults.standard.string(forKey: controlId), !baseValue.isEmpty else {
            return ""
        }
        if controlId.starts(with: "nextWindowShortcut") {
            let holdShortcut = Preferences.holdShortcut[Preferences.nameToIndex(controlId)]
            return holdShortcut + baseValue
        }
        return baseValue
    }

    private static func applyArrowKeysPreference() {
        if Preferences.arrowKeysEnabled {
            arrowKeys.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $0, nil) }
        } else {
            arrowKeys.forEach { removeShortcutIfExists($0) }
        }
    }

    private static func applyVimKeysPreferenceWithoutDialogs() {
        guard Preferences.vimKeysEnabled else {
            vimKeyActions.forEach { removeShortcutIfExists($1) }
            return
        }
        if hasVimKeysConflictWithoutUi() {
            vimKeyActions.forEach { removeShortcutIfExists($1) }
            Preferences.set("vimKeysEnabled", "false", false)
            return
        }
        vimKeyActions.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $1, nil) }
    }

    private static func hasVimKeysConflictWithoutUi() -> Bool {
        return shortcuts.values.contains {
            if let key = $0.shortcut.characters, vimKeyActions.keys.contains(key) {
                return !vimKeyActions.values.contains($0.id)
            }
            return false
        }
    }

    @objc private static func openSystemGestures(_ sender: NSButton) {
        // Apple doesn't expose the More Gestures tab directly
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
    }

    static func executeAction(_ action: String) {
        shortcutsActions[action]!()
    }
}
