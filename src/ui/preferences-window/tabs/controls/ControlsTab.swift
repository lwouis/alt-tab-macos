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
    static var arrowKeysCheckbox: Switch!
    static var vimKeysCheckbox: Switch!

    static var tableGroupViews: [TableGroupView]!

    static var shortcutsWhenActiveSheet: ShortcutsWhenActiveSheet!
    static var additionalControlsSheet: AdditionalControlsSheet!

    static func initTab() -> NSView {
        let (holdShortcut, nextWindowShortcut, tab1View) = shortcutTab(0)
        let (holdShortcut2, nextWindowShortcut2, tab2View) = shortcutTab(1)
        let (holdShortcut3, nextWindowShortcut3, tab3View) = shortcutTab(2)
        let (holdShortcut4, nextWindowShortcut4, tab4View) = shortcutTab(3)
        let (holdShortcut5, nextWindowShortcut5, tab5View) = shortcutTab(4)
        let (gesture, tab6View) = gestureTab(5)
        tableGroupViews = [tab1View, tab2View, tab3View, tab4View, tab5View, tab6View]
        // trigger shortcutChanged for these shortcuts to trigger .restrictModifiers
        [holdShortcut, holdShortcut2, holdShortcut3, holdShortcut4, holdShortcut5].forEach { ControlsTab.shortcutChangedCallback($0[1] as! NSControl) }
        [nextWindowShortcut, nextWindowShortcut2, nextWindowShortcut3, nextWindowShortcut4, nextWindowShortcut5].forEach { ControlsTab.shortcutChangedCallback($0[0] as! NSControl) }
        [gesture].forEach { ControlsTab.gestureChangedCallback($0[0] as! NSControl) }

        let tabs = StackView(tableGroupViews, .vertical)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.fit()

        let table = TableGroupView(hasHeader: true, width: PreferencesWindow.width)
        let tab = NSSegmentedControl(labels: [
            NSLocalizedString("Shortcut 1", comment: ""),
            NSLocalizedString("Shortcut 2", comment: ""),
            NSLocalizedString("Shortcut 3", comment: ""),
            NSLocalizedString("Shortcut 4", comment: ""),
            NSLocalizedString("Shortcut 5", comment: ""),
            NSLocalizedString("Gesture", comment: ""),
        ], trackingMode: .selectOne, target: self, action: #selector(switchTab(_:)))
        tab.selectedSegment = 0
        tab.segmentStyle = .automatic
        tab.widthAnchor.constraint(equalToConstant: PreferencesWindow.width).isActive = true
        table.addHeader(views: [tab])

        let additionalControlsButton = NSButton(title: NSLocalizedString("Additional controls…", comment: ""), target: self, action: #selector(ControlsTab.showAdditionalControlsSettings))
        let shortcutsButton = NSButton(title: NSLocalizedString("Shortcuts when active…", comment: ""), target: self, action: #selector(ControlsTab.showShortcutsSettings))
        let tools = StackView([additionalControlsButton, shortcutsButton], .horizontal)
        let view = TableGroupSetView(originalViews: [table, tab1View, tab2View, tab3View, tab4View, tab5View, tab6View], toolsViews: [tools], toolsAlignment: .trailing)
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

    private static func gestureTab(_ index: Int) -> ([NSView], TableGroupView) {
        let gesture = LabelAndControl.makeDropdown("gesture", GesturePreference.allCases, extraAction: ControlsTab.gestureChangedCallback)
        
        let infoBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        if #available(macOS 11.0, *) {
            infoBtn.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        } else {
            let infoImage = NSImage(named: NSImage.infoName)?
                .copy() as? NSImage
            infoImage?.size = NSSize(width: 18, height: 18)
            infoBtn.image = infoImage
        }
        infoBtn.bezelStyle = .inline
        infoBtn.isBordered = false
        infoBtn.target = self
        infoBtn.action = #selector(showGestureInfo(_:))
        
        let gestureWithTooltip = StackView([infoBtn, gesture], .horizontal)
        gestureWithTooltip.spacing = 8
        gestureWithTooltip.alignment = .centerY
        
        let tab = controlTab(index, [gestureWithTooltip])
        return ([gesture], tab)
    }

    private static func controlTab(_ index: Int, _ trigger: [NSView]) -> TableGroupView {
        let appsToShow = LabelAndControl.makeDropdown(Preferences.indexToName("appsToShow", index), AppsToShowPreference.allCases)
        let spacesToShow = LabelAndControl.makeDropdown(Preferences.indexToName("spacesToShow", index), SpacesToShowPreference.allCases)
        let screensToShow = LabelAndControl.makeDropdown(Preferences.indexToName("screensToShow", index), ScreensToShowPreference.allCases)
        let showMinimizedWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showMinimizedWindows", index), ShowHowPreference.allCases)
        let showHiddenWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showHiddenWindows", index), ShowHowPreference.allCases)
        let showFullscreenWindows = LabelAndControl.makeDropdown(Preferences.indexToName("showFullscreenWindows", index), ShowHowPreference.allCases.filter { $0 != .showAtTheEnd })
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
        }
        toggleNativeCommandTabIfNeeded()
    }

    /// commandTab and commandKeyAboveTab are self-contained in the "nextWindowShortcut" shortcuts
    /// but the keys of commandShiftTab can be spread between holdShortcut and a local shortcut
    static func combinedModifiersMatch(_ modifiers1: UInt32, _ modifiers2: UInt32) -> Bool {
        return (0..<Preferences.holdShortcut.count).contains {
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
        if (sender as! Switch).state == .on {
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
        if (sender as! Switch).state == .on {
            if isClearVimKeysSuccessful() {
                keyActions.forEach { addShortcut(.down, .local, Shortcut(keyEquivalent: $0)!, $1, nil) }
            } else {
                (sender as! Switch).state = .off
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

    @objc static func gestureChangedCallback(_ sender: NSControl) {
        guard let value = LabelAndControl.getControlValue(sender, nil),
              let intValue = Int(value),
              intValue < GesturePreference.allCases.count else {
            return
        }
        let swipe = GesturePreference.allCases[intValue]
        switch swipe {
            case .none: TrackpadEvents.toggle(false)
            case .threeFingerSwipe: TrackpadEvents.toggle(true)
            case .fourFingerSwipe: TrackpadEvents.toggle(true)
        }
    }

    @objc private static func showGestureInfo(_ sender: NSButton) {
        let popover = NSPopover()
        let label = NSTextField(wrappingLabelWithString: NSLocalizedString("Swipe may conflict with system shortcuts.\nCheck for any conflicts within System Settings > Trackpad > More Gestures.", comment: ""))
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 0))
        let openBtn = NSButton(title: NSLocalizedString("Open", comment: ""), target: self, action: #selector(openSystemGestures(_:)))
        let stack = StackView([label, openBtn], .vertical)
        stack.alignment = .centerX
        container.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])
        
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = container
        popover.behavior = .transient
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private static func openSystemGestures(_ sender: NSButton) {
        // Apple doesn't expose the More Gestures tab directly
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
    }

    static func executeAction(_ action: String) {
        shortcutsActions[action]!()
    }
}
