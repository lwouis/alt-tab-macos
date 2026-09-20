import Cocoa

class RunningApplicationsEvents {
    private static var appsObserver: NSKeyValueObservation!
    // Many short-lived helper processes (e.g. `*.CompileAppleScript`) launch and quit within ~80ms.
    // Eagerly tracking each is a wasted Application init + deinit, sometimes ~1/sec (#5721). We defer tracking
    // a newly-launched app by this delay and skip it if it's already gone, so transient helpers cost nothing.
    // This applies ONLY to apps that appear during continuous monitoring; the initial bulk discovery
    // (`addInitialRunningApplications`) is added immediately.
    private static let newAppDebounce = DispatchTimeInterval.milliseconds(250)

    static func observe() {
        // we can't observe NSWorkspace.didLaunchApplicationNotification or NSWorkspace.didTerminateApplicationNotification
        // these only trigger for some apps, mostly GUI app. We need to track all processes as any could spawn a window
        appsObserver = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new], changeHandler: { (_, change) in handleEvent(change) })
    }

    private static func handleEvent(_ change: NSKeyValueObservedChange<[NSRunningApplication]>) {
        let launched = change.newValue
        let quit = change.oldValue
        if let launched {
            Logger.debug { "launched:\(launched.map { $0.debugId() })" }
            debounceThenAddRunningApplications(launched)
        }
        if let quit {
            Logger.debug { "quit:\(quit.map { $0.debugId() })" }
            Applications.removeRunningApplications(quit)
        }
    }

    /// Defer by `newAppDebounce`, then add only the apps still alive — transient helpers are dropped.
    /// A genuine app that opens a window within the delay is still caught at switcher-show time by
    /// `Applications.manuallyRefreshAllWindows` (the WindowServer discovery pass calls `findOrCreate` on
    /// each window's owner pid), and on-demand lookups still go through `findOrCreate` immediately, so
    /// nothing user-visible is missed by the delay.
    ///
    /// **Liveness comes from the kernel, not from `isTerminated`** (`pid_t.isAlive`). A process that dies
    /// inside the debounce has already had its removal announced and processed, so admitting it here is
    /// permanent: nothing will announce it again, and its `Application`, its `AXObserver` and its
    /// accessibility-health entry stay for the rest of the session. Every 30s recovery tick then re-attempts
    /// subscriptions against it forever. On a machine that spawns short-lived processes at ~1/s this reached
    /// 56k dead processes and a permanently pegged core in three days (#6051).
    private static func debounceThenAddRunningApplications(_ launched: [NSRunningApplication]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + newAppDebounce) {
            let stillAlive = launched.filter { $0.processIdentifier.isAlive() }
            guard !stillAlive.isEmpty else { return }
            Applications.addRunningApplications(stillAlive)
        }
    }
}
