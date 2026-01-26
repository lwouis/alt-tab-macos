import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class KeyboardEventsTestable {
    static let globalShortcutsIds = [
        "nextWindowShortcut": 0,
        "nextWindowShortcut2": 1,
        "nextWindowShortcut3": 2,
        "holdShortcut": 5,
        "holdShortcut2": 6,
        "holdShortcut3": 7,
    ]
}

/// Simple priority: ensure search-enter outranks search-exit and others when not editing.
private func shortcutPriority(_ id: String) -> Int {
    if id == "searchToggleShortcut" { return 0 }
    // Keep everything else at a lower priority; ties resolved by id for determinism
    return 10
}

private func isNonPrintableKeyCode(_ keyCode: UInt32) -> Bool {
    switch keyCode {
    case UInt32(kVK_Return),
         UInt32(kVK_ANSI_KeypadEnter),
         UInt32(kVK_Tab),
         UInt32(kVK_Escape),
         UInt32(kVK_Delete),
         UInt32(kVK_ForwardDelete),
         UInt32(kVK_Home),
         UInt32(kVK_End),
         UInt32(kVK_PageUp),
         UInt32(kVK_PageDown),
         UInt32(kVK_LeftArrow),
         UInt32(kVK_RightArrow),
         UInt32(kVK_UpArrow),
         UInt32(kVK_DownArrow),
         UInt32(kVK_Help),
         UInt32(kVK_Function),
         UInt32(kVK_F1),
         UInt32(kVK_F2),
         UInt32(kVK_F3),
         UInt32(kVK_F4),
         UInt32(kVK_F5),
         UInt32(kVK_F6),
         UInt32(kVK_F7),
         UInt32(kVK_F8),
         UInt32(kVK_F9),
         UInt32(kVK_F10),
         UInt32(kVK_F11),
         UInt32(kVK_F12),
         UInt32(kVK_F13),
         UInt32(kVK_F14),
         UInt32(kVK_F15),
         UInt32(kVK_F16),
         UInt32(kVK_F17),
         UInt32(kVK_F18),
         UInt32(kVK_F19),
         UInt32(kVK_F20):
        return true
    default:
        return false
    }
}

@discardableResult
func handleKeyboardEvent(_ globalId: Int?, _ shortcutState: ShortcutState?, _ keyCode: UInt32?, _ modifiers: NSEvent.ModifierFlags?, _ isARepeat: Bool) -> Bool {
    if let globalId, let shortcutState {
        Logger.debug {
            let shortcut = KeyboardEventsTestable.globalShortcutsIds.first { $0.value == globalId }
            return "globalShortcut:\(shortcut?.key ?? "") state:\(shortcutState)"
        }
    } else {
        // TODO: use proper pattern from SwiftBeaver to not compute SymbolicModifierFlagsTransformer when logs are off
        Logger.debug {
            let modifiersAsString = modifiers.flatMap { SymbolicModifierFlagsTransformer.shared.transformedValue(NSNumber(value: $0.rawValue)) }
            let keyCodeAsString = keyCode.flatMap { SymbolicKeyCodeTransformer.shared.transformedValue(NSNumber(value: $0)) }
            return "keys:\(modifiersAsString ?? "")\(keyCodeAsString ?? "") isARepeat:\(isARepeat)"
        }
    }
    // While typing in the search field, allow a small, explicit set of shortcuts:
    // - Toggle search (takes precedence if it matches)
    // - Focus selected window (e.g., Enter)
    // - Escape always exits search
    if App.app != nil,
       App.app.appIsBeingUsed,
       App.app.thumbnailsPanel != nil,
       App.app.thumbnailsPanel.isKeyWindow,
       App.app.thumbnailsPanel.thumbnailsView.searchField.currentEditor() != nil {
        if let keyCode, keyCode == UInt32(kVK_Escape) {
            App.app.thumbnailsPanel.thumbnailsView.exitSearchFocus()
            return true
        }
        if let toggleShortcut = ControlsTab.shortcuts["searchToggleShortcut"],
           toggleShortcut.matches(globalId, shortcutState, keyCode, modifiers) && toggleShortcut.shouldTrigger() {
            if let keyCode, isNonPrintableKeyCode(keyCode) {
                toggleShortcut.executeAction(isARepeat)
                toggleShortcut.redundantSafetyMeasures()
                return true
            }
            return false
        }
        if let focusShortcut = ControlsTab.shortcuts["focusWindowShortcut"],
           focusShortcut.matches(globalId, shortcutState, keyCode, modifiers) && focusShortcut.shouldTrigger() {
            if Windows.list.firstIndex(where: { Windows.shouldDisplay($0) }) != nil {
                if let keyCode, isNonPrintableKeyCode(keyCode) {
                    focusShortcut.executeAction(isARepeat)
                } else {
                    return false
                }
            }
            focusShortcut.redundantSafetyMeasures()
            return true
        }
        return false
    }
    var someShortcutTriggered = false
    // Deterministic ordering: by priority then id; execute only the first match.
    let orderedShortcuts = ControlsTab.shortcuts.values.sorted { (a, b) -> Bool in
        let pa = shortcutPriority(a.id)
        let pb = shortcutPriority(b.id)
        return pa == pb ? a.id < b.id : pa < pb
    }
    for shortcut in orderedShortcuts {
        let isMatch = shortcut.matches(globalId, shortcutState, keyCode, modifiers)
        if isMatch && shortcut.shouldTrigger() && !someShortcutTriggered {
            shortcut.executeAction(isARepeat)
            // we want to pass-through alt-up to the active app, since it saw alt-down previously
            if !shortcut.id.starts(with: "holdShortcut") {
                someShortcutTriggered = true
            }
        }
        // Always run safety to keep timers/state consistent even if not executed
        shortcut.redundantSafetyMeasures()
    }
    // TODO if we manage to move all keyboard listening to the background thread, we'll have issues returning this boolean
    // this function uses many objects that are also used on the main-thread. It also executes the actions
    // we'll have to rework this whole approach. Today we rely on somewhat in-order events/actions
    // special attention should be given to App.app.appIsBeingUsed which is being set to true when executing the nextWindowShortcut action
    return someShortcutTriggered
}
