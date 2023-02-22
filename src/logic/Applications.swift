import Cocoa
import ApplicationServices

class Applications {
    static var list = [Application]()

    static func manuallyUpdateWindowsFor2s() {
        let group = DispatchGroup()
        manuallyUpdateWindows(group)
        _ = group.wait(wallTimeout: .now() + .seconds(2))
    }

    static func manuallyUpdateWindows(_ group: DispatchGroup? = nil) {
        for app in list {
            if app.runningApplication.isFinishedLaunching && app.runningApplication.activationPolicy != .prohibited {
                app.manuallyUpdateWindows(group)
            }
        }
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
                Applications.manuallyUpdateWindowsFor2s()
                CGSRemoveWindowsFromSpaces(cgsMainConnectionId, windowsOnlyOnOtherSpaces as NSArray, [Spaces.currentSpaceId])
            }
        } else {
            Applications.manuallyUpdateWindowsFor2s()
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
                if window.application.runningApplication.isEqual(runningApp) && index < Windows.focusedWindowIndex && window.shouldShowTheUser {
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
            if !App.app.appIsBeingUsed { return }
            let view = ThumbnailsView.recycledViews[i]
            if let app = Applications.find(window.application.pid) {
                if app.runningApplication.activationPolicy == .regular,
                   let bundleId = app.runningApplication.bundleIdentifier,
                   let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
                   let matchingItem = (items.first { $0.0 == url }),
                   let label = matchingItem.1 {
                    app.dockLabel = label
                    view.updateDockLabelIcon(label)
                } else {
                    app.dockLabel = nil
                    assignIfDifferent(&view.dockLabelIcon.isHidden, true)
                }
            }
        }
    }

    private static func isActualApplication(_ app: NSRunningApplication) -> Bool {
        // an app can start with .activationPolicy == .prohibited, then transition to != .prohibited later
        // an app can be both activationPolicy == .accessory and XPC (e.g. com.apple.dock.etci)
        return (isNotXpc(app) || isAndroidEmulator(app)) && !app.processIdentifier.isZombie()
    }

    private static func isNotXpc(_ app: NSRunningApplication) -> Bool {
        // these private APIs are more reliable than Bundle.init? as it can return nil (e.g. for com.apple.dock.etci)
        var psn = ProcessSerialNumber()
        GetProcessForPID(app.processIdentifier, &psn)
        var info = ProcessInfoRec()
        GetProcessInformation(&psn, &info)
        return String(info.processType) != "XPC!"
    }

    // managing AltTab windows within AltTab create all sorts of side effects
    // e.g. hiding the thumbnails panel gives focus to the preferences panel if open, thus changing its order in the list
    private static func notAltTab(_ app: NSRunningApplication) -> Bool {
        return app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    static func isAndroidEmulator(_ app: NSRunningApplication) -> Bool {
        // NSRunningApplication provides no way to identify the emulator; we pattern match on its KERN_PROCARGS
        if app.bundleIdentifier == nil,
           let executablePath = Sysctl.run([CTL_KERN, KERN_PROCARGS, app.processIdentifier]) {
            // example path: ~/Library/Android/sdk/emulator/qemu/darwin-x86_64/qemu-system-x86_64
            return executablePath.range(of: "qemu-system[^/]*$", options: .regularExpression, range: nil, locale: nil) != nil
        }
        return false
    }

    static func find(_ pid: pid_t?) -> Application? {
        return list.first { $0.pid == pid }
    }
}
