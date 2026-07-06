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
            Logger.debug { "manuallyRefreshAllWindows" }
            syncSpacesState()
            refreshWindowsViaWindowServer()
            reviewExistingWindows()
            discardDeadPhantomWindows()
        }
    }

    /// Discard "zombie" windows so they can't accumulate. Window removal is normally driven by the per-window
    /// destroy event (804), which is reliable for windows we're subscribed to. But our discovery is async — a
    /// window seen in the SLS snapshot can die in the gap before we subscribe to it, so its 804 fires before
    /// we're listening and never removes it; it lingers flagged phantom (empty spaceIds) and would otherwise
    /// pile up forever, holding a Window + a stale subscription each. So on each refresh, reconcile ONLY the
    /// windows currently flagged phantom (the accumulation candidates — usually none) against authoritative
    /// OS existence, and drop the ones the OS confirms gone. Alive-but-phantom windows (a real window briefly
    /// between Spaces, or Slack's empty-spaceIds case #5791) still exist, so they're kept and stay correctly
    /// hidden. Bails on query failure — never discard on incomplete data. (yabai sidesteps this race by
    /// observing a window synchronously at create; our discovery is async, so this is the cheap, scoped
    /// backstop — it checks the suspicious few, not the whole list.)
    static func discardDeadPhantomWindows() {
        let phantomWids = Windows.list.compactMap { $0.isPhantom ? $0.cgWindowId : nil }
        guard !phantomWids.isEmpty else { return }
        CGSCallScheduler.existingWindowIds(among: phantomWids) { alive in
            guard let alive else { return } // query failed; don't discard on incomplete data
            let dead = Windows.list.filter { $0.isPhantom && ($0.cgWindowId.map { !alive.contains($0) } ?? false) }
            guard !dead.isEmpty else { return }
            Logger.debug { "discarding \(dead.count) dead phantom window(s): \(dead.map { $0.debugId })" }
            Windows.removeWindows(dead, true)
        }
    }

    /// Refresh Space topology + per-window Space/screen membership via SkyLight, OFF the main thread, then
    /// reconcile the open switcher only if something moved. This is the per-summon Space refresh that used
    /// to block `Windows.updatesBeforeShowing` (#5721) — relocated here (runs ~0.25s after show, throttled),
    /// and first so its correction lands before the best-effort window passes. Mirrors `refreshIsPhantom`'s
    /// capture-on-main → query-off-main → apply-on-main pattern.
    static func syncSpacesState() {
        let mainScreenUuid = Spaces.mainScreenUuid()
        let trackedWids = Windows.list.compactMap { $0.cgWindowId }
        CGSCallScheduler.run {
            let snapshot = Spaces.query(mainScreenUuid, includeWindowMap: true)
            // #5791: the inverted per-Space enumeration can miss a window (e.g. Slack), leaving it absent from
            // the map → empty spaceIds → flagged phantom → hidden ("No Window"). Backfill any tracked wid the
            // map missed with a per-window CGSCopySpacesForWindows (off-main; only the misses pay, usually none).
            var windowToSpacesMap = snapshot.windowToSpacesMap
            for wid in trackedWids where windowToSpacesMap[wid] == nil {
                let spaces = CGSCallScheduler.windowSpaces(wid)
                if !spaces.isEmpty { windowToSpacesMap[wid] = spaces }
            }
            DispatchQueue.main.async {
                var changed = Spaces.applyTopology(snapshot)
                for window in Windows.list {
                    if window.applySpacesAndScreen(windowToSpacesMap) { changed = true }
                }
                if changed {
                    TabGroup.reconcile()
                    if SwitcherSession.isActive { App.refreshOpenUiAfterExternalEvent([]) }
                }
            }
        }
    }

    /// Window discovery: take the all-Space wid set from the WindowServer and ACQUIRE an AX element for each
    /// genuinely-new app-level window (via `WindowElementAcquisition`), then discriminate it with WS-owned
    /// facts (geometry/level/fullscreen/minimized from the snapshot) + a light AX read (subrole/role/title/
    /// tabs). Already-tracked windows are skipped — events keep their geometry live, reviewExistingWindows their title/tabs.
    static func refreshWindowsViaWindowServer() {
        // the all-Space wid list comes from ONE CGSCopyWindowsWithOptionsAndTags call over every Space
        // (verified to match the per-Space fan-out), not a second windowToSpacesMap rebuild — syncSpacesState
        // owns the per-window membership map; here we only need the wid set.
        let allSpaceIds = Spaces.idsAndIndexes.map { $0.0 }
        guard !allSpaceIds.isEmpty else { return }
        CGSCallScheduler.run {
            let allSpaceWids = CGSCallScheduler.windowsInSpaces(allSpaceIds, true)
            // phantom detection reuses this same all-Space fetch (was a separate per-show CGS double-query
            // that also ran on the AX pool): a wid CGS omits from "visible" but keeps in "all" is alive-but-hidden.
            let visibleWids = Set(CGSCallScheduler.windowsInSpaces(allSpaceIds, false))
            let allWids = Set(allSpaceWids)
            let appWindows = WindowServerQuery.query(allSpaceWids).filter { WsWindowState.isApplicationWindowLevel($0) }
            DispatchQueue.main.async {
                for raw in appWindows {
                    guard let app = findOrCreate(raw.pid, false) else { continue }
                    // tracked windows with a live element stay fresh via the WS event stream
                    // (geometry/min/fullscreen) + reviewExistingWindows (title/tabs); discovery only ACQUIRES
                    // genuinely-new windows.
                    guard Windows.byWindowId[raw.wid]?.axUiElement == nil else { continue }
                    AXCallScheduler.shared.schedule(key: "wid-\(raw.wid)-acquire", context: app.debugId, pid: raw.pid, scan: true) {
                        if let element = WindowDiscriminator.acquireElementOrReject(raw.wid, raw.pid, .otherSpaceViaBruteForce) {
                            addDiscoveredWindow(element, raw, app)
                        }
                    }
                }
                // regular apps with no windows show as an icon placeholder. It's dropped when a real window
                // arrives (Window.init) or when an existing window un-phantoms (Window.updateSpaces), so a
                // window that recovers its Space after a fullscreen transition clears the stale placeholder
                // instead of leaving both the window tile and the icon tile shown.
                for app in list { _ = app.addWindowlessWindowIfNeeded() }
                applyPhantomVerdict(inVisible: visibleWids, inAll: allWids)
            }
        }
    }

    /// Acquire-and-discriminate a newly-discovered window. WindowServer-owned facts (geometry, level,
    /// fullscreen) come from the snapshot `raw`; AX is read for what WS can't give cleanly — subrole/role
    /// (discrimination), title (AX title is preferred), the main flag, minimized (the WS ordered-out bit is
    /// ambiguous — see below), and tab children.
    /// Used for genuinely-new windows only (discovery + discoverWindow). Uses the "generic" bucket so a real
    /// focus event (in the "focus" bucket) is never clobbered.
    static func addDiscoveredWindow(_ element: AXUIElement, _ raw: WsRawWindow, _ app: Application) {
        let wid = raw.wid
        AXCallScheduler.shared.schedule(key: "wid-\(wid)-generic", context: app.debugId, pid: app.pid, scan: true) { [weak app] in
            guard let app else { return }
            guard wid != 0 else { return }
            // TilesPanel.shared is nil until the switcher is first built; discovery can now run before that
            // (a window created right at launch), so don't force-unwrap it. If the panel exists and this is
            // its own window, skip it; otherwise it can't be ours, so proceed.
            if let panel = TilesPanel.shared, wid == panel.windowNumber { return }
            let isSelf = app.pid == AXUIElement.currentProcessPid
            // minimized comes from AX (kAXMinimized) — a reliable, unambiguous signal — NOT the WS ordered-out
            // bit, which is also cleared for closing / app-hidden / other-Space windows. (yabai sources
            // minimize from AX the same way: seed kAXMinimized, then track miniaturize/deminiaturize.)
            let keys = [kAXTitleAttribute, kAXSubroleAttribute, kAXRoleAttribute, kAXMainAttribute, kAXMinimizedAttribute] + (isSelf ? [] : [kAXChildrenAttribute])
            let a = try element.attributes(keys, pid: app.pid)
            let tabSiblingTitles = isSelf ? nil : TabGroup.extractTabTitles(a.children)
            let isFullscreen = WsWindowState.isFullscreen(raw)
            let isMinimized = a.isMinimized ?? false
            // Resolve the window's REAL Space(s) now, off-main. Window.init defaults spaceIds to the current
            // Space (it runs on main and must avoid this blocking CGS call, #5721); for an other-Space window
            // that default is wrong, and the first post-show syncSpacesState would then correct it → a visible
            // reflow on the first summon (misaligned space numbers / shifted title). Setting it right here makes
            // that later correction a no-op.
            let spaceIds = isSelf ? [CGSSpaceID]() : CGSCallScheduler.windowSpaces(wid)
            DispatchQueue.main.async { [weak app] in
                guard let app else { return }
                windowAttributesThrottler.throttleOrProceed(key: "\(wid)-generic") {
                    // Consume the pending-removal marker up-front, so a window rejected below can't leave it
                    // dangling. `Windows.windowsPendingSpaceRemoval` remembers a removed-from-Space event that
                    // arrived while the window was still untracked (a rapid-burst background tab, #5830 — see
                    // below); consuming here regardless of accept/reject keeps the set self-draining.
                    let wasRemovedFromSpaceWhileUntracked = Windows.windowsPendingSpaceRemoval.remove(wid) != nil
                    let findOrCreate = Windows.findOrCreate(element, wid, app, CGWindowLevel(raw.level), a.title, a.subrole, a.role, raw.bounds.size, raw.bounds.origin, isFullscreen, isMinimized)
                    guard let window = findOrCreate.0 else { return }
                    // override Window.init's current-Space default with the real Space resolved above (new
                    // windows only; existing ones stay live via events / syncSpacesState).
                    if findOrCreate.1 {
                        if wasRemovedFromSpaceWhileUntracked {
                            // It got a removed-from-Space event while still untracked → it's a background tab.
                            // Force it Space-less: the per-window CGS query still reports its OLD Space here
                            // (stale right after backgrounding), so trusting that would keep it looking like a
                            // separate on-screen window; the empty is what lets geometry group it (#5830).
                            window.applySpacesAndScreen([wid: []])
                        } else if !spaceIds.isEmpty {
                            window.applySpacesAndScreen([wid: spaceIds])
                        }
                    }
                    window.isMainWindow = a.isMain ?? false
                    var tabStateChanged = false
                    if tabSiblingTitles != nil || window.tabbedSiblingWids != nil {
                        tabStateChanged = TabGroup.updateState(window, tabSiblingTitles)
                    }
                    // a newly-discovered tab (e.g. switching to a fullscreen window's other tab) joins its
                    // fullscreen sibling's group here, so it's grouped before the next show rather than during it
                    if findOrCreate.1 { TabGroup.reconcile() }
                    if findOrCreate.1 || (tabStateChanged && SwitcherSession.isActive) {
                        if findOrCreate.1 { Logger.info { "discovered a new window:\(window.debugId)" } }
                        App.refreshOpenUiAfterExternalEvent([window])
                    }
                }
            }
        }
    }

    /// WindowServer-driven per-window state refresh (geometry + fullscreen), replacing the AX attribute read
    /// on move/resize/visibility events and the Space-change fullscreen re-read. ONE batched WS query for the
    /// whole wid set (off-main: ~84µs for a full screen vs ~15µs × N serial), decoded by WsWindowState,
    /// applied on main in a single UI reconcile. Minimized is NOT read here — it's an AX fact (kAXMinimized),
    /// refreshed at discovery + on each show, because the WS ordered-out bit can't tell minimized from
    /// closing/other-Space. Callers coalesce upstream where the input self-floods: the per-event path
    /// throttles per-wid (windowAttributesThrottler, ≤1 query/200ms on a resize drag); the Space-change path
    /// calls this once per transition.
    static func updateWindowStatesViaWindowServer(_ wids: [CGWindowID]) {
        guard !wids.isEmpty else { return }
        CGSCallScheduler.run {
            let raws = WindowServerQuery.query(wids)
            guard !raws.isEmpty else { return }
            DispatchQueue.main.async {
                var changedAny = false
                var toCapture = [Window]()
                for raw in raws {
                    guard let window = Windows.byWindowId[raw.wid] else { continue }
                    if window.updateFromWindowServer(position: raw.bounds.origin, size: raw.bounds.size, isFullscreen: WsWindowState.isFullscreen(raw)) {
                        changedAny = true
                        // Re-capture only on-screen windows. A window that just ordered out (a closing window
                        // orders out for ~1s before its destroy event fires; a minimize too) can't be
                        // screenshotted — a capture grabs a torn-down/blank "skeleton" — so keep its last
                        // on-screen frame and just refresh the layout for the geometry change.
                        if WsWindowState.isVisible(raw) { toCapture.append(window) }
                    }
                }
                if changedAny {
                    // a window entering/leaving fullscreen forms or dissolves a fullscreen tab group
                    TabGroup.reconcile()
                    if SwitcherSession.isActive { App.refreshOpenUiAfterExternalEvent(toCapture) }
                }
            }
        }
    }

    /// A tracked window just ordered out (left the screen): it was either CLOSED, or merely minimized / hidden
    /// / moved to another Space. WindowServer can't disambiguate promptly — its destroy event (804) lags a real
    /// close by seconds, or never fires at all, for apps that retain the CGWindow after closing the window
    /// (Finder does). The window's AX element, by contrast, dies within ~20ms of a real close. So probe AX off
    /// -main: a dead element (`.invalidUIElement`) means the window is gone → remove it now (prompt, OS
    /// -confirmed, NOT optimistic). A live element means it's just off-screen → leave it. `.cannotComplete`
    /// (app busy) throws so the scheduler retries with backoff instead of wrongly concluding the window closed.
    static func removeIfClosedAfterOrderOut(_ window: Window) {
        guard let axWindow = window.axUiElement, let wid = window.cgWindowId else { return }
        AXCallScheduler.shared.schedule(key: "wid-\(wid)-liveness", pid: window.application.pid) {
            let result = axWindow.liveness(pid: window.application.pid)
            if result == .cannotComplete { throw AxError.runtimeError }
            guard result == .invalidUIElement else { return }
            DispatchQueue.main.async {
                guard let window = Windows.byWindowId[wid] else { return }
                Windows.removeWindows([window], true)
            }
        }
    }

    /// A focus event (808) hit a wid we don't track yet — its create event was missed or is in-flight.
    /// Discover just that one window (it's on the current Space, since it was focused) instead of a full
    /// inventory. `Window.init`'s `checkIfFocused` then bumps its MRU order.
    static func discoverWindow(_ wid: CGWindowID) {
        CGSCallScheduler.run {
            guard let raw = WindowServerQuery.query([wid]).first, WindowDiscriminator.isApplicationWindow(raw) else { return }
            DispatchQueue.main.async {
                guard Windows.byWindowId[wid] == nil, let app = findOrCreate(raw.pid, false) else { return }
                AXCallScheduler.shared.schedule(key: "wid-\(wid)-acquire", context: app.debugId, pid: raw.pid, scan: true) {
                    if let element = WindowDiscriminator.acquireElementOrReject(wid, raw.pid, .currentSpaceViaApplicationWindows) {
                        addDiscoveredWindow(element, raw, app)
                    }
                }
            }
        }
    }

    // ≤1 inactive-tab brute-force scan per app per 3s, a frequency cap on top of the per-situation guard below.
    static let tabAdoptThrottler = ThrottlerWithKey(delayInMs: 3000)
    // The last unresolved situation (untracked-tab titles + window count) we scanned for, per app. An inactive
    // tab the brute-force can't resolve would otherwise re-fire the scan on every show forever; we attempt each
    // distinct situation once, and become eligible again the moment the app's window set changes (a tab gets
    // adopted, opened, or closed — any of which moves the count or the titles).
    static var lastInactiveTabScan = [pid_t: String]()

    /// Discover an app's INACTIVE OS TABS. A tabbed window's inactive tabs are real windows, but they appear in
    /// no CGS list, so the WindowServer-driven discovery never sees them — only the focused tab shows until the
    /// user activates another. When an AXTabGroup names tabs we have no window for (`untrackedTitles`), the
    /// inactive tab's accessibility element is still reachable: brute-force the app for the matching untracked
    /// standard windows and adopt them through the normal discovery path. Throttled per app, off-main, bounded.
    static func discoverInactiveTabs(_ app: Application, _ untrackedTitles: [String]) {
        let pid = app.pid
        let appWindowCount = Windows.list.reduce(0) { $1.application.pid == pid ? $0 + 1 : $0 }
        let situation = "\(untrackedTitles.sorted().joined(separator: "\u{1}"))|\(appWindowCount)"
        let trackedWids = Set(Windows.list.compactMap { $0.cgWindowId })
        tabAdoptThrottler.throttleOrProceed(key: "\(pid)") {
            guard lastInactiveTabScan[pid] != situation else { return }
            lastInactiveTabScan[pid] = situation
            AXCallScheduler.shared.schedule(key: "pid-\(pid)-tabadopt", context: app.debugId, pid: pid, scan: true) { [weak app] in
                guard let app else { return }
                for (wid, element, title) in AXUIElement.untrackedWindowsByBruteForce(pid, excluding: trackedWids, matching: untrackedTitles) {
                    guard let raw = WindowServerQuery.query([wid]).first else {
                        Logger.debug { "inactive tab wid:\(wid) '\(title)' has no WindowServer data; skipping" }
                        continue
                    }
                    Logger.info { "discovered inactive tab via brute-force: wid:\(wid) '\(title)'" }
                    addDiscoveredWindow(element, raw, app)
                }
            }
        }
    }

    /// Light per-window AX read for already-tracked windows: the facts WindowServer can't deliver cleanly —
    /// title (no WS title-change event), the main-window flag, minimized (AX kAXMinimized, the reliable
    /// signal — the WS ordered-out bit conflates minimized with closing/other-Space), and tab siblings.
    /// Shares the "wid-N-generic" dedup/throttle key so it never double-reads a window the discovery pass
    /// just refreshed. Runs for every tracked window on each show, so minimized stays fresh from AX.
    static func refreshWindowTitleAndTabs(_ axWindow: AXUIElement, _ wid: CGWindowID, _ app: Application, _ reconcileTabs: Bool = true) {
        AXCallScheduler.shared.schedule(key: "wid-\(wid)-generic", context: app.debugId, pid: app.pid, scan: true) { [weak app] in
            guard let app else { return }
            guard wid != 0 else { return }
            // TilesPanel.shared is nil until the switcher is first built; discovery can now run before that
            // (a window created right at launch), so don't force-unwrap it. If the panel exists and this is
            // its own window, skip it; otherwise it can't be ours, so proceed.
            if let panel = TilesPanel.shared, wid == panel.windowNumber { return }
            let isSelf = app.pid == AXUIElement.currentProcessPid
            // Skip the tab-group read when the caller says not to reconcile tabs (an order-out): an
            // ordered-out window reports its AXTabGroup inconsistently mid-transition, and order-out never
            // changes tab membership anyway. Saves the kAXChildren IPC too.
            let readTabs = !isSelf && reconcileTabs
            let keys = [kAXTitleAttribute, kAXMainAttribute, kAXMinimizedAttribute] + (readTabs ? [kAXChildrenAttribute] : [])
            let a = try axWindow.attributes(keys, pid: app.pid)
            let tabSiblingTitles = readTabs ? TabGroup.extractTabTitles(a.children) : nil
            DispatchQueue.main.async {
                windowAttributesThrottler.throttleOrProceed(key: "\(wid)-generic") {
                    guard let window = Windows.byWindowId[wid] else { return }
                    let newTitle = window.bestEffortTitle(a.title)
                    var changed = window.title != newTitle
                    if changed { window.title = newTitle; window.lastSearchQuery = nil }
                    window.isMainWindow = a.isMain ?? false
                    let newMinimized = a.isMinimized ?? false
                    if window.isMinimized != newMinimized {
                        window.isMinimized = newMinimized
                        window.recomputeIsPhantom()
                        changed = true
                    }
                    if reconcileTabs, tabSiblingTitles != nil || window.tabbedSiblingWids != nil {
                        if TabGroup.updateState(window, tabSiblingTitles) { changed = true }
                    }
                    if changed && SwitcherSession.isActive {
                        App.refreshOpenUiAfterExternalEvent([window])
                    }
                }
            }
        }
    }

    /// Re-read the AX-only facts WindowServer can't deliver, for all tracked windows, in case events were
    /// incomplete: title, the main-window flag, minimized (AX kAXMinimized — reliable, unlike the WS
    /// ordered-out bit), and tab siblings. Geometry/fullscreen are WindowServer-maintained (806/807), so
    /// those are NOT re-read or overwritten here.
    static func reviewExistingWindows() {
        for window in Windows.list {
            guard !window.isWindowlessApp,
                  let axUiElement = window.axUiElement,
                  let wid = window.cgWindowId else { continue }
            refreshWindowTitleAndTabs(axUiElement, wid, window.application)
        }
    }

    /// detect "phantom" windows: windows that the OS has tagged invisible (alpha=0, orderOut:, etc.)
    /// but that AX still hands us as live windows. Disambiguates against the other reasons a
    /// window can be in the CGS-invisible bucket (tabs, minimized, hidden app, other-Space).
    /// Runs on main from refreshWindowsViaWindowServer, reusing the all/visible wid sets that pass already
    /// fetched — no separate CGS query (and no longer on the AX pool). See PhantomWindowDetection.swift
    static func applyPhantomVerdict(inVisible: Set<CGWindowID>, inAll: Set<CGWindowID>) {
        var changed = [Window]()
        for window in Windows.list {
            guard let wid = window.cgWindowId, wid != CGWindowID(bitPattern: -1) else { continue }
            let newValue = PhantomWindowDetector.cgsVerdict(window.state, window.application.state,
                inVisibleList: inVisible.contains(wid),
                inAllList: inAll.contains(wid),
                visibleSpaceIds: Spaces.visibleSpaces)
            if window.isPhantom != newValue {
                Logger.debug { "PhantomDetect flip \(window.debugId) wid=\(wid) isPhantom=\(newValue) (inVisible=\(inVisible.contains(wid)) inAll=\(inAll.contains(wid)) isMinimized=\(window.isMinimized) isHidden=\(window.isHidden) isTabbed=\(window.isTabbed) spaceIds=\(window.spaceIds))" }
                window.isPhantom = newValue
                changed.append(window)
            }
        }
        if !changed.isEmpty {
            App.refreshOpenUiAfterExternalEvent(changed)
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
            // comparing pid here can fail here, as it can be already nil; we use isEqual here to avoid the issue
            list.removeAll { $0.runningApplication.isEqual(tApp) }
        }
        for tApp in terminatingApps {
            let pid = tApp.processIdentifier
            AXCallScheduler.shared.removeEntry(key: "pid-\(pid)")
            AXCallScheduler.shared.removeEntries(withPrefix: "pid-\(pid)-")
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
