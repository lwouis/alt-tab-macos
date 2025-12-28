import Cocoa

class RunningApplicationsEvents {
    private static var appsObserver: NSKeyValueObservation!
    private static var previousValueOfRunningApps: Set<NSRunningApplication>!

    static func observe() {
        previousValueOfRunningApps = Set(NSWorkspace.shared.runningApplications)
        // we can't observe NSWorkspace.didLaunchApplicationNotification or NSWorkspace.didTerminateApplicationNotification
        // these only trigger for some apps, mostly GUI app. We need to track all processes as any could spawn a window
        appsObserver = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new], changeHandler: { (_, _) in handleEvent() })
    }

    private static func handleEvent() {
        let workspaceApps = Set(NSWorkspace.shared.runningApplications)
        let added = workspaceApps.subtracting(previousValueOfRunningApps)
        let removed = previousValueOfRunningApps.subtracting(workspaceApps)
        Logger.info("added:", added.map { $0.id }, "removed:", removed.map { $0.id })
        if !added.isEmpty {
            Applications.addRunningApplications(Array(added))
        }
        if !removed.isEmpty {
            Applications.removeRunningApplications(Array(removed))
        }
        previousValueOfRunningApps = workspaceApps
    }
}
