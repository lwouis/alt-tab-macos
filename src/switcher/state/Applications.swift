import Cocoa
import ApplicationServices

class Applications {
    static var list = [Application]()
    static var frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
    // Throttlers coalesce redundant work. They are SEPARATE from AXCallScheduler, which is a pure executor
    // (bounded pools + retry, no throttle). Each one below states what it coalesces and why:
    // A — suppress redundant inbound events: coalesce resize/move/title bursts to ≤1 attribute read per window
    static let windowAttributesThrottler = ThrottlerWithKey(delayInMs: 200)
    // B — suppress redundant recompute: ≤1 full window-inventory scan per second (on switcher show)
    static let fullRescanThrottler = Throttler(delayInMs: 1000)
    // B — ≤1 Dock-badge fetch per second
    static let dockBadgeThrottler = Throttler(delayInMs: 1000)
    // C — cap a resource: ≤1 thumbnail capture per window per 200ms
    static let screenshotThrottler = ThrottlerWithKey(delayInMs: 200)

    static func initialDiscovery() {
        addInitialRunningApplications()
        RunningApplicationsEvents.observe()
    }

    static func addInitialRunningApplications() {
        addRunningApplications(NSWorkspace.shared.runningApplications, false)
    }

    static func manuallyRefreshAllWindows() {
        fullRescanThrottler.throttleOrProceed {
            syncSpacesState()
            addMissingApps()
            removeZombieWindows()
            addMissingWindows()
            reviewExistingWindows()
            refreshIsPhantom()
        }
    }

    /// Refresh Space topology + per-window Space/screen membership via SkyLight, OFF the main thread, then
    /// reconcile the open switcher only if something moved. This is the per-summon Space refresh that used
    /// to block `Windows.updatesBeforeShowing` (#5721) — relocated here (runs ~0.25s after show, throttled),
    /// and first so its correction lands before the best-effort window passes. Mirrors `refreshIsPhantom`'s
    /// capture-on-main → query-off-main → apply-on-main pattern.
    static func syncSpacesState() {
        let mainScreenUuid = Spaces.mainScreenUuid()
        AXCallScheduler.shared.submit(scan: true) {
            let snapshot = Spaces.query(mainScreenUuid, includeWindowMap: true)
            DispatchQueue.main.async {
                var changed = Spaces.applyTopology(snapshot)
                for window in Windows.list {
                    if window.applySpacesAndScreen(snapshot.windowToSpacesMap) { changed = true }
                }
                if changed && SwitcherSession.isActive {
                    App.refreshOpenUiAfterExternalEvent([])
                }
            }
        }
    }

