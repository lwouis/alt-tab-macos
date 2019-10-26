import Cocoa
import Carbon.HIToolbox

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
            let isTab = event.keyCode == Preferences.tabKeyCode
            let isMeta = event.keyCode == Preferences.metaKeyCode
            let isRightArrow = event.keyCode == kVK_RightArrow
            let isLeftArrow = event.keyCode == kVK_LeftArrow
            let isEscape = event.keyCode == kVK_Escape
            if event.modifierFlags.contains(Preferences.metaModifierFlag!) {
                if keyDown {
                    if isTab && event.modifierFlags.contains(.shift) {
                        delegate.showUiOrSelectPrevious()
                        return nil // previously focused app should not receive keys
                    } else if isTab {
                        delegate.showUiOrSelectNext()
                        return nil // previously focused app should not receive keys
                    } else if isRightArrow && delegate.appIsBeingUsed {
                        delegate.cycleSelection(1)
                        return nil // previously focused app should not receive keys
                    } else if isLeftArrow && delegate.appIsBeingUsed {
                        delegate.cycleSelection(-1)
                        return nil // previously focused app should not receive keys
                    } else if keyDown && isEscape {
                        delegate.hideUi()
                        return nil // previously focused app should not receive keys
                    }
                }
            } else if isMeta && !keyDown {
                delegate.focusTarget()
            }
        }
    } else if cgEvent.type == .tapDisabledByUserInput || cgEvent.type == .tapDisabledByTimeout {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    // focused app will receive the event
    return Unmanaged.passRetained(cgEvent)
}
