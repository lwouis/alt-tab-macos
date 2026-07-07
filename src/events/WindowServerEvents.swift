import Cocoa

/// The WindowServer event tap: AltTab's source of truth for window lifecycle, focus, geometry and Space
/// membership. Window state comes from SkyLight's notify-proc stream — immune to a busy or AX-lying app
/// (e.g. Electron throwing away its AX tree) — instead of Accessibility notifications. See
/// `SkyLight.framework.swift` for the underlying calls and `windowserver/` for the pure decision layer
/// (routing, decode, acquisition). AX is kept only for on-demand reads (subrole/title/tabs) and the actions.
class WindowServerEvents {
    /// WS-derived live window set; kept opted-in for per-window delivery (mandatory since Sequoia).
    private static var wsWindows = Set<CGWindowID>()
    private static var started = false
    /// Space switches emit storms of transient animation/snapshot windows; ignore create/destroy briefly
    /// around a Space transition so they aren't mistaken for real windows (RE "transition noise").
    private static var spaceTransitionUntil: TimeInterval = 0
    private static var inSpaceTransition: Bool { ProcessInfo.processInfo.systemUptime < spaceTransitionUntil }
    /// debounces the 1329/1401 Space-change burst into one settled handler (replaces SpacesEvents)
    private static var spaceChangeWorkItem: DispatchWorkItem?
    /// On app activation macOS raises the app's on-Space windows, emitting one focus event (808) per window.
    /// Those are RAISES, not focus changes: re-fronting each would reverse the app's MRU. We snapshot the app's
    /// wids at activation and let the 808 handler ignore exactly one per wid; a genuine focus right after (a
    /// second 808 for a wid) isn't in the set, so it still bumps. Keyed by pid (not one global set) so two quick
    /// activations don't clobber each other's storm. `until` bounds each entry so a straggler (a wid whose raise
    /// never fires) can't linger; expired entries are pruned on the next activation.
    private static var pendingActivationRaises = [pid_t: (wids: Set<CGWindowID>, until: TimeInterval)]()

