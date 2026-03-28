import Cocoa
import ApplicationServices

class Applications {
    static var list = [Application]()
    static var frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
    // Layer 0: global throttle on manuallyRefreshAllWindows (panel show full-sync)
    static let manualRefreshThrottler = Throttler(delayInMs: 1000)
    // Layer 1 (AX IPC throttle + retry + concurrency) is handled by AXCallScheduler.shared
    // Layer 2: throttle mutations to Applications.list / Windows.list on main thread
    static let appListUpdateThrottler = ThrottlerWithKey(delayInMs: 200)
    static let windowListUpdateThrottler = ThrottlerWithKey(delayInMs: 200)
    static let badgesThrottler = Throttler(delayInMs: 1000)

    static func initialDiscovery() {
        addInitialRunningApplications()
        RunningApplicationsEvents.observe()
    }

    static func addInitialRunningApplications() {
        addRunningApplications(NSWorkspace.shared.runningApplications, false)
    }

    static func manuallyRefreshAllWindows() {
        manualRefreshThrottler.throttleOrProceed {
            removeZombieWindows()
            addMissingWindows()
            reviewExistingWindows()
        }
    }

    /// we may not receive a window-created event in some cases:
    /// * we can't subscribe to the app
    /// * we couldn't subscribe to the app before the window was created
    /// * weird cases like apps launching at startup with "restaure windows"
    /// this manually queries the system for windows, and keeps our list in-sync with the actual system
    static func addMissingWindows() {
        for app in list {
            manuallyUpdateWindows(app)
        }
    }

    static func manuallyUpdateWindows(_ app: Application) {
        AXCallScheduler.shared.schedule(key: "pid-\(app.pid)", context: app.debugId, pid: app.pid) { [weak app] in
            guard let app, let axUiElement = app.axUiElement else { return }
            let axWindows = try axUiElement.allWindows(app.pid)
            guard !axWindows.isEmpty else {
                // workaround: some apps launch but take a while to create their window(s)
                // initial windows don't trigger a windowCreated notification, so we won't get notified
                // it's very unlikely an app would launch with no initial window
                // so we retry until timeout, in those rare cases (e.g. Bear.app)
                // we only do this for regular, active app, to avoid wasting CPU, with the trade-off of maybe missing some windows
                if app.runningApplication.isActive && app.runningApplication.activationPolicy == .regular {
                    throw AxError.runtimeError
                }
                return
            }
            for axWindow in axWindows {
                guard let wid = try? axWindow.cgWindowId(), wid != 0 else { continue }
                updateWindowAttributes(axWindow, wid, app)
            }
        }
    }

    /// Unified window attribute fetch + main-thread update. Used by both manual sync and reviewExistingWindows.
    static func updateWindowAttributes(_ axWindow: AXUIElement, _ wid: CGWindowID, _ app: Application) {
        AXCallScheduler.shared.schedule(key: "wid-\(wid)", context: app.debugId, pid: app.pid) { [weak app] in
            guard let app else { return }
            guard wid != 0 && wid != TilesPanel.shared.windowNumber else { return }
            let level = wid.level()
            let isSelf = app.pid == ProcessInfo.processInfo.processIdentifier
            let keys = [kAXTitleAttribute, kAXSubroleAttribute, kAXRoleAttribute, kAXSizeAttribute, kAXPositionAttribute, kAXFullscreenAttribute, kAXMinimizedAttribute] + (isSelf ? [] : [kAXChildrenAttribute])
            let a = try axWindow.attributes(keys)
            let tabSiblingTitles = isSelf ? nil : TabGroup.extractTabTitles(a.children)
            DispatchQueue.main.async { [weak app] in
                guard let app else { return }
                windowListUpdateThrottler.throttleOrProceed(key: "\(wid)") {
                    let findOrCreate = Windows.findOrCreate(axWindow, wid, app, level, a.title, a.subrole, a.role, a.size, a.position, a.isFullscreen, a.isMinimized)
                    guard let window = findOrCreate.0 else { return }
                    var tabStateChanged = false
                    if tabSiblingTitles != nil || window.tabbedSiblingWids != nil {
                        tabStateChanged = TabGroup.updateState(window, tabSiblingTitles)
                    }
                    if findOrCreate.1 || (tabStateChanged && App.appIsBeingUsed) {
                        if findOrCreate.1 { Logger.info { "manuallyUpdateWindows found a new window:\(window.debugId)" } }
                        App.refreshOpenUiAfterExternalEvent([window])
                    }
                }
            }
        }
    }

    /// refreshes AX attributes for all known windows, in case notifications were incomplete
    static func reviewExistingWindows() {
        for window in Windows.list {
            guard !window.isWindowlessApp,
                  let axUiElement = window.axUiElement,
                  let wid = window.cgWindowId else { continue }
            updateWindowAttributes(axUiElement, wid, window.application)
        }
    }

