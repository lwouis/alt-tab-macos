import Foundation
import Cocoa

class Applications {
    static var map = [pid_t: Application]()
    static var appsObserver = RunningApplicationsObserver()

    static func addInitialRunningApplications() {
        addRunningApplications(NSWorkspace.shared.runningApplications)
    }

    static func addRunningApplications(_ runningApps: [NSRunningApplication]) {
        for app in filterApplications(runningApps) {
            Applications.map[app.processIdentifier] = Application(app)
        }
    }

    static func observeRunningApplications() {
        NSWorkspace.shared.addObserver(Applications.appsObserver, forKeyPath: "runningApplications", options: [.old, .new], context: nil)
    }

    static func reviewRunningApplicationsWindows() {
        for app in map.values {
            guard app.runningApplication.isFinishedLaunching else { continue }
            app.observeNewWindows()
        }
    }

    static func removeApplications(_ runningApps: [NSRunningApplication]) {
        var someAppsAreAlreadyTerminated = false
        for runningApp in runningApps {
            guard runningApp.bundleIdentifier != nil else { someAppsAreAlreadyTerminated = true; continue }
            guard Applications.map[runningApp.processIdentifier] != nil else { continue }
            var windowsToKeep = [Window]()
            for window in Windows.listRecentlyUsedFirst {
                guard window.application.runningApplication.processIdentifier != runningApp.processIdentifier else { continue }
                windowsToKeep.append(window)
            }
            Windows.listRecentlyUsedFirst = windowsToKeep
            Applications.map.removeValue(forKey: runningApp.processIdentifier)
            guard Windows.listRecentlyUsedFirst.count > 0 else { (App.shared as! App).hideUi(); return }
            // TODO: implement of more sophisticated way to decide which thumbnail gets focused on app quit
            Windows.focusedWindowIndex = 1
            (App.shared as! App).refreshOpenUi()
        }
        // sometimes removed `runningApps` are already terminated by the time they reach this method so we can't match their pid in `Applications.map` above
        // we need to remove them based on their lack of `bundleIdentifier`
        if someAppsAreAlreadyTerminated {
            Windows.listRecentlyUsedFirst.removeAll(where: { $0.application.runningApplication.bundleIdentifier == nil })
            Applications.map = Applications.map.filter { $0.value.runningApplication.bundleIdentifier != nil }
        }
    }

    private static func filterApplications(_ apps: [NSRunningApplication]) -> [NSRunningApplication] {
        // it would be nice to filter with $0.activationPolicy != .prohibited (see https://stackoverflow.com/a/26002033/2249756)
        // however some daemon processes can sometimes create windows, so we can't filter them out (e.g. CopyQ is .prohibited for some reason)
        return apps.filter { $0.bundleIdentifier != nil && $0.bundleIdentifier != NSRunningApplication.current.bundleIdentifier }
    }
}

class RunningApplicationsObserver: NSObject {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let type = NSKeyValueChange(rawValue: change![.kindKey]! as! UInt)
        switch type {
            case .insertion:
                let apps = change![.newKey] as! [NSRunningApplication]
                debugPrint("OS event: apps launched", apps.map { ($0.processIdentifier, $0.bundleIdentifier) })
                Applications.addRunningApplications(apps)
            case .removal:
                let apps = change![.oldKey] as! [NSRunningApplication]
                debugPrint("OS event: apps quit", apps.map { ($0.processIdentifier, $0.bundleIdentifier) })
                Applications.removeApplications(apps)
            default: return
        }
    }
}
