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
        runningApps.forEach {
            if isActualApplication($0) {
                Applications.list.append(Application($0))
            }
        }
    }

    static func removeRunningApplications(_ runningApps: [NSRunningApplication]) {
        var windowsOnTheLeftOfFocusedWindow = 0
        for runningApp in runningApps {
            Applications.list.removeAll(where: { $0.runningApplication.isEqual(runningApp) })
            Windows.list.enumerated().forEach { (index, window) in
                if window.application.runningApplication.isEqual(runningApp) && index <= Windows.focusedWindowIndex {
                    windowsOnTheLeftOfFocusedWindow += 1
                }
            }
            Windows.list.removeAll(where: { $0.application.runningApplication.isEqual(runningApp) })
        }
        guard Windows.list.count > 0 else { App.app.hideUi(); return }
        if windowsOnTheLeftOfFocusedWindow > 0 {
            Windows.cycleFocusedWindowIndex(-windowsOnTheLeftOfFocusedWindow)
        }
        App.app.refreshOpenUi()
    }

    private static func isActualApplication(_ app: NSRunningApplication) -> Bool {
        return (app.activationPolicy != .prohibited ||
                // Bug in CopyQ; see https://github.com/hluk/CopyQ/issues/1330
                app.bundleIdentifier == "io.github.hluk.CopyQ" ||
                // Bug in Parsec https://github.com/lwouis/alt-tab-macos/issues/206#issuecomment-609828033
                app.bundleIdentifier == "tv.parsec.www" ||
                // Bug in Octave.app; see https://github.com/octave-app/octave-app/issues/193#issuecomment-603648857
                app.localizedName == "octave-gui") &&
                // bug in Octave.app; see https://github.com/octave-app/octave-app/issues/193
                app.bundleIdentifier != "org.octave-app.Octave"
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
