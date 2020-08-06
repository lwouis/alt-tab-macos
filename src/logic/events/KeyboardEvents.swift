import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

fileprivate var eventTap: CFMachPort?

class KeyboardEvents {
    static func observe() {
        observe_()
    }
}

private func observe_() {
    let eventMask = [CGEventType.keyDown, CGEventType.keyUp, CGEventType.flagsChanged].reduce(CGEventMask(0), { $0 | (1 << $1.rawValue) })
    // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass
    eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: keyboardHandler,
        userInfo: nil)
    // permission can have been removed before SystemPermissions timer triggers, thus we check and restart if needed
    if eventTap == nil { App.app.restart() }
    let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
    CFRunLoopAddSource(BackgroundWork.keyboardEventsThread.runLoop, runLoopSource, .commonModes)
}

private func keyboardHandler(_: CGEventTapProxy, type: CGEventType, cgEvent: CGEvent, _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if (type == .keyDown || type == .keyUp || type == .flagsChanged) && !App.app.shortcutsShouldBeDisabled {
        if let event = NSEvent(cgEvent: cgEvent) {
            let appWasBeingUsed = App.app.appIsBeingUsed
            if let shortcut = shortcutThatMatches(event, type) {
                if shortcut.hasPrefix("nextWindowShortcut") {
                    App.app.appIsBeingUsed = true
                } else if shortcut.hasPrefix("holdShortcut") || shortcut == "cancelShortcut" || shortcut == "focusWindowShortcut" {
                    App.app.appIsBeingUsed = false
                    App.app.isFirstSummon = true
                }
                DispatchQueue.main.async { () -> () in ControlsTab.shortcutsActions[shortcut]!() }
            }
            if appWasBeingUsed || App.app.appIsBeingUsed {
                return nil // focused app won't receive the event
            }
        }
    } else if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    return Unmanaged.passRetained(cgEvent) // focused app will receive the event
}

// shortcutMonitor.handle only does exact matching; we match manually to allow flexible matching
// see https://github.com/lwouis/alt-tab-macos/issues/230
private func shortcutThatMatches(_ event: NSEvent, _ type: CGEventType) -> String? {
    for shortcutId in ControlsTab.shortcuts.keys {
        let postfix = App.app.shortcutIndex == 0 ? "" : "2"
        let shortcut = ControlsTab.shortcuts[shortcutId]!
        if shortcutId.hasPrefix("holdShortcut") {
            if event.sr_keyEventType == .up && type == .flagsChanged && shortcut.keyCode == .none && event.modifierFlags.isDisjoint(with: shortcut.modifierFlags) &&
                   shortcutId == "holdShortcut" + postfix && App.app.appIsBeingUsed && Preferences.shortcutStyle == .focusOnRelease {
                return shortcutId
            }
        } else if event.sr_keyEventType == .down && (shortcut.keyCode == .none || event.keyCode == shortcut.carbonKeyCode) {
            if shortcutId.hasPrefix("nextWindowShortcut") {
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == shortcut.modifierFlags &&
                       (!App.app.appIsBeingUsed || shortcutId == "nextWindowShortcut" + postfix) {
                    return shortcutId
                }
            } else {
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(shortcut.modifierFlags) &&
                       App.app.appIsBeingUsed {
                    return shortcutId
                }
            }
        }
    }
    return nil
}
