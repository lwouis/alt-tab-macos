import Cocoa

class SleepWakeEvents {
    static func observe() {
        // system sleep/wake and display sleep/wake both suspend our event taps long enough for macOS to
        // disable them with kCGEventTapDisabledByTimeout; we re-enable them on resume (#5723)
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private static func handleWake(_ notification: Notification) {
        Logger.info { "" }
        reEnableAllTaps()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { reEnableAllTaps() }
        AxObserverRegistry.shared.recoverAll(.wake)
        // A wake reconfigures the displays, which mints new Space ids for every external screen (measured on
        // macOS 26: the same monitor came back with its Space renumbered 5253 → 5257). Every window's cached
        // Space membership is stale against that, and the screen + Space filters are judged on it, so
        // re-query rather than wait for the next summon (#6021). The unlock that usually follows asks for
        // the same pass; both go through the 1s rescan throttle.
        Applications.manuallyRefreshAllWindows()
    }

    static func reEnableAllTaps() {
        TrackpadEvents.reEnableTapIfNeeded()
        ScrollwheelEvents.reEnableTapIfNeeded()
        KeyboardEvents.reEnableTapIfNeeded()
        CursorEvents.reEnableTapIfNeeded()
        WindowAttentionEvents.reEnableTapIfNeeded()
    }
}
