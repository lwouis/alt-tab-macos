import Cocoa
import ShortcutRecorder

class ATShortcut {
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

    func matches(_ id: EventHotKeyID?, _ shortcutState: ShortcutState?, _ keyCode: UInt32?, _ modifiers: UInt32?, _ isARepeat: Bool) -> Bool {
        if let id = id, let shortcutState = shortcutState {
            let shortcutIndex = Int(id.id)
            let shortcutId = Array(KeyboardEvents.globalShortcutsIds).first { $0.value == shortcutIndex }!.key
            if shortcutId == self.id {
                state = state == .down ? .up : .down
                if state == .up {
                    KeyRepeatTimer.timer?.invalidate()
                }
                if (triggerPhase == .down && shortcutState == .down) || (triggerPhase == .up && shortcutState == .up) {
                    return true
                }
            }
        }
        if let modifiers = modifiers {
            let modifiersMatch_ = modifiersMatch(modifiers)
            let flipped = (state == .up && (shortcut.keyCode == .none || keyCode == shortcut.carbonKeyCode) && modifiersMatch_) ||
                (state == .down && ((shortcut.keyCode != .none && keyCode != shortcut.carbonKeyCode) || !modifiersMatch_))
            if flipped {
                state = state == .down ? .up : .down
                if state == .up {
                    KeyRepeatTimer.timer?.invalidate()
                }
            }
            if (flipped || isARepeat) && ((triggerPhase == .up && state == .up) || (triggerPhase == .down && state == .down)) {
                return true
            }
        }
        return false
    }

    func modifiersMatch(_ modifiers: UInt32) -> Bool {
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
            if triggerPhase == .down && (!App.app.appIsBeingUsed || index == nil || index == App.app.shortcutIndex) {
                App.app.appIsBeingUsed = true
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            KeyRepeatTimer.isARepeat = isARepeat
            ControlsTab.shortcutsActions[self.id]!()
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
