import Cocoa

class WorkspaceEvents: NSObject {
    private static var appsObserver = WorkspaceEvents()

    static func observeRunningApplications() {
        NSWorkspace.shared.addObserver(appsObserver, forKeyPath: "runningApplications", options: [.old, .new], context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let type = NSKeyValueChange(rawValue: change![.kindKey]! as! UInt)
        if type == .insertion {
            let apps = change![.newKey] as! [NSRunningApplication]
            debugPrint("OS event", "apps launched", apps.map { ($0.processIdentifier, $0.bundleIdentifier) })
            Applications.addRunningApplications(apps)
        } else if type == .removal {
            let apps = change![.oldKey] as! [NSRunningApplication]
            debugPrint("OS event", "apps quit", apps.map { ($0.processIdentifier, $0.bundleIdentifier) })
            Applications.removeRunningApplications(apps)

        }
    }
}
