import Cocoa

class RunningApplicationsEvents {
    private static var appsObserver: NSKeyValueObservation!

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
            Applications.addRunningApplications(launched)
        }
        if let quit {
            Logger.debug { "quit:\(quit.map { $0.debugId() })" }
            Applications.removeRunningApplications(quit)
        }
    }
}
