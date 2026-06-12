import Cocoa

class RunningApplicationsEvents {
    private static var appsObserver: NSKeyValueObservation!
    // Many short-lived helper processes (e.g. `*.CompileAppleScript`) launch and quit within ~80ms.
    // Eagerly tracking each is a wasted Application init + AX-subscribe (which times out and retries) +
    // deinit, sometimes ~1/sec (#5721). We defer tracking a newly-launched app by this delay and skip it
    // if it's already gone, so transient helpers cost nothing. This applies ONLY to apps that appear during
    // continuous monitoring; the initial bulk discovery (`addInitialRunningApplications`) is added immediately.
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
    /// `Applications.manuallyRefreshAllWindows` (`addMissingApps`), and on-demand lookups still go through
    /// `findOrCreate` immediately, so nothing user-visible is missed by the delay.
    private static func debounceThenAddRunningApplications(_ launched: [NSRunningApplication]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + newAppDebounce) {
            let stillAlive = launched.filter { !$0.isTerminated }
            guard !stillAlive.isEmpty else { return }
            Applications.addRunningApplications(stillAlive, true)
        }
    }
}
