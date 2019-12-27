import Cocoa
import Carbon.HIToolbox.Events

class Keyboard {
    static let backgroundQueue = DispatchQueue(label: "uiQueue", qos: .userInteractive, autoreleaseFrequency: .never)

    static func listenToGlobalEvents(_ delegate: Application) {
        listenToGlobalKeyboardEvents(delegate)
    }
}

var eventTap: CFMachPort?

func listenToGlobalKeyboardEvents(_ delegate: Application) {
    Keyboard.backgroundQueue.async {
        Thread.current.name = "uiQueue-thread"
        let eventMask = [CGEventType.keyDown, CGEventType.keyUp, CGEventType.flagsChanged].reduce(CGEventMask(0), { $0 | (1 << $1.rawValue) })
        // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass
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

func dispatchWork(_ application: Application, _ uiWorkShouldBeDone: Bool, _ fn: @escaping () -> Void) -> Unmanaged<CGEvent>? {
    application.uiWorkShouldBeDone = uiWorkShouldBeDone
    DispatchQueue.main.async {
        fn()
    }
    return nil // previously focused app should not receive keys
}

func keyboardHandler(proxy: CGEventTapProxy, type: CGEventType, event_: CGEvent, delegate_: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let application = Unmanaged<Application>.fromOpaque(delegate_!).takeUnretainedValue()
    if type == .keyDown || type == .keyUp || type == .flagsChanged {
        if let event = NSEvent(cgEvent: event_) {
            let isTab = event.keyCode == Preferences.tabKeyCode
            let isMetaChanged = Preferences.metaKeyCodes!.contains(event.keyCode)
            let isMetaDown = event.modifierFlags.contains(Preferences.metaModifierFlag!)
            let isRightArrow = event.keyCode == kVK_RightArrow
            let isLeftArrow = event.keyCode == kVK_LeftArrow
            let isEscape = event.keyCode == kVK_Escape
            if isMetaDown && type == .keyDown {
                if isTab && event.modifierFlags.contains(.shift) {
                    return dispatchWork(application, true, { application.showUiOrCycleSelection(-1) })
                } else if isTab {
                    return dispatchWork(application, true, { application.showUiOrCycleSelection(1) })
                } else if isRightArrow && application.appIsBeingUsed {
                    return dispatchWork(application, true, { application.cycleSelection(1) })
                } else if isLeftArrow && application.appIsBeingUsed {
                    return dispatchWork(application, true, { application.cycleSelection(-1) })
                } else if type == .keyDown && isEscape {
                    return dispatchWork(application, false, { application.hideUi() })
                }
            } else if isMetaChanged && !isMetaDown {
                return dispatchWork(application, false, { application.focusTarget() })
            }
        }
    } else if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    // focused app will receive the event
    return Unmanaged.passRetained(event_)
}
