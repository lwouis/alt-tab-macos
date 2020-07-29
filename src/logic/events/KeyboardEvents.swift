import Cocoa
import Carbon.HIToolbox.Events

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
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(BackgroundWork.keyboardEventsThread.runLoop, runLoopSource, .commonModes)
}

private func keyboardHandler(_: CGEventTapProxy, type: CGEventType, cgEvent: CGEvent, _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if (type == .keyDown || type == .keyUp || type == .flagsChanged) && !App.app.shortcutsShouldBeDisabled {
        if let event_ = NSEvent(cgEvent: cgEvent),
           // workaround: NSEvent.characters is not safe outside of the main thread; this is not documented by Apple
            // see https://github.com/Kentzo/ShortcutRecorder/issues/114#issuecomment-606465340
           let event = NSEvent.keyEvent(with: event_.type, location: event_.locationInWindow, modifierFlags: event_.modifierFlags,
               timestamp: event_.timestamp, windowNumber: event_.windowNumber, context: nil, characters: "",
               charactersIgnoringModifiers: "", isARepeat: type == .flagsChanged ? false : event_.isARepeat, keyCode: event_.keyCode) {
            let appWasBeingUsed = App.app.appIsBeingUsed
            // ShortcutRecorder handles only exact matches for modifiers-only .up shortcuts. We want to activate holdShortcut even if other modifiers are still pressed
            // see https://github.com/lwouis/alt-tab-macos/issues/230
            let holdShortcutAction = GeneralTab.shortcutActions["holdShortcut"]!
            let holdShortcut = holdShortcutAction.shortcut!
            if holdShortcut.keyCode == .none && type == .flagsChanged && event.sr_keyEventType == .up &&
                   event.modifierFlags.isDisjoint(with: holdShortcut.modifierFlags) {
                _ = holdShortcutAction.actionHandler!(holdShortcutAction)
            } else {
                App.shortcutMonitor.handle(event, withTarget: nil)
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
