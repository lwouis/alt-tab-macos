import Cocoa

class RunningApplicationsEvents {
    private static var appsObserver: NSKeyValueObservation!
    private static let appsQueue = DispatchQueue(label: "RunningApplicationsEvents.appsQueue")
    private static var _previousValueOfRunningApps: Set<NSRunningApplication> = []
    private static var previousValueOfRunningApps: Set<NSRunningApplication> {
        get { appsQueue.sync { _previousValueOfRunningApps } }
        set { appsQueue.sync { _previousValueOfRunningApps = newValue } }
    }

    static func observe() {
        previousValueOfRunningApps = Set(NSWorkspace.shared.runningApplications)
        appsObserver = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new], changeHandler: { workspace, change in
            Self.handleEvent(workspace, change)
        })
    }

    // TODO: handle this on a separate thread?
    private static func handleEvent(_: NSWorkspace, _ change: NSKeyValueObservedChange<[NSRunningApplication]>) {
        let workspaceApps = Set(NSWorkspace.shared.runningApplications)
        // TODO: symmetricDifference has bad performance
        let diff = Array(workspaceApps.symmetricDifference(previousValueOfRunningApps))
        Logger.debug(diff.map { ($0.processIdentifier, $0.bundleIdentifier ?? "nil") })
        if change.kind == .insertion {
            Applications.addRunningApplications(diff)
        } else if change.kind == .removal {
            Applications.removeRunningApplications(diff)
        }
        previousValueOfRunningApps = workspaceApps
    }
}
