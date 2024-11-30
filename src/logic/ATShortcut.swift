import Cocoa
import ShortcutRecorder

class ATShortcut {
    static var lastEventIsARepeat = false
    var shortcut: Shortcut
    var id: String
    var scope: ShortcutScope
    var triggerPhase: ShortcutTriggerPhase
    var state: ShortcutState = .up
    var index: Int?

    init(_ shortcut: Shortcut, _ id: String, _ scope: ShortcutScope, _ triggerPhase: ShortcutTriggerPhase, _ index: Int? = nil) {
        self.shortcut = shortcut
        self.id = id
        self.scope = scope
        self.triggerPhase = triggerPhase
        self.index = index
    }

    func matches(_ id: Int?, _ shortcutState: ShortcutState?, _ keyCode: UInt32?, _ modifiers: NSEvent.ModifierFlags?) -> Bool {
        if let id = id, let shortcutState = shortcutState {
            let shortcutIndex = id
            let shortcutId = KeyboardEventsTestable.globalShortcutsIds.first { $0.value == shortcutIndex }!.key
            if shortcutId == self.id {
                state = shortcutState
                if (triggerPhase == .down && state == .down) || (triggerPhase == .up && state == .up) {
                    return true
                }
            }
        }
        if let modifiers = modifiers {
            let modifiersMatch_ = modifiersMatch(cocoaToCarbonFlags(modifiers))
            let newState: ShortcutState = ((shortcut.keyCode == .none || keyCode == shortcut.carbonKeyCode) && modifiersMatch_) ? .down : .up
            let flipped = state != newState
//            if self.id == "holdShortcut" {
//                logger.e(self.id, state, newState, modifiersMatch_)
//            }
            state = newState
            // state == down is unambiguous; state == up is hard to match with a particular shortcut, unless it's been flipped
            if (triggerPhase == .down && state == .down) || (triggerPhase == .up && state == .up && flipped) {
                return true
            }
        }
        return false
    }

    private func modifiersMatch(_ modifiers: UInt32) -> Bool {
        if id.hasPrefix("holdShortcut") {
            // contains at least
            return modifiers == (modifiers | shortcut.carbonModifierFlags)
        }
        let holdModifiers = ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", App.app.shortcutIndex)]!.shortcut.carbonModifierFlags
        // contains exactly or exactly + holdShortcut modifiers
        return modifiers == shortcut.carbonModifierFlags || modifiers == (shortcut.carbonModifierFlags | holdModifiers)
    }

    func shouldTrigger() -> Bool {
        if scope == .global {
//            if id == "holdShortcut" {
//                logger.e(id, triggerPhase, App.app.appIsBeingUsed, index, App.app.shortcutIndex, Preferences.shortcutStyle[App.app.shortcutIndex] == .focusOnRelease)
//            }
            if triggerPhase == .down && (!App.app.appIsBeingUsed || index == nil || index == App.app.shortcutIndex) {
                return true
            }
            if triggerPhase == .up && App.app.appIsBeingUsed && (index == nil || index == App.app.shortcutIndex) && Preferences.shortcutStyle[App.app.shortcutIndex] == .focusOnRelease {
                return true
            }
        }
        if scope == .local {
            if App.app.appIsBeingUsed && (index == nil || index == App.app.shortcutIndex) {
                return true
            }
        }
        return false
    }

    func executeAction(_ isARepeat: Bool) {
        logger.e("executeAction", id)
        ATShortcut.lastEventIsARepeat = isARepeat
        ControlsTab.executeAction(id)
    }

    /// keyboard events can be unreliable. They can arrive in the wrong order, or may never arrive
    /// this function acts as a safety net to improve the chances that some keyUp behaviors are enforced
    func redundantSafetyMeasures() {
        // Keyboard shortcuts come from different sources. As a result, they can arrive in the wrong order (e.g. alt DOWN > alt UP > alt+tab DOWN > alt+tab UP)
        // The events can be disordered between sources, but not within each source
        // Another issue is events being dropped by macOS, which we never receive
        // Knowing this, we handle these edge-cases by double checking if holdShortcut is UP, when any shortcut state is UP
        // If it is, then we trigger the holdShortcut action
        if App.app.appIsBeingUsed {
            let currentHoldShortcut = ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", App.app.shortcutIndex)]!
            if id == currentHoldShortcut.id {
                let currentModifiers = cocoaToCarbonFlags(ModifierFlags.current)
                if currentModifiers != (currentModifiers | (currentHoldShortcut.shortcut.carbonModifierFlags)) {
                    currentHoldShortcut.state = .up
                    logger.e("safetyChecksOnShortcutsUp", "holdShortcut")
                    ControlsTab.executeAction(currentHoldShortcut.id)
                }
            }
        }
        if state == .up {
            // ensure timers don't keep running if their shortcut is UP
            KeyRepeatTimer.deactivateTimerForRepeatingKey(id)
        }
    }
}

enum ShortcutTriggerPhase {
    case down
    case up
}

enum ShortcutState {
    case down
    case up
}

enum ShortcutScope {
    case global
    case local
}
