import ShortcutRecorder

class KeyboardEventsTestable {
    static let globalShortcutsIds = [
        "nextWindowShortcut": 0,
        "nextWindowShortcut2": 1,
        "nextWindowShortcut3": 2,
        "nextWindowShortcut4": 3,
        "nextWindowShortcut5": 4,
        "holdShortcut": 5,
        "holdShortcut2": 6,
        "holdShortcut3": 7,
        "holdShortcut4": 8,
        "holdShortcut5": 9,
    ]
}

@discardableResult
func handleKeyboardEvent(_ globalId: Int?, _ shortcutState: ShortcutState?, _ keyCode: UInt32?, _ modifiers: NSEvent.ModifierFlags?, _ isARepeat: Bool) -> Bool {
    Logger.debug(globalId, shortcutState, keyCode, modifiers, isARepeat, NSEvent.modifierFlags)
    var someShortcutTriggered = false
    for shortcut in ControlsTab.shortcuts.values {
        if shortcut.matches(globalId, shortcutState, keyCode, modifiers) && shortcut.shouldTrigger() {
            shortcut.executeAction(isARepeat)
            someShortcutTriggered = true
        }
        shortcut.redundantSafetyMeasures()
    }
    return someShortcutTriggered
}
