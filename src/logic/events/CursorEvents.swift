import Cocoa
import Carbon.HIToolbox.Events

class CursorEvents {
    private static var eventTap: CFMachPort!
    private static var shouldBeEnabled: Bool!
    static var deadZoneInitialPosition: CGPoint?
    static var isAllowedToMouseHover = true

    static func observe() {
        observe_()
    }

    static func toggle(_ enabled: Bool) {
        guard enabled != shouldBeEnabled else { return }
        shouldBeEnabled = enabled
        if !enabled {
            deadZoneInitialPosition = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        }
    }

    private static func observe_() {
        let eventMask = [CGEventType.mouseMoved].reduce(CGEventMask(0), { $0 | (1 << $1.rawValue) })
        // CGEvent.tapCreate returns nil if ensureAccessibilityCheckboxIsChecked() didn't pass
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: handleEvent,
            userInfo: nil)
        if let eventTap {
            toggle(false)
            let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
            // we run on main-thread directly since all we do is check NSEvent data, which we must do on main-thread
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        } else {
            App.app.restart()
        }
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
        if type == .mouseMoved {
            updateDeadzoneSituation(cgEvent)
        } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) && shouldBeEnabled {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
        }
        return Unmanaged.passUnretained(cgEvent) // focused app will receive the event
    }

    /// when using the trackpad, the user may swipe with a slight mistake. This will create a small cursor movement
    /// we ignore those, as they are not intended. Intended movements will be larger and not ignored
    private static func updateDeadzoneSituation(_ cgEvent: CGEvent) {
        guard let event = cgEvent.toNSEvent() else { return }
        guard let deadZoneInitialPosition else {
            deadZoneInitialPosition = event.locationInWindow
            isAllowedToMouseHover = false
            return
        }
        let deltaX = event.locationInWindow.x - deadZoneInitialPosition.x
        let deltaY = event.locationInWindow.y - deadZoneInitialPosition.y
        let d = hypot(deltaX, deltaY)
        isAllowedToMouseHover = d > 25
    }
}