    /// we may not be tracking an app at all: we failed to subscribe to it, or it never entered our list.
    /// that is fine as long as it has no window; but once it owns an on-screen window, we can trace that
    /// window back to its owner pid and backfill the app. this is the non-AX twin of the
    /// `handleEventWindow` → `findOrCreate` backfill, which only fires for apps we already subscribe to.
    /// note: `CGWindowList` is current-Space-only (#1324), so this complements (does not replace) the
    /// brute-force remote-token discovery that finds other-Space windows.
    static func addMissingApps() {
        let knownPids = Set(list.map { $0.pid })
        // CGWindowListCopyWindowInfo is a synchronous WindowServer IPC call; run it off the main thread
        AXCallScheduler.shared.submit {
            let untrackedPids = Set(CGWindow.windows(.optionOnScreenOnly).compactMap { window -> pid_t? in
                // most-selective check first: nearly every on-screen window belongs to an already-tracked app,
                // so the knownPids lookup short-circuits before we test layer (layer 0 == normal windows;
                // skips menubar/UI/floating chrome, see CGWindow.isNotMenubarOrOthers)
                guard let pid = window.ownerPID(), !knownPids.contains(pid), window.layer() == 0 else { return nil }
                return pid
            })
            guard !untrackedPids.isEmpty else { return }
            DispatchQueue.main.async {
                for pid in untrackedPids {
                    guard let app = findOrCreate(pid, false) else { continue }
                    Logger.info { "addMissingApps found untracked app with window:\(app.debugId)" }
                    manuallyUpdateWindows(app)
                }
            }
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
        AXCallScheduler.shared.schedule(key: "pid-\(app.pid)", context: app.debugId, pid: app.pid, scan: true) { [weak app] in
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
    /// Uses the "generic" bucket so a real focus event (which lives in the "focus" bucket) is never clobbered.
    static func updateWindowAttributes(_ axWindow: AXUIElement, _ wid: CGWindowID, _ app: Application) {
        AXCallScheduler.shared.schedule(key: "wid-\(wid)-generic", context: app.debugId, pid: app.pid, scan: true) { [weak app] in
            guard let app else { return }
            guard wid != 0 && wid != TilesPanel.shared.windowNumber else { return }
            let level = wid.level()
            let isSelf = app.pid == ProcessInfo.processInfo.processIdentifier
            let keys = [kAXTitleAttribute, kAXSubroleAttribute, kAXRoleAttribute, kAXSizeAttribute, kAXPositionAttribute, kAXFullscreenAttribute, kAXMinimizedAttribute, kAXMainAttribute] + (isSelf ? [] : [kAXChildrenAttribute])
            let a = try axWindow.attributes(keys)
            let tabSiblingTitles = isSelf ? nil : TabGroup.extractTabTitles(a.children)
            DispatchQueue.main.async { [weak app] in
                guard let app else { return }
                windowAttributesThrottler.throttleOrProceed(key: "\(wid)-generic") {
                    let findOrCreate = Windows.findOrCreate(axWindow, wid, app, level, a.title, a.subrole, a.role, a.size, a.position, a.isFullscreen, a.isMinimized)
                    guard let window = findOrCreate.0 else { return }
                    window.isMainWindow = a.isMain ?? false
                    var tabStateChanged = false
                    if tabSiblingTitles != nil || window.tabbedSiblingWids != nil {
                        tabStateChanged = TabGroup.updateState(window, tabSiblingTitles)
                    }
                    if findOrCreate.1 || (tabStateChanged && SwitcherSession.isActive) {
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
        CGSCallScheduler.existingWindowIds(among: wIds) { alive in
            guard let alive else { return } // query failed; don't garbage-collect on incomplete data
            let zombies = Set(wIds).subtracting(alive)
            guard !zombies.isEmpty else { return }
            for window in Windows.list.reversed() {
                if let wid = window.cgWindowId, zombies.contains(wid) {
                    Logger.debug { window.debugId }
                    Windows.removeWindows([window], true)
                }
            }
        }
    }

    /// detect "phantom" windows: windows that the OS has tagged invisible (alpha=0, orderOut:, etc.)
    /// but that AX still hands us as live windows. Disambiguates against the other reasons a
    /// window can be in the CGS-invisible bucket (tabs, minimized, hidden app, other-Space).
    /// see src/experimentations/PhantomWindowDetection.swift
    static func refreshIsPhantom() {
        let widsAndWindows: [(CGWindowID, Window)] = Windows.list.compactMap { w in
            guard let wid = w.cgWindowId, wid != CGWindowID(bitPattern: -1) else { return nil }
            return (wid, w)
        }
        guard !widsAndWindows.isEmpty else { return }
        let spaceIds = Spaces.idsAndIndexes.map { $0.0 }
        AXCallScheduler.shared.submit {
            let visibleCgsWindowIds = Set(CGSCallScheduler.windowsInSpaces(spaceIds, false))
            let allCgsWindowIds = Set(CGSCallScheduler.windowsInSpaces(spaceIds, true))
            DispatchQueue.main.async {
                var changed = [Window]()
                for (wid, window) in widsAndWindows {
                    let newValue = PhantomWindowDetector.cgsVerdict(window.state, window.application.state,
                        inVisibleList: visibleCgsWindowIds.contains(wid),
                        inAllList: allCgsWindowIds.contains(wid),
                        visibleSpaceIds: Spaces.visibleSpaces)
                    if window.isPhantom != newValue {
                        Logger.debug { "PhantomDetect flip \(window.debugId) wid=\(wid) isPhantom=\(newValue) (inVisible=\(visibleCgsWindowIds.contains(wid)) inAll=\(allCgsWindowIds.contains(wid)) isMinimized=\(window.isMinimized) isHidden=\(window.isHidden) isTabbed=\(window.isTabbed) spaceIds=\(window.spaceIds))" }
                        window.isPhantom = newValue
                        changed.append(window)
                    }
                }
                if !changed.isEmpty {
                    App.refreshOpenUiAfterExternalEvent(changed)
                }
            }
        }
    }

    static func addRunningApplications(_ runningApps: [NSRunningApplication], _ needToVerifyFrontmostPid: Bool) {
        runningApps.forEach { runningApp in
            let bundleIdentifier = runningApp.bundleIdentifier
            let processIdentifier = runningApp.processIdentifier
            if bundleIdentifier == "com.apple.dock" {
                DockEvents.observe(processIdentifier)
            }
            // com.apple.universalcontrol always fails subscribeToNotification. We blacklist it to save resources on everyone's machines
            guard bundleIdentifier != "com.apple.universalcontrol" else { return }
            // classify off-main (process & sysctl IPC), then create on main if it's a real app (#5721).
            // findOrCreate stays synchronous for the rarer AX-event new-pid path (it re-checks the list).
            ProcessCallScheduler.isActualApplication(processIdentifier, bundleIdentifier) { isActual in
                if isActual { createActualApp(runningApp) }
            }
        }
    }

    // The post-classification half of findOrCreate, for the discovery path where classification already
    // ran off-main via ProcessCallScheduler. Runs on main; dedups by pid so it can't race a parallel creation.
    private static func createActualApp(_ runningApp: NSRunningApplication) {
        let pid = runningApp.processIdentifier
        guard !(list.contains { $0.pid == pid }) else { return }
        list.append(Application(runningApp))
    }

    static func removeRunningApplications(_ terminatingApps: [NSRunningApplication]) {
        let existingAppsToRemove = list.filter { app in terminatingApps.contains { tApp in app.runningApplication.isEqual(tApp) } }
        let existingWindowstoRemove = Windows.list.filter { window in terminatingApps.contains { tApp in window.application.runningApplication.isEqual(tApp) } }
        if existingAppsToRemove.isEmpty && existingWindowstoRemove.isEmpty { return }
        for tApp in terminatingApps {
            Windows.removeWindows(Windows.list.filter { $0.application.runningApplication.isEqual(tApp) }, false)
            // Detach the per-app AX observer's runloop source before dropping the strong ref —
            // without this, every quit app leaves an orphaned source pinned to the AX events
            // thread runloop forever (leak #1).
            for app in list where app.runningApplication.isEqual(tApp) {
                app.releaseAxObserver()
            }
            // comparing pid here can fail here, as it can be already nil; we use isEqual here to avoid the issue
            list.removeAll { $0.runningApplication.isEqual(tApp) }
        }
        for tApp in terminatingApps {
            let pid = tApp.processIdentifier
            AXCallScheduler.shared.removeEntry(key: "pid-\(pid)")
            AXCallScheduler.shared.removeEntries(withPrefix: "pid-\(pid)-")
            // one-shot subscription keys (see Application.observeEvents) use the `sub-app-` prefix, which
            // the `pid-` cleanup above misses; strip them here too or they leak 6 entries per app.
            AXCallScheduler.shared.removeEntry(key: "sub-app-\(pid)")
            AXCallScheduler.shared.removeEntries(withPrefix: "sub-app-\(pid)-")
            AXCallScheduler.shared.removeUnresponsivePid(pid)
        }
        App.refreshOpenUiAfterExternalEvent([])
    }

    static func refreshBadgesAsync() {
        guard SwitcherSession.isActive else { return }
        dockBadgeThrottler.throttleOrProceed {
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
                    guard SwitcherSession.isActive else { return }
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
