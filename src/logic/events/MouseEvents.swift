import Cocoa
import Carbon.HIToolbox.Events

fileprivate var eventTap: CFMachPort!
fileprivate var shouldBeEnabled: Bool!

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
    // CGEvent.tapCreate returns nil if ensureAccessibilityCheckboxIsChecked() didn't pass
    eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: handleEvent,
        userInfo: nil)
    if let eventTap = eventTap {
        MouseEvents.toggle(false)
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    } else {
        App.app.restart()
    }
}

private let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
    if type == .leftMouseDown {
        if !isPointerInsideUi() {
            return nil // focused app won't receive the event
        }
    } else if type == .leftMouseUp && cgEvent.getIntegerValueField(.mouseEventClickState) >= 1 {
        if !isPointerInsideUi() {
            App.app.hideUi()
            return nil // focused app won't receive the event
        }
    } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) && shouldBeEnabled {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    return Unmanaged.passUnretained(cgEvent) // focused app will receive the event
}

private func isPointerInsideUi() -> Bool {
    return App.app.thumbnailsPanel.contentLayoutRect.contains(App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream)
}
