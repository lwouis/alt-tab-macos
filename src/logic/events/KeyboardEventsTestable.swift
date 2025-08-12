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

@discardableResult
func handleKeyboardEvent(_ globalId: Int?, _ shortcutState: ShortcutState?, _ keyCode: UInt32?, _ modifiers: NSEvent.ModifierFlags?, _ isARepeat: Bool) -> Bool {
    // Identify event source
    let eventSource: EventSource
    if globalId != nil && shortcutState != nil {
        eventSource = .globalHotKey  // InstallEventHandler
    } else if keyCode != nil {
        eventSource = .nsEvent       // NSEvent.addLocalMonitorForEvents
    } else if modifiers != nil {
        eventSource = .cgEventTap    // cgEventFlagsChangedHandler
    } else {
        eventSource = .unknown
    }
    
    Logger.debug("Event Source:", eventSource, "globalId:", globalId, "state:", shortcutState, "keyCode:", keyCode, "modifiers:", modifiers, "isRepeat:", isARepeat, "currentModifiers:", NSEvent.modifierFlags)
    
    var someShortcutTriggered = false
    for shortcut in ControlsTab.shortcuts.values {
        if shortcut.matches(globalId, shortcutState, keyCode, modifiers) && shortcut.shouldTrigger() {
            shortcut.executeActionWithSource(isARepeat, eventSource)
            // we want to pass-through alt-up to the active app, since it saw alt-down previously
            if !shortcut.id.starts(with: "holdShortcut") {
                someShortcutTriggered = true
            }
        }
        shortcut.redundantSafetyMeasures()
    }
    // TODO if we manage to move all keyboard listening to the background thread, we'll have issues returning this boolean
    // this function uses many objects that are also used on the main-thread. It also executes the actions
    // we'll have to rework this whole approach. Today we rely on somewhat in-order events/actions
    // special attention should be given to App.app.appIsBeingUsed which is being set to true when executing the nextWindowShortcut action
    return someShortcutTriggered
}
