import Cocoa
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
    if id == "searchEnterShortcut" { return 0 }
    if id == "searchExitShortcut" { return 1 }
    // Keep everything else at a lower priority; ties resolved by id for determinism
    return 10
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
    // - Exit search (with safety: suppressed if same key as Enter Search)
    // - Focus selected window (e.g., Space by default)
    // - Cancel (e.g., Escape by default)
    if App.app != nil,
       App.app.appIsBeingUsed,
       App.app.thumbnailsPanel != nil,
       App.app.thumbnailsPanel.isKeyWindow,
       App.app.thumbnailsPanel.thumbnailsView.searchField.currentEditor() != nil {
        if let exitShortcut = ControlsTab.shortcuts["searchExitShortcut"],
           exitShortcut.matches(globalId, shortcutState, keyCode, modifiers) && exitShortcut.shouldTrigger() {
            // Centralized rule: suppress exit if Enter and Exit share same key while typing
            if !allowSearchExitWhileTyping() { return false }
            exitShortcut.executeAction(isARepeat)
            exitShortcut.redundantSafetyMeasures()
            return true
        }
        if let focusShortcut = ControlsTab.shortcuts["focusWindowShortcut"],
           focusShortcut.matches(globalId, shortcutState, keyCode, modifiers) && focusShortcut.shouldTrigger() {
            if Windows.list.firstIndex(where: { Windows.shouldDisplay($0) }) != nil {
                focusShortcut.executeAction(isARepeat)
            }
            focusShortcut.redundantSafetyMeasures()
            return true
        }
        if let cancelShortcut = ControlsTab.shortcuts["cancelShortcut"],
           cancelShortcut.matches(globalId, shortcutState, keyCode, modifiers) && cancelShortcut.shouldTrigger() {
            cancelShortcut.executeAction(isARepeat)
            cancelShortcut.redundantSafetyMeasures()
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

/// Policy: whether exiting search is allowed while the search field is actively being edited.
/// We suppress exit if Enter and Exit share the same key and modifiers to avoid prematurely leaving search.
func allowSearchExitWhileTyping() -> Bool {
    guard let exit = ControlsTab.shortcuts["searchExitShortcut"]?.shortcut,
          let enter = ControlsTab.shortcuts["searchEnterShortcut"]?.shortcut else { return true }
    if enter.carbonKeyCode == exit.carbonKeyCode &&
       ControlsTab.combinedModifiersMatch(enter.carbonModifierFlags, exit.carbonModifierFlags) {
        return false
    }
    return true
}
