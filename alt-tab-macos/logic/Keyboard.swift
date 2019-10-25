import Cocoa

// Apple doesn't provide an enum for this, strangely
enum KeyCode: UInt16 {
    case escape = 53
    case command = 55
    case capsLock = 57
    case tab = 58
    case control = 59
    case function = 63
}

class Keyboard {
    static func listenToGlobalEvents(_ delegate: Application) {
        listenToGlobalKeyboardEvents(delegate)
    }
}

var eventTap: CFMachPort?

func listenToGlobalKeyboardEvents(_ delegate: Application) {
    let eventMask = [CGEventType.keyDown, CGEventType.keyUp, CGEventType.flagsChanged].reduce(CGEventMask(0), { $0 | (1 << $1.rawValue) })
    eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (_, _, event, delegate_) -> Unmanaged<CGEvent>? in
                let d = Unmanaged<Application>.fromOpaque(delegate_!).takeUnretainedValue()
                return keyboardHandler(event, d)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(delegate).toOpaque()))
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap!, enable: true)
    CFRunLoopRun()
}

func keyboardHandler(_ cgEvent: CGEvent, _ delegate: Application) -> Unmanaged<CGEvent>? {
    if cgEvent.type == .keyDown || cgEvent.type == .keyUp || cgEvent.type == .flagsChanged {
        if let event = NSEvent(cgEvent: cgEvent) {
            let keyDown = event.type == .keyDown
            let keycode = KeyCode(rawValue: event.keyCode)
            let optionKeyEvent = keycode == Preferences.metaKeyCode
            let tabKeyEvent = event.keyCode == Preferences.tabKey
            let escKeyEvent = keycode == KeyCode.escape
            if optionKeyEvent && event.modifiersDown([Preferences.metaModifierFlag!]) {
                delegate.preActivate()
            } else if tabKeyEvent && event.modifiersDown([Preferences.metaModifierFlag!]) && keyDown {
                delegate.showUiOrSelectNext()
                return nil // previously focused app should not receive keys
            } else if tabKeyEvent && event.modifiersDown([Preferences.metaModifierFlag!, .shift]) && keyDown {
                delegate.showUiOrSelectPrevious()
                return nil // previously focused app should not receive keys
            } else if escKeyEvent && event.modifiersDown([Preferences.metaModifierFlag!]) && keyDown {
                delegate.hideUi()
                return nil // previously focused app should not receive keys
            } else if optionKeyEvent && !keyDown {
                delegate.focusTarget()
            }
        }
    } else if cgEvent.type == .tapDisabledByUserInput || cgEvent.type == .tapDisabledByTimeout {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    // focused app will receive the event
    return Unmanaged.passRetained(cgEvent)
}
