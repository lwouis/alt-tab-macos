import Cocoa

class ScrollwheelEvents {
    static var shouldBeEnabled: Bool!
    private static var eventTap: CFMachPort!

    static func observe() {
        eventTap = CGEvent.createTapOrRestart(
            tap: .cghidEventTap, // we need raw data
            options: .defaultTap,
            eventsOfInterest: NSEvent.EventTypeMask.scrollWheel.rawValue,
            callback: handleEvent,
            runLoop: BackgroundWork.keyboardAndMouseAndTrackpadEventsThread.runLoop)
        toggle(false)
    }

    static func toggle(_ enabled: Bool) {
        guard enabled != shouldBeEnabled else { return }
        shouldBeEnabled = enabled
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        }
    }

    static func reEnableTapIfNeeded() {
        if CGEvent.reEnableTapIfNeeded(eventTap, wanted: shouldBeEnabled) {
            Logger.warning { "" }
        }
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
        if type.rawValue == NSEvent.EventType.scrollWheel.rawValue,
           cgEvent.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
            // block continuous (trackpad) scrolling; let discrete (mouse) scrolling through
            return nil
        } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) && shouldBeEnabled {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
        }
        return Unmanaged.passUnretained(cgEvent) // focused app will receive the event
    }
}
