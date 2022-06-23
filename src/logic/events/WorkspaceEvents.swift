import Cocoa

class WorkspaceEvents {
    private static var appsObserver: NSKeyValueObservation!
    private static var previousValueOfRunningApps: Set<NSRunningApplication>!

    static func observeRunningApplications() {
        previousValueOfRunningApps = Set(NSWorkspace.shared.runningApplications)
        appsObserver = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new], changeHandler: observerCallback)
    }

    static func observerCallback<A>(_ application: NSWorkspace, _ change: NSKeyValueObservedChange<A>) {
        let workspaceApps = Set(NSWorkspace.shared.runningApplications)
        // TODO: symmetricDifference has bad performance
        let diff = Array(workspaceApps.symmetricDifference(previousValueOfRunningApps))
        if change.kind == .insertion {
            debugPrint("OS event", "apps launched", diff.map { ($0.processIdentifier, $0.bundleIdentifier) })
            Applications.addRunningApplications(diff)
        } else if change.kind == .removal {
            debugPrint("OS event", "apps quit", diff.map { ($0.processIdentifier, $0.bundleIdentifier) })
            Applications.removeRunningApplications(diff)
        }
        previousValueOfRunningApps = workspaceApps
    }
}
