import Cocoa
import Carbon.HIToolbox.Events

fileprivate var eventTap: CFMachPort!
fileprivate var shouldBeEnabled: Bool!
fileprivate var isPointerInsideUi: Bool!

class MouseEvents {
    static func observe() {
        observe_()
    }

    static func toggle(_ enabled: Bool) {
        shouldBeEnabled = enabled
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        }
    }
}

private func observe_() {
    let eventMask = [CGEventType.leftMouseDown, CGEventType.leftMouseUp].reduce(CGEventMask(0), { $0 | (1 << $1.rawValue) })
    // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass
    eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: mouseHandler,
        userInfo: nil)
    if let eventTap = eventTap {
        MouseEvents.toggle(false)
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        CFRunLoopAddSource(BackgroundWork.mouseEventsThread.runLoop, runLoopSource, .commonModes)
    } else {
        App.app.restart()
    }
}

private func mouseHandler(proxy: CGEventTapProxy, type: CGEventType, cgEvent: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .leftMouseDown {
        isPointerInsideUi_()
        if !isPointerInsideUi {
            return nil // focused app won't receive the event
        }
    } else if type == .leftMouseUp && cgEvent.getIntegerValueField(.mouseEventClickState) >= 1 {
        isPointerInsideUi_()
        if !isPointerInsideUi {
            DispatchQueue.main.async { App.app.hideUi() }
            return nil // focused app won't receive the event
        }
    } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) && shouldBeEnabled {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    return Unmanaged.passUnretained(cgEvent) // focused app will receive the event
}

private func isPointerInsideUi_() {
    DispatchQueue.main.sync {
        isPointerInsideUi = App.app.thumbnailsPanel.contentLayoutRect.contains(App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream)
    }
}
