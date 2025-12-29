import Cocoa

class RunningApplicationsEvents {
    private static var appsObserver: NSKeyValueObservation!

    static func observe() {
        // we can't observe NSWorkspace.didLaunchApplicationNotification or NSWorkspace.didTerminateApplicationNotification
        // these only trigger for some apps, mostly GUI app. We need to track all processes as any could spawn a window
        appsObserver = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new], changeHandler: { (_, change) in handleEvent(change) })
    }

    private static func handleEvent(_ change: NSKeyValueObservedChange<[NSRunningApplication]>) {
        let added = change.newValue
        let removed = change.oldValue
        Logger.debug("added:", added?.map { $0.debugId() }, "removed:", removed?.map { $0.debugId() })
        if let added {
            Applications.addRunningApplications(added)
        }
        if let removed {
            Applications.removeRunningApplications(removed)
        }
    }
}
