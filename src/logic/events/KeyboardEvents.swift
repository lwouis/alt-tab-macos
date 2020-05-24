import Cocoa
import Carbon.HIToolbox.Events

class KeyboardEvents {
    static func observe() {
        observe_()
    }
}

private var eventTap: CFMachPort?

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

private func keyboardHandler(proxy: CGEventTapProxy, type: CGEventType, cgEvent: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
     if type == .keyDown || type == .keyUp || type == .flagsChanged {
        if let event_ = NSEvent(cgEvent: cgEvent),
           // workaround: NSEvent.characters is not safe outside of the main thread; this is not documented by Apple
            // see https://github.com/Kentzo/ShortcutRecorder/issues/114#issuecomment-606465340
           let event = NSEvent.keyEvent(with: event_.type, location: event_.locationInWindow, modifierFlags: event_.modifierFlags,
               timestamp: event_.timestamp, windowNumber: event_.windowNumber, context: nil, characters: "",
               charactersIgnoringModifiers: "", isARepeat: type == .flagsChanged ? false : event_.isARepeat, keyCode: event_.keyCode) {
            let appWasBeingUsed = App.app.appIsBeingUsed
            App.shortcutMonitor.handle(event, withTarget: nil)
            if appWasBeingUsed || App.app.appIsBeingUsed {
                return nil // focused app won't receive the event
            }
        }
    } else if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    return Unmanaged.passRetained(cgEvent) // focused app will receive the event
}
