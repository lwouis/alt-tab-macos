import Cocoa
import ApplicationServices

class Applications {
    static var list = [Application]()

    static func observeNewWindowsBlocking() {
        let group = DispatchGroup()
        for app in list {
            guard app.runningApplication.isFinishedLaunching else { continue }
            app.observeNewWindows(group)
        }
        _ = group.wait(wallTimeout: .now() + .seconds(2))
    }

    static func initialDiscovery() {
        addInitialRunningApplications()
        addInitialRunningApplicationsWindows()
        WorkspaceEvents.observeRunningApplications()
    }

    static func addInitialRunningApplications() {
        addRunningApplications(NSWorkspace.shared.runningApplications)
    }

    static func addInitialRunningApplicationsWindows() {
        let otherSpaces = Spaces.otherSpaces()
        if otherSpaces.count > 0 {
            let windowsOnCurrentSpace = Spaces.windowsInSpaces([Spaces.currentSpaceId])
            let windowsOnOtherSpaces = Spaces.windowsInSpaces(otherSpaces)
            let windowsOnlyOnOtherSpaces = Array(Set(windowsOnOtherSpaces).subtracting(windowsOnCurrentSpace))
            if windowsOnlyOnOtherSpaces.count > 0 {
                // on initial launch, we use private APIs to bring windows from other spaces into the current space, observe them, then remove them from the current space
                CGSAddWindowsToSpaces(cgsMainConnectionId, windowsOnlyOnOtherSpaces as NSArray, [Spaces.currentSpaceId])
                Applications.observeNewWindowsBlocking()
                CGSRemoveWindowsFromSpaces(cgsMainConnectionId, windowsOnlyOnOtherSpaces as NSArray, [Spaces.currentSpaceId])
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
            // comparing pid here can fail here, as it can be already nil; we use isEqual here to avoid the issue
            Applications.list.removeAll { $0.runningApplication.isEqual(runningApp) }
            Windows.list.enumerated().forEach { (index, window) in
                if window.application.runningApplication.isEqual(runningApp) && index < Windows.focusedWindowIndex {
                    windowsOnTheLeftOfFocusedWindow += 1
                }
            }
            Windows.list.removeAll { $0.application.runningApplication.isEqual(runningApp) }
        }
        guard Windows.list.count > 0 else { App.app.hideUi(); return }
        if windowsOnTheLeftOfFocusedWindow > 0 {
            Windows.cycleFocusedWindowIndex(-windowsOnTheLeftOfFocusedWindow)
        }
        App.app.refreshOpenUi()
    }

    static func refreshBadges() {
        if !App.app.appIsBeingUsed || Preferences.hideAppBadges { return }
        retryAxCallUntilTimeout {
            if let dockPid = (list.first { $0.runningApplication.bundleIdentifier == "com.apple.dock" }?.pid),
               let axList = (try AXUIElementCreateApplication(dockPid).children()?.first { try $0.role() == kAXListRole }),
               let axAppDockItem = (try axList.children()?.filter { try $0.subrole() == kAXApplicationDockItemSubrole && ($0.appIsRunning() ?? false) }) {
                let axAppDockItemUrlAndLabel = try axAppDockItem.map { try ($0.attribute(kAXURLAttribute, URL.self), $0.attribute(kAXStatusLabelAttribute, String.self)) }
                DispatchQueue.main.async {
                    refreshBadges_(axAppDockItemUrlAndLabel)
                }
            }
        }
    }

    static func refreshBadges_(_ items: [(URL?, String?)], _ currentIndex: Int = 0) {
        Windows.list.enumerated().forEach { (i, window) in
            let view = ThumbnailsView.recycledViews[i]
            if let app = (Applications.list.first { window.application.pid == $0.pid }) {
                if App.app.appIsBeingUsed,
                   app.runningApplication.activationPolicy == .regular,
                   let bundleId = app.runningApplication.bundleIdentifier,
                   let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
                   let matchingItem = (items.first { $0.0 == url }),
                   let label = matchingItem.1,
                   let labelInt = Int(label) {
                    app.dockLabel = label
                    view.updateDockLabelIcon(labelInt)
                } else {
                    app.dockLabel = nil
                    assignIfDifferent(&view.dockLabelIcon.isHidden, true)
                }
            }
        }
    }

    private static func isActualApplication(_ app: NSRunningApplication) -> Bool {
        return (app.activationPolicy != .prohibited || isNotXpc(app)) && !app.processIdentifier.isZombie()
    }

    private static func isNotXpc(_ app: NSRunningApplication) -> Bool {
        return app.bundleURL
            .flatMap { Bundle(url: $0) }
            .flatMap { $0.infoDictionary }
            .flatMap { $0["CFBundlePackageType"] as? String } != "XPC!"
    }

    // managing AltTab windows within AltTab create all sorts of side effects
    // e.g. hiding the thumbnails panel gives focus to the preferences panel if open, thus changing its order in the list
    private static func notAltTab(_ app: NSRunningApplication) -> Bool {
        return app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }
}
