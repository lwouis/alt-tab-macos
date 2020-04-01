import Cocoa
import ApplicationServices

class Applications {
    static var list = [Application]()
    static var appsObserver = RunningApplicationsObserver()
    static var appsInSubscriptionRetryLoop = [String]()

    static func observeNewWindows() {
        for app in list {
            guard app.runningApplication.isFinishedLaunching else { continue }
            app.observeNewWindows()
        }
    }

    static func initialDiscovery() {
        addInitialRunningApplications()
        addInitialRunningApplicationsWindows()
        observeRunningApplications()
    }

    static func addInitialRunningApplications() {
        addRunningApplications(NSWorkspace.shared.runningApplications)
    }

    static func observeRunningApplications() {
        NSWorkspace.shared.addObserver(Applications.appsObserver, forKeyPath: "runningApplications", options: [.old, .new], context: nil)
    }

    static func addInitialRunningApplicationsWindows() {
        let spaces = Spaces.otherSpaces()
        if spaces.count == 0 {
            Applications.observeNewWindows()
        } else {
            let windows = Spaces.windowsInSpaces(spaces)
            if windows.count > 0 {
                // on initial launch, we use private APIs to bring windows from other spaces into the current space, observe them, then remove them from the current space
                CGSAddWindowsToSpaces(cgsMainConnectionId, windows as NSArray, [Spaces.currentSpaceId])
                Applications.observeNewWindows()
                CGSRemoveWindowsFromSpaces(cgsMainConnectionId, windows as NSArray, [Spaces.currentSpaceId])
            }
        }
    }

    static func addRunningApplications(_ runningApps: [NSRunningApplication]) {
        for app in filterApplications(runningApps) {
            Applications.list.append(Application(app))
        }
    }

    static func removeRunningApplications(_ runningApps: [NSRunningApplication]) {
        for runningApp in runningApps {
            Applications.list.removeAll(where: { $0.runningApplication.isEqual(runningApp) })
            var indexesToRemove = [Int]()
            Windows.list.enumerated().forEach { (index, window) in
                if window.application.runningApplication.isEqual(runningApp) {
                    indexesToRemove.append(index)
                }
            }
            Windows.list.removeAll(where: { $0.application.runningApplication.isEqual(runningApp) })
        }
        guard Windows.list.count > 0 else { App.app.hideUi(); return }
        // TODO: implement of more sophisticated way to decide which thumbnail gets focused on app quit
        Windows.updateFocusedWindowIndex(1)
        App.app.refreshOpenUi()
    }

    private static func filterApplications(_ apps: [NSRunningApplication]) -> [NSRunningApplication] {
        return apps.filter {
            ($0.activationPolicy != .prohibited ||
                    // Bug in CopyQ; see https://github.com/hluk/CopyQ/issues/1330
                    $0.bundleIdentifier == "io.github.hluk.CopyQ" ||
                    // Bug in Octave.app; see https://github.com/octave-app/octave-app/issues/193#issuecomment-603648857
                    $0.localizedName == "octave-gui") &&
                    // bug in Octave.app; see https://github.com/octave-app/octave-app/issues/193
                    $0.bundleIdentifier != "org.octave-app.Octave"
        }
    }
}

class RunningApplicationsObserver: NSObject {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        let type = NSKeyValueChange(rawValue: change![.kindKey]! as! UInt)
        switch type {
            case .insertion:
                let apps = change![.newKey] as! [NSRunningApplication]
                debugPrint("OS event", "apps launched", apps.map { ($0.processIdentifier, $0.bundleIdentifier) })
                Applications.addRunningApplications(apps)
            case .removal:
                let apps = change![.oldKey] as! [NSRunningApplication]
                debugPrint("OS event", "apps quit", apps.map { ($0.processIdentifier, $0.bundleIdentifier) })
                Applications.removeRunningApplications(apps)
            default: return
        }
    }
}
