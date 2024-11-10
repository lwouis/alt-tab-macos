import Cocoa

class RunningApplicationsEvents {
    private static var appsObserver: NSKeyValueObservation!
    private static var previousValueOfRunningApps: Set<NSRunningApplication>!

    static func observe() {
        previousValueOfRunningApps = Set(NSWorkspace.shared.runningApplications)
        appsObserver = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new], changeHandler: handleEvent)
    }

    private static func handleEvent<A>(_: NSWorkspace, _ change: NSKeyValueObservedChange<A>) {
        let workspaceApps = Set(NSWorkspace.shared.runningApplications)
        // TODO: symmetricDifference has bad performance
        let diff = Array(workspaceApps.symmetricDifference(previousValueOfRunningApps))
        logger.d(diff.map { ($0.processIdentifier, $0.bundleIdentifier ?? "nil") })
        if change.kind == .insertion {
            Applications.addRunningApplications(diff)
        } else if change.kind == .removal {
            Applications.removeRunningApplications(diff)
        }
        previousValueOfRunningApps = workspaceApps
    }
}
