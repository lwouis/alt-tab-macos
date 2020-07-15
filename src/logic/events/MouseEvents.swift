import Cocoa
import Carbon.HIToolbox.Events

fileprivate var eventTap: CFMachPort!
fileprivate var shouldBeEnabled: Bool!

class MouseEvents {
    static func observe() {
        observe_()
    }

    static func disable() {
        shouldBeEnabled = false
        CGEvent.tapEnable(tap: eventTap, enable: false)
    }

    static func enable() {
        shouldBeEnabled = true
        CGEvent.tapEnable(tap: eventTap, enable: true)
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
    MouseEvents.disable()
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(BackgroundWork.mouseEventsThread.runLoop, runLoopSource, .commonModes)
}

private func mouseHandler(proxy: CGEventTapProxy, type: CGEventType, cgEvent: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .leftMouseDown && !isPointerInsideUi() {
        return nil // focused app won't receive the event
    } else if type == .leftMouseUp && cgEvent.getIntegerValueField(.mouseEventClickState) >= 1 && !isPointerInsideUi() {
        App.app.hideUi()
        return nil // focused app won't receive the event
    } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) && shouldBeEnabled {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    return Unmanaged.passRetained(cgEvent) // focused app will receive the event
}

private func isPointerInsideUi() -> Bool {
    return App.app.thumbnailsPanel.contentLayoutRect.contains(App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream)
}
