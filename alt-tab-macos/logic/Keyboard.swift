import Cocoa
import Carbon.HIToolbox.Events

class Keyboard {
    static func listenToGlobalEvents(_ delegate: Application) {
        listenToGlobalKeyboardEvents(delegate)
    }
}

var eventTap: CFMachPort?

func listenToGlobalKeyboardEvents(_ delegate: Application) {
    DispatchQueue.global(qos: .userInteractive).async {
        let eventMask = [CGEventType.keyDown, CGEventType.keyUp, CGEventType.flagsChanged].reduce(CGEventMask(0), { $0 | (1 << $1.rawValue) })
        eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: keyboardHandler,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(delegate).toOpaque()))
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap!, enable: true)
        CFRunLoopRun()
    }
}

func consumeEvent(_ fn: @escaping () -> Void) -> Unmanaged<CGEvent>? {
    // run app logic on main thread
    DispatchQueue.main.async {
        fn()
    }
    // previously focused app should not receive keys
    return nil
}

func keyboardHandler(proxy: CGEventTapProxy, type: CGEventType, event_: CGEvent, delegate_: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let delegate = Unmanaged<Application>.fromOpaque(delegate_!).takeUnretainedValue()
    if type == .keyDown || type == .keyUp || type == .flagsChanged {
        if let event = NSEvent(cgEvent: event_) {
            let keyDown = event.type == .keyDown
            let isTab = event.keyCode == Preferences.tabKeyCode
            let isMeta = Preferences.metaKeyCodes!.contains(event.keyCode)
            let isRightArrow = event.keyCode == kVK_RightArrow
            let isLeftArrow = event.keyCode == kVK_LeftArrow
            let isEscape = event.keyCode == kVK_Escape
            if event.modifierFlags.contains(Preferences.metaModifierFlag!) && keyDown {
                if isTab && event.modifierFlags.contains(.shift) {
                    return consumeEvent { delegate.showUiOrSelectPrevious() }
                } else if isTab {
                    return consumeEvent { delegate.showUiOrSelectNext() }
                } else if isRightArrow && delegate.appIsBeingUsed {
                    return consumeEvent { delegate.cycleSelection(1) }
                } else if isLeftArrow && delegate.appIsBeingUsed {
                    return consumeEvent { delegate.cycleSelection(-1) }
                } else if keyDown && isEscape {
                    return consumeEvent { delegate.hideUi() }
                }
            } else if isMeta && !keyDown {
                return consumeEvent { delegate.focusTarget() }
            }
        }
    } else if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    // focused app will receive the event
    return Unmanaged.passRetained(event_)
}
