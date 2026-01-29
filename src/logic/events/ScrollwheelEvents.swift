import Cocoa

class ScrollwheelEvents {
    static var shouldBeEnabled: Bool!
    private static var eventTap: CFMachPort!

    static func observe() {
        observe_()
        toggle(false)
    }

    static func toggle(_ enabled: Bool) {
        guard enabled != shouldBeEnabled else { return }
        shouldBeEnabled = enabled
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        }
    }

    private static func observe_() {
        // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap, // we need raw data
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: NSEvent.EventTypeMask.scrollWheel.rawValue,
            callback: handleEvent,
            userInfo: nil)
        if let eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
            CFRunLoopAddSource(BackgroundWork.keyboardAndMouseAndTrackpadEventsThread.runLoop, runLoopSource, .commonModes)
        } else {
            App.app.restart()
        }
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
        if type.rawValue == NSEvent.EventType.scrollWheel.rawValue {
            // block scrolling globally
            return nil
        } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) && shouldBeEnabled {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
        }
        return Unmanaged.passUnretained(cgEvent) // focused app will receive the event
    }
}
