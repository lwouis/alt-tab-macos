import Cocoa

class SleepWakeEvents {
    static func observe() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        // Periodic watchdog: catches cases where the tap silently stops working without a
        // sleep/wake event (e.g. CFMachPort invalidated after 1-2 days of continuous uptime).
        Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { _ in reEnableAllTaps() }
    }

    @objc private static func handleWake(_ notification: Notification) {
        Logger.info { "" }
        reEnableAllTaps()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { reEnableAllTaps() }
    }

    private static func reEnableAllTaps() {
        TrackpadEvents.reEnableTapIfNeeded()
        ScrollwheelEvents.reEnableTapIfNeeded()
        KeyboardEvents.reEnableTapIfNeeded()
        CursorEvents.reEnableTapIfNeeded()
    }
}
