import Cocoa
import ApplicationServices

class Applications {
    static var list = [Application]()

    static func initialDiscovery() {
        addInitialRunningApplications()
        RunningApplicationsEvents.observe()
    }

    static func addInitialRunningApplications() {
        addRunningApplications(NSWorkspace.shared.runningApplications)
    }

    static func manuallyRefreshAllWindows() {
        removeZombieWindows()
        addMissingWindows()
    }

    /// we may not receive a window-created event in some cases:
    /// * we can't subscribe to the app
    /// * we couldn't subscribe to the app before the window was created
    /// * weird cases like apps launching at startup with "restaure windows"
    /// this manually queries the system for windows, and keeps our list in-sync with the actual system
    static func addMissingWindows() {
        for app in list {
            app.manuallyUpdateWindows()
        }
    }

    /// we may not receive a window-destroyed event in some cases:
    /// * Sequoia bug: https://github.com/lwouis/alt-tab-macos/issues/3589
    /// * Logic Pro bug: https://github.com/lwouis/alt-tab-macos/issues/4924
    /// this acts as a garbage-collector for windows, to keep our list in-sync with the actual system
    static func removeZombieWindows() {
        let wIds = Windows.list.compactMap { $0.cgWindowId }
        guard !wIds.isEmpty else { return }
        let values = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: wIds.count)
        for (i, id) in wIds.enumerated() {
            values[i] = UnsafeRawPointer(bitPattern: UInt(id))
        }
        let rawIds = CFArrayCreate(kCFAllocatorDefault, values, wIds.count, nil)
        let descriptions = (CGWindowListCreateDescriptionFromArray(rawIds) as? [[CFString: Any]])
        let existingWids = descriptions?.compactMap { $0[kCGWindowNumber] } as? [CGWindowID]
        guard let existingWids else { return }
        let believedAlive = Set(wIds)
        let confirmedAlive = Set(existingWids)
        let zombies = believedAlive.subtracting(confirmedAlive)
        for window in Windows.list.reversed() {
            if let wid = window.cgWindowId, zombies.contains(wid) {
                Logger.debug { window.debugId() }
                Windows.removeWindows([window], true)
            }
        }
    }

    static func addRunningApplications(_ runningApps: [NSRunningApplication]) {
        runningApps.forEach {
            let bundleIdentifier = $0.bundleIdentifier
            let processIdentifier = $0.processIdentifier
            if bundleIdentifier == "com.apple.dock" {
                DockEvents.observe(processIdentifier)
            }
            // com.apple.universalcontrol always fails subscribeToNotification. We blacklist it to save resources on everyone's machines
            if bundleIdentifier != "com.apple.universalcontrol" {
                findOrCreate(processIdentifier)
            }
        }
    }

    static func removeRunningApplications(_ terminatingApps: [NSRunningApplication]) {
        let existingAppsToRemove = list.filter { app in terminatingApps.contains { tApp in app.runningApplication.isEqual(tApp) } }
        let existingWindowstoRemove = Windows.list.filter { window in terminatingApps.contains { tApp in window.application.runningApplication.isEqual(tApp) } }
        if existingAppsToRemove.isEmpty && existingWindowstoRemove.isEmpty { return }
        for tApp in terminatingApps {
            Windows.removeWindows(Windows.list.filter { $0.application.runningApplication.isEqual(tApp) }, false)
            // comparing pid here can fail here, as it can be already nil; we use isEqual here to avoid the issue
            list.removeAll { $0.runningApplication.isEqual(tApp) }
        }
        App.app.refreshOpenUi([], .refreshUiAfterExternalEvent)
    }

    static func refreshBadgesAsync() {
        guard App.app.appIsBeingUsed && !Preferences.hideAppBadges else { return }
        AXUIElement.retryAxCallUntilTimeout(callType: .updateDockBadges) {
            guard let dockPid = (list.first { $0.bundleIdentifier == "com.apple.dock" }?.pid),
                let axDockChildren = try AXUIElementCreateApplication(dockPid).attributes([kAXChildrenAttribute]).children,
                let axList = try (axDockChildren.first { try $0.attributes([kAXRoleAttribute]).role == kAXListRole }),
                let axListChildren = try axList.attributes([kAXChildrenAttribute]).children else { return }
            let axAppDockItemUrlAndLabel: [(URL?, String?)] = try axListChildren.compactMap {
                let a = try $0.attributes([kAXSubroleAttribute, kAXIsApplicationRunningAttribute, kAXURLAttribute, kAXStatusLabelAttribute])
                guard a.subrole == kAXApplicationDockItemSubrole && (a.appIsRunning ?? false) else { return nil }
                return (a.url, a.statusLabel)
            }
            guard !axAppDockItemUrlAndLabel.isEmpty else { return }
            DispatchQueue.main.async {
                guard App.app.appIsBeingUsed && !Preferences.hideAppBadges else { return }
                refreshBadges_(axAppDockItemUrlAndLabel)
            }
        }
    }

    static func refreshBadges_(_ items: [(URL?, String?)]) {
        Windows.list.enumerated().forEach { (i, window) in
            let view = ThumbnailsView.recycledViews[i]
            if let app = findOrCreate(window.application.pid) {
                if app.runningApplication.activationPolicy == .regular,
                   let matchingItem = (items.first { $0.0 == app.bundleURL }),
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

    @discardableResult
    static func findOrCreate(_ pid: pid_t) -> Application? {
        if let app = (list.first { $0.pid == pid }) {
            return app
        }
        guard let runningApp = NSRunningApplication(processIdentifier: pid) else { return nil }
        guard ApplicationDiscriminator.isActualApplication(pid, runningApp.bundleIdentifier) else { return nil }
        let app = Application(runningApp)
        list.append(app)
        return app
    }

    static func updateAppIcons() {
        for app in list {
            BackgroundWork.screenshotsQueue.addOperation { [weak app] in
                guard let app else { return }
                let r = Application.appIconWithoutPadding(app.runningApplication.icon)
                DispatchQueue.main.async { [weak app] in
                    app?.icon = r
                }
            }
        }
    }
}