    /// we may not receive a window-destroyed event in some cases:
    /// * Sequoia bug: https://github.com/lwouis/alt-tab-macos/issues/3589
    /// * Logic Pro bug: https://github.com/lwouis/alt-tab-macos/issues/4924
    /// this acts as a garbage-collector for windows, to keep our list in-sync with the actual system
    static func removeZombieWindows() {
        // snapshot wids on main thread where Windows.list is safe to read
        let wIds = Windows.list.compactMap { $0.cgWindowId }
        guard !wIds.isEmpty else { return }
        // CGWindowListCreateDescriptionFromArray is a synchronous WindowServer IPC call; run it off main thread
        AXCallScheduler.shared.submit {
            let rawIds: CFArray = wIds.map { UnsafeRawPointer(bitPattern: UInt($0)) }.withUnsafeBufferPointer {
                CFArrayCreate(nil, UnsafeMutablePointer(mutating: $0.baseAddress), $0.count, nil)
            }
            let descriptions = CGWindowListCreateDescriptionFromArray(rawIds) as? [[CFString: Any]]
            let existingWids = descriptions?.compactMap { $0[kCGWindowNumber] } as? [CGWindowID]
            guard let existingWids else { return }
            let believedAlive = Set(wIds)
            let confirmedAlive = Set(existingWids)
            let zombies = believedAlive.subtracting(confirmedAlive)
            guard !zombies.isEmpty else { return }
            DispatchQueue.main.async {
                for window in Windows.list.reversed() {
                    if let wid = window.cgWindowId, zombies.contains(wid) {
                        Logger.debug { window.debugId }
                        Windows.removeWindows([window], true)
                    }
                }
            }
        }
    }

    static func addRunningApplications(_ runningApps: [NSRunningApplication], _ needToVerifyFrontmostPid: Bool) {
        runningApps.forEach {
            let bundleIdentifier = $0.bundleIdentifier
            let processIdentifier = $0.processIdentifier
            if bundleIdentifier == "com.apple.dock" {
                DockEvents.observe(processIdentifier)
            }
            // com.apple.universalcontrol always fails subscribeToNotification. We blacklist it to save resources on everyone's machines
            if bundleIdentifier != "com.apple.universalcontrol" {
                findOrCreate(processIdentifier, needToVerifyFrontmostPid)
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
        for tApp in terminatingApps {
            let pid = tApp.processIdentifier
            AXCallScheduler.shared.removeEntry(key: "pid-\(pid)")
            AXCallScheduler.shared.removeUnresponsivePid(pid)
            appListUpdateThrottler.removeEntry(withKey: "\(pid)")
        }
        App.refreshOpenUiAfterExternalEvent([])
    }

    static func refreshBadgesAsync() {
        guard App.appIsBeingUsed && !Preferences.hideAppBadges else { return }
        badgesThrottler.throttleOrProceed {
            let dockPid = list.first { $0.bundleIdentifier == "com.apple.dock" }?.pid
            AXCallScheduler.shared.schedule(key: "badges", context: "badges", pid: dockPid) {
                guard let dockPid,
                    let axDockChildren = try AXUIElementCreateApplication(dockPid).attributes([kAXChildrenAttribute]).children,
                    let axListAttrs = (axDockChildren.lazy.compactMap { try? $0.attributes([kAXRoleAttribute, kAXChildrenAttribute]) }.first { $0.role == kAXListRole }),
                    let axListChildren = axListAttrs.children else { return }
                let axAppDockItemUrlAndLabel: [(URL?, String?)] = try axListChildren.compactMap {
                    let a = try $0.attributes([kAXSubroleAttribute, kAXIsApplicationRunningAttribute, kAXURLAttribute, kAXStatusLabelAttribute])
                    guard a.subrole == kAXApplicationDockItemSubrole && (a.appIsRunning ?? false) else { return nil }
                    return (a.url, a.statusLabel)
                }
                guard !axAppDockItemUrlAndLabel.isEmpty else { return }
                DispatchQueue.main.async {
                    guard App.appIsBeingUsed && !Preferences.hideAppBadges else { return }
                    refreshBadges_(axAppDockItemUrlAndLabel)
                }
            }
        }
    }

    static func refreshBadges_(_ items: [(URL?, String?)]) {
        Windows.list.enumerated().forEach { (i, window) in
            let view = TilesView.recycledViews[i]
            if let app = findOrCreate(window.application.pid, false) {
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
    static func findOrCreate(_ pid: pid_t, _ needToVerifyFrontmostPid: Bool) -> Application? {
        if let app = (list.first { $0.pid == pid }) {
            return app
        }
        guard let runningApp = NSRunningApplication(processIdentifier: pid) else {
            Logger.debug { "NSRunningApplication init failed for pid:\(pid)" }
            return nil
        }
        guard ApplicationDiscriminator.isActualApplication(pid, runningApp.bundleIdentifier) else {
            return nil
        }
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
