import Cocoa
import Carbon.HIToolbox.Events

class Keyboard {
    static func listenToGlobalEvents(_ delegate: App) {
        listenToGlobalKeyboardEvents(delegate)
    }
}

var eventTap: CFMachPort?

func listenToGlobalKeyboardEvents(_ app: App) {
    DispatchQueues.keyboardEvents.async {
        let eventMask = [CGEventType.keyDown, CGEventType.keyUp, CGEventType.flagsChanged].reduce(CGEventMask(0), { $0 | (1 << $1.rawValue) })
        // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass
        eventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: keyboardHandler,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(app).toOpaque()))
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CGEvent.tapEnable(tap: eventTap!, enable: true)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CFRunLoopRun()
    }
}

func dispatchWork(_ fn: @escaping () -> Void) -> Unmanaged<CGEvent>? {
    (App.shared as! App).uiWorkShouldBeDone = true
    DispatchQueue.main.async {
        fn()
    }
    return nil // previously focused app should not receive keys
}

func dispatchWorkCurrentThread(_ fn: @escaping () -> Void) -> Unmanaged<CGEvent>? {
    (App.shared as! App).uiWorkShouldBeDone = false
    fn()
    return nil // previously focused app should not receive keys
}

func keyboardHandler(proxy: CGEventTapProxy, type: CGEventType, event_: CGEvent, appPointer: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let app = Unmanaged<App>.fromOpaque(appPointer!).takeUnretainedValue()
    if type == .keyDown || type == .keyUp || type == .flagsChanged {
        if let event = NSEvent(cgEvent: event_) {
            let isTab = event.keyCode == Preferences.tabKeyCode
            let isMetaChanged = Preferences.metaKeyCodes.contains(event.keyCode)
            let isMetaDown = event.modifierFlags.contains(Preferences.metaModifierFlag)
            let isRightArrow = event.keyCode == kVK_RightArrow
            let isLeftArrow = event.keyCode == kVK_LeftArrow
            let isEscape = event.keyCode == kVK_Escape
            if type == .keyDown && isEscape && app.appIsBeingUsed {
                return dispatchWorkCurrentThread { app.hideUi() }
            } else if isMetaDown && type == .keyDown {
                if isTab && event.modifierFlags.contains(.shift) {
                    return dispatchWork { app.showUiOrCycleSelection(-1) }
                } else if isTab {
                    return dispatchWork { app.showUiOrCycleSelection(1) }
                } else if isRightArrow && app.appIsBeingUsed {
                    return dispatchWork { app.cycleSelection(1) }
                } else if isLeftArrow && app.appIsBeingUsed {
                    return dispatchWork { app.cycleSelection(-1) }
                }
            } else if isMetaChanged && !isMetaDown {
                return dispatchWorkCurrentThread { app.focusTarget() }
            }
        }
    } else if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    // focused app will receive the event
    return Unmanaged.passRetained(event_)
}
