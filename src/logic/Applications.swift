import Cocoa
import ApplicationServices

class Applications {
    static var list = [Application]()

    static func observeNewWindowsBlocking() {
        let group = DispatchGroup()
        for app in list {
            app.wasLaunchedBeforeAltTab = true
            guard app.runningApplication.isFinishedLaunching else { continue }
            app.observeNewWindows(group)
        }
        _ = group.wait(wallTimeout: .now() + .seconds(2))
    }

    static func addOtherSpaceWindows(_ windowsOnlyOnOtherSpaces: [CGWindowID]) {
        for app in list {
            app.wasLaunchedBeforeAltTab = true
            guard app.runningApplication.isFinishedLaunching else { continue }
            app.addOtherSpaceWindows(windowsOnlyOnOtherSpaces)
        }
    }

    static func initialDiscovery() {
        addInitialRunningApplications()
        addInitialRunningApplicationsWindows()
        WorkspaceEvents.observeRunningApplications()
        WorkspaceEvents.registerFrontAppChangeNote()
    }

    static func addInitialRunningApplications() {
        addRunningApplications(NSWorkspace.shared.runningApplications, true)
    }

    static func addInitialRunningApplicationsWindows() {
        let otherSpaces = Spaces.otherSpaces()
        if otherSpaces.count > 0 {
            let windowsOnCurrentSpace = Spaces.windowsInSpaces([Spaces.currentSpaceId])
            let windowsOnOtherSpaces = Spaces.windowsInSpaces(otherSpaces)
            let windowsOnlyOnOtherSpaces = Array(Set(windowsOnOtherSpaces).subtracting(windowsOnCurrentSpace))
            if windowsOnlyOnOtherSpaces.count > 0 {
                // Currently we add those window in other space without AXUIElement init
                // We don't need to get the AXUIElement until we focus these windows.
                // when we need to focus these windows, we use the helper window to take us to that space,
                // then get the AXUIElement, and finally focus that window.
                Applications.addOtherSpaceWindows(windowsOnlyOnOtherSpaces)
            }
        }
    }

    static func addRunningApplications(_ runningApps: [NSRunningApplication], _ wasLaunchedBeforeAltTab: Bool = false) {
        runningApps.forEach {
            if isActualApplication($0, wasLaunchedBeforeAltTab) {
                Applications.list.append(Application($0, wasLaunchedBeforeAltTab))
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
            if let app = (Applications.list.first { window.application.pid == $0.pid }) {
                if app.runningApplication.activationPolicy == .regular,
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

    private static func isActualApplication(_ app: NSRunningApplication, _ wasLaunchedBeforeAltTab: Bool = false) -> Bool {
        // an app can start with .activationPolicy == .prohibited, then transition to != .prohibited later
        // an app can be both activationPolicy == .accessory and XPC (e.g. com.apple.dock.etci)
        return isAnWindowApplication(app, wasLaunchedBeforeAltTab) && (isNotXpc(app) || isAndroidEmulator(app)) && !app.processIdentifier.isZombie()
    }

    private static func isAnWindowApplication(_ app: NSRunningApplication, _ wasLaunchedBeforeAltTab: Bool = false) -> Bool {
        if (wasLaunchedBeforeAltTab) {
            // For wasLaunchedBeforeAltTab=true, we assume that those apps are all launched, if they are programs with windows.
            // Even if it has 0 windows at this point, axUiElement.windows() will not throw an exception. If they are programs without windows, then axUiElement.windows() will throw an exception.
            // Here I consider there is an edge case where AltTab is starting up and this program has been loading, then it is possible that axUiElement.windows() will throw an exception.
            // I'm not quite sure if this happens, but even if it does, then after restarting this application, AltTab captures its window without any problem. I think this happens rarely.
            let allWindows = CGWindow.windows(.optionAll)
            guard let winApp = (allWindows.first { app.processIdentifier == $0.ownerPID()
                    && $0.isNotMenubarOrOthers()
                    && $0.id() != nil
                    && $0.bounds() != nil
                    && CGRect(dictionaryRepresentation: $0.bounds()!)!.width > 0
                    && CGRect(dictionaryRepresentation: $0.bounds()!)!.height > 0
            }) else {
                return false
            }
            return true
        } else {
            // Because we only add the application when we receive the didActivateApplicationNotification.
            // So here is actually the handling for the case wasLaunchedBeforeAltTab=false. For applications where wasLaunchedBeforeAltTab=true, the majority of isActive is false.
            // The reason for not using axUiElement.windows() here as a way to determine if it is a window application is that
            // When we receive the didActivateApplicationNotification notification, the application may still be loading and axUiElement.windows() will throw an exception
            // So we use isActive to determine if it is a window application, even if the application is not frontmost, isActive is still true at this time
            return true;
        }
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
}