    static func observe() {
        guard !started else { return }
        started = true
        // Register our notify procs + opt into per-window notifications on the (AppKit-shared) main connection.
        // We deliberately DO NOT call `SLSConnectionDispatchNotificationsToMainQueueIfNotMainThread`: on the
        // shared connection it overrode AppKit's own coordinated-notification routing, so AppKit's
        // `activeSpaceChanged:` / appearance handlers started firing inline on the `_NSEventThread` (whichever
        // thread snarfs the datagram), crashing on their main-thread-only AppKit work. Our `notifyProc` hops to
        // main itself, so we don't need that call — letting AppKit keep its main-thread delivery.
        for n in WsEventRouting.Notification.allCases {
            SLSRegisterConnectionNotifyProc(CGS_CONNECTION, notifyProc, n.rawValue, nil)
        }
        wsWindows = Set(onScreenWindowIds())
        requestNotifications()
        Logger.info { "WindowServerEvents: tap installed on cid \(CGS_CONNECTION), opted in to \(wsWindows.count) windows" }
        // app activation + hidden state have no WindowServer equivalent (they're AppKit concepts) — NSWorkspace
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            if let app = runningApp(note) {
                let pid = app.processIdentifier
                Applications.frontmostPid = pid
                // On activation macOS raises the app's on-Space windows, emitting one 808 PER window — a raise,
                // not a focus. Re-fronting each would reverse the app's MRU order (regression from the AX→WS
                // migration; 808 means "came to front", the AX path only signalled the one focused window).
                // Snapshot the app's non-minimized windows so the 808 handler ignores exactly one raise per wid;
                // `bumpFocusOnActivation` sets the single real focus. Minimized windows aren't raised (so aren't
                // listed — else un-minimizing one right after would be swallowed); off-Space windows aren't
                // raised either but are harmless if listed since their raise never comes. Time-bounded so a
                // straggler entry can't outlive the burst and swallow a later genuine focus.
                let now = ProcessInfo.processInfo.systemUptime
                pendingActivationRaises = pendingActivationRaises.filter { $0.value.until > now }  // prune expired
                let wids = Set(Windows.list.compactMap { $0.application.pid == pid && !$0.isMinimized ? $0.cgWindowId : nil })
                // 0.5s is deliberately generous (the storm is observed ~10-60ms after activation). The risk is
                // asymmetric: too SHORT is dangerous — the raise 808s are processed on the main thread behind
                // AltTab's own activation work (discovery/screenshots/phantom pass), so under load their
                // processing can lag well past that; if the window expires first, the leftover raises bump and
                // the MRU inverts again. Too LONG is nearly harmless — a window you can focus by hand is on this
                // Space and its entry is consumed by its own raise, so its genuine click (a later 808) is no
                // longer in the set and bumps; only off-Space entries linger, and focusing one requires a Space
                // switch that re-activates the app and rebuilds this set.
                pendingActivationRaises[pid] = (wids, now + 0.5)
                bumpFocusOnActivation(pid)
            }
        }
        center.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main) { note in
            if let app = runningApp(note) { applicationVisibilityChanged(app.processIdentifier, hidden: true) }
        }
        center.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main) { note in
            if let app = runningApp(note) { applicationVisibilityChanged(app.processIdentifier, hidden: false) }
        }
        // initial discovery once running apps are listed; subsequent refreshes ride events + switcher shows
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Applications.manuallyRefreshAllWindows() }
    }

    /// Non-capturing C callback. The WindowServer calls it on whichever thread snarfs the datagram (often the
    /// `_NSEventThread`, since we don't route this connection's notifications to the main queue — that broke
    /// AppKit's own coordinated handlers). The payload pointer is only valid for this call, so extract the
    /// integers synchronously, then hop to main ourselves before touching the model.
    private static let notifyProc: CGSConnectionNotifyProc = { event, data, len, _, _ in
        var w0: UInt32 = 0, w8: UInt32 = 0
        var s0: UInt64 = 0
        if let d = data, len >= 4 { memcpy(&w0, d, 4) }
        if let d = data, len >= 8 { memcpy(&s0, d, 8) }
        if let d = data, len >= 12 { memcpy(&w8, d.advanced(by: 8), 4) }
        if Thread.isMainThread {
            handle(event, w0, s0, w8)
        } else {
            DispatchQueue.main.async { handle(event, w0, s0, w8) }
        }
    }

    private static func handle(_ event: UInt32, _ w0: UInt32, _ space: UInt64, _ widInSpace: UInt32) {
        guard let n = WsEventRouting.notification(event) else { return }
        switch n {
        case .activeSpaceChanged, .spaceCurrentChanged:
            spaceTransitionUntil = ProcessInfo.processInfo.systemUptime + 0.5
        case .windowCreated:
            if !inSpaceTransition {
                subscribe(w0)
                // Remember it's brand-new so its first focus event can promote it even if its app has since
                // gone background (cmd-N spam → open AltTab: the burst's 808s land while the app is inactive).
                Windows.recentlyCreatedWindows.insert(w0)
            }
        case .windowDestroyed:
            unsubscribe(w0)
        default:
            break
        }
        Logger.debug { "WS \(n) wid=\(w0)" + (WsEventRouting.payloadCarriesSpaceId(n) ? " space=\(space) wid=\(widInSpace)" : "") }
        route(n, w0, space, widInSpace)
    }

    /// Turn a WindowServer notification into a targeted model mutation. Window events key off `w0` (the wid);
    /// Space-membership events (1325/1326) key off `widInSpace`/`space` from the payload. Runs on main.
    private static func route(_ n: WsEventRouting.Notification, _ w0: CGWindowID, _ space: CGSSpaceID, _ widInSpace: CGWindowID) {
        switch WsEventRouting.action(for: n) {
        case .bumpFocusOrder:
            if let window = Windows.byWindowId[w0] {
                // A brand-new window earns one promotion that ignores the app-active guard: the focus it gets
                // right after creation. `appendWindow` already fronts new windows on discovery; this also honors
                // the flag for the rare ordering where the create event lands after the window was appended.
                // Consume it whatever the outcome, so only that first focus is exempt from the guard.
                let wasJustCreated = Windows.recentlyCreatedWindows.remove(w0) != nil
                // Ignore the app-activation raise storm: one 808 fires per on-Space window as macOS raises the
                // app, but those are raises, not focus changes — bumping each would reverse the app's MRU. We
                // consume exactly one per wid from that app's activation snapshot; `bumpFocusOnActivation` sets
                // the one real focus. A brand-new window's focus is always honored; a genuine focus after the
                // burst (a wid's second 808) isn't in the set, so it bumps too.
                let pid = window.application.pid
                let now = ProcessInfo.processInfo.systemUptime
                let isActivationRaise = pendingActivationRaises[pid].map { $0.until > now && $0.wids.contains(w0) } ?? false
                if isActivationRaise { pendingActivationRaises[pid]?.wids.remove(w0) }
                if wasJustCreated || (window.application.runningApplication.isActive && !isActivationRaise) {
                    window.application.focusedWindow = window
                    App.checkIfShortcutsShouldBeDisabled(window, nil)
                    if let changed = Windows.updateLastFocusOrder(window) {
                        App.refreshOpenUiAfterExternalEvent(changed)
                    }
                }
                // else: tracked, app not frontmost, not brand-new → a transient focus race (e.g. a background
                // app re-focusing one of its windows). Ignore to avoid MRU churn; a real activation re-bumps
                // it via bumpFocusOnActivation.
            } else {
                // focus hit a window we don't track yet → discover just it, not a full inventory. Record the
                // focus so it isn't lost: discovery is async, so the window is promoted the moment it's
                // appended (Windows.appendWindow), else a freshly-focused window (e.g. cmd-N spam) whose 808
                // outran its discovery would land at the back of the MRU.
                Windows.windowsPendingFocusPromotion.insert(w0)
                Applications.discoverWindow(w0)
            }
        case .remove:
            Windows.windowsPendingFocusPromotion.remove(w0)
            Windows.recentlyCreatedWindows.remove(w0)
            Windows.windowsPendingSpaceRemoval.remove(w0)
            if let window = Windows.byWindowId[w0] {
                Windows.removeWindows([window], true)
            }
        case .updateGeometry, .refreshVisibility:
            if let window = Windows.byWindowId[w0] {
                if n == .windowOrderedOut {
                    // A tracked window left the screen: closed, or merely minimized / hidden / moved to another
                    // Space. WS's destroy event (804) lags a real close by seconds — or never fires — for apps
                    // that retain the CGWindow (Finder), so we can't wait for it; the AX element dies within
                    // ~20ms. Probe AX: dead ⇒ closed ⇒ remove now; alive ⇒ just off-screen ⇒ keep. Skip during
                    // a Space transition — then an order-out is just the leaving Space's windows going off
                    // -screen, not a close, and the post-transition syncSpacesState reconcile covers it.
                    if !inSpaceTransition {
                        Applications.removeIfClosedAfterOrderOut(window)
                        // Minimize has no dedicated WS event — it surfaces as an order-out that isn't a close — so
                        // re-read kAXMinimized here. Without it the model keeps a stale isMinimized and minDemin
                        // toggles the wrong way (a just-minimized window's "unminimize" re-minimizes it instead).
                        // Do NOT reconcile tabs on an order-out: a window going off-screen
                        // (minimize, fullscreen, Space-move) reports its AXTabGroup inconsistently
                        // mid-transition, so a transient empty read would wrongly dissolve the tab
                        // group and strand its inactive tabs as phantoms (the fullscreen-tab
                        // disappearance). Order-out never changes tab membership anyway.
                        if let axWindow = window.axUiElement {
                            Applications.refreshWindowTitleAndTabs(axWindow, w0, window.application, false)
                        }
                    }
                } else {
                    // moved/resized/ordered-in for a tracked window → refresh just that window's WindowServer
                    // facts (geometry, fullscreen) from a WS query, NOT an AX read. Coalesced per-wid so a
                    // resize drag collapses to ≤1 query/200ms.
                    Applications.windowAttributesThrottler.throttleOrProceed(key: "wid-\(w0)-wsstate") {
                        Applications.updateWindowStatesViaWindowServer([w0])
                    }
                    // De-minimize likewise has no dedicated WS event; it surfaces as an order-in →
                    // re-read kAXMinimized. Like order-out, do NOT reconcile tabs here: an order-in
                    // during a fullscreen or Space transition reports the AXTabGroup inconsistently,
                    // and a transient empty read would dissolve the group and strand its inactive
                    // tabs as phantoms (the fullscreen-tab disappearance). Tab membership is
                    // reconciled at the stable points — discovery and each show.
                    if n == .windowOrderedIn, let axWindow = window.axUiElement {
                        Applications.refreshWindowTitleAndTabs(axWindow, w0, window.application, false)
                    }
                }
            } else if !inSpaceTransition, n == .windowMoved || n == .windowResized || n == .windowOrderedIn {
                // Untracked: a window is created at 0x0 and sized a beat later, so the create-time discovery
                // rejects it on the min-size filter. Its first move/resize/ordered-in is the signal it now has
                // real geometry → discover it right then, instead of waiting for the next throttled full rescan
                // (the ~1-2s "new window is slow to appear" regression). Coalesced; discoverWindow is idempotent.
                Applications.windowAttributesThrottler.throttleOrProceed(key: "wid-\(w0)-discover") {
                    Applications.discoverWindow(w0)
                }
            }
        case .updateSpaceMembership:
            // 1325/1326 carry (spaceId, wid) in the payload, so update just that window's spaceIds — no CGS
            // re-query / full rescan. Untracked wid → remember a removal so discovery can honor the empty Space
            // (a rapid-burst background tab whose remove fires before it's tracked, #5830); a later add cancels
            // it. Then the missed delta no longer strands the tab shown-as-separate until the next show.
            guard let window = Windows.byWindowId[widInSpace] else {
                if n == .windowRemovedFromSpace { Windows.windowsPendingSpaceRemoval.insert(widInSpace) }
                else { Windows.windowsPendingSpaceRemoval.remove(widInSpace) }
                return
            }
            if window.applySpaceMembershipDelta(space, added: n == .windowAddedToSpace) {
                // switching a fullscreen window's tabs swaps which one holds the Space — regroup so the
                // newly-backgrounded tab stays shown instead of being flagged phantom
                TabGroup.reconcile()
                if SwitcherSession.isActive { App.refreshOpenUiAfterExternalEvent([window]) }
            }
        case .acquireAndDiscriminate:
            // Discover just this new wid right away (not the throttled full rescan — that was the ~1-2s
            // "new window is slow to appear" regression). If the window is still 0x0 at create time it'll be
            // rejected on size and re-discovered from its first move/resize (see .updateGeometry above). A
            // window created on another Space (discoverWindow's current-Space acquisition can't reach it) is
            // picked up by the next switcher-show full rescan.
            if !inSpaceTransition { Applications.discoverWindow(w0) }
        case .spaceTransition:
            // 1329/1401 fire during the transition (manuallyRefreshAllWindows above stays muted ~0.5s to
            // ignore the create/destroy storm). Debounce, then refresh topology + reconcile once it settles.
            scheduleSpaceChangeHandling()
        }
    }

    /// AppKit app-activation is the backstop for a window-focus (808) the focus handler dropped because the
    /// app wasn't frontmost yet — 808 and NSRunningApplication.isActive are separate clocks and 808 can win the
    /// race (e.g. un-minimizing a background app's window). Read the now-front app's focused window from AX and
    /// bump the MRU, same as a focus event would. Mirrors yabai's APPLICATION_FRONT_SWITCHED handler.
    private static func bumpFocusOnActivation(_ pid: pid_t) {
        guard let app = Applications.findOrCreate(pid, false), let appAx = app.axUiElement else { return }
        AXCallScheduler.shared.schedule(key: "pid-\(pid)-activation-focus", pid: pid) {
            // Our own windows (e.g. Preferences) are tracked like any app's, so self activation gets the same MRU
            // bump; both AX reads here go through the pid-aware guards so the own-process ones run on main.
            guard let focused = try? appAx.attributes([kAXFocusedWindowAttribute], pid: pid).focusedWindow,
                  let wid = try? focused.cgWindowId(pid: pid) else { return }
            DispatchQueue.main.async {
                guard Applications.frontmostPid == pid, let window = Windows.byWindowId[wid] else { return }
                window.application.focusedWindow = window
                App.checkIfShortcutsShouldBeDisabled(window, nil)
                if let changed = Windows.updateLastFocusOrder(window) {
                    App.refreshOpenUiAfterExternalEvent(changed)
                }
            }
        }
    }

    /// 1329/1401 can fire several times during one Space transition; debounce so the topology refresh + UI
    /// reconcile run once, after it settles.
    private static func scheduleSpaceChangeHandling() {
        spaceChangeWorkItem?.cancel()
        let work = DispatchWorkItem { handleSpaceChanged() }
        spaceChangeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// The Space-switch reaction that used to live in `SpacesEvents` (NSWorkspace.activeSpaceDidChange):
    /// refresh the Space topology (cached for the switcher's hot path, #5721), re-read fullscreen for the
    /// current Space (the Safari full-screen-video window emits no resize/move event), re-check shortcut
    /// disabling for the focused window, and reconcile any open switcher.
    private static func handleSpaceChanged() {
        Spaces.refresh()
        // re-derive per-window Space membership authoritatively once the transition settles. The 1325/1326
        // deltas keep it live between transitions, but a Space/display change fires a burst of them (a monitor
        // plug/unplug creates/destroys whole Spaces), so a full backfill here corrects anything the deltas
        // missed instead of waiting for the next switcher show. Off-main; reconciles the UI when it lands.
        Applications.syncSpacesState()
        Windows.updateIsFullscreenOnCurrentSpace()
        if let frontmostPid = Applications.frontmostPid,
           let frontmostApp = Applications.findOrCreate(frontmostPid, false),
           let focusedWindow = frontmostApp.focusedWindow {
            App.checkIfShortcutsShouldBeDisabled(focusedWindow, nil)
        }
        App.refreshOpenUiAfterExternalEvent(Windows.list)
    }

    private static func runningApp(_ note: Notification) -> NSRunningApplication? {
        note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    /// Replaces AX's kAXApplicationHidden/Shown: "hidden" is an AppKit state the WindowServer doesn't own.
    private static func applicationVisibilityChanged(_ pid: pid_t, hidden: Bool) {
        guard let app = Applications.list.first(where: { $0.pid == pid }) else { return }
        app.isHidden = hidden
        App.refreshOpenUiAfterExternalEvent(Windows.list.filter { $0.application.pid == pid })
    }

    private static func onScreenWindowIds() -> [CGWindowID] {
        var buf = [CGWindowID](repeating: 0, count: 4096)
        var out: Int32 = 0
        guard SLSGetOnScreenWindowList(CGS_CONNECTION, 0, 4096, &buf, &out) == .success, out > 0 else { return [] }
        return Array(buf.prefix(Int(out)))
    }

    private static func requestNotifications() {
        var list = Array(wsWindows)
        guard !list.isEmpty else { return }
        SLSRequestNotificationsForWindows(CGS_CONNECTION, &list, Int32(list.count))
    }

    /// Opt the WindowServer into per-window notifications for a wid we now track — from ANY source, including
    /// the brute-force discovery of other-Space windows. Those never appear in SLSGetOnScreenWindowList, so
    /// before this they were tracked-but-unsubscribed: we got no destroy/geometry/order events for them (AX's
    /// per-app observers used to cover them, any Space). Coalesced so a discovery burst re-requests once.
    static func subscribe(_ wid: CGWindowID) {
        guard wsWindows.insert(wid).inserted else { return }
        scheduleRequestNotifications()
    }

    /// Drop a wid from the opt-in set when we stop tracking it (destroyed / removed).
    static func unsubscribe(_ wid: CGWindowID) {
        guard wsWindows.remove(wid) != nil else { return }
        scheduleRequestNotifications()
    }

    private static var requestNotificationsPending = false
    /// Coalesce re-requests to once per main-runloop tick — a discovery pass appends many windows at once.
    private static func scheduleRequestNotifications() {
        guard !requestNotificationsPending else { return }
        requestNotificationsPending = true
        DispatchQueue.main.async {
            requestNotificationsPending = false
            requestNotifications()
        }
    }
}
