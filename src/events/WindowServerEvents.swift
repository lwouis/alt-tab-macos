import Cocoa

/// The WindowServer event tap: AltTab's source of truth for window lifecycle, geometry and Space
/// membership. Those physical facts come from SkyLight's notify-proc stream — immune to a busy or AX-lying
/// app (e.g. Electron throwing away its AX tree). See `SkyLight.framework.swift` for the underlying calls and
/// `windowserver/` for the pure decision layer (routing, decode, acquisition). Per-process AX observers own
/// semantic focus and title signals; AX reads still supply discovery attributes and actions.
class WindowServerEvents {
    /// The wids opted in for per-window delivery (mandatory since Sequoia). Order in/out, focus, and the
    /// removal side of the model all depend on it: a wid absent here is one we are deaf to.
    ///
    /// Two things measured on macOS 26.5 shape everything below. Create/destroy (811/804) and the Space
    /// notifications are connection-wide, but only once the connection has opted at least one window in:
    /// with every `SLSRequestNotificationsForWindows` call skipped, not even 811 arrived. And the call
    /// REPLACES this list rather than adding to it, so the request must always carry the whole set and
    /// removing a wid from it is a real unsubscribe (see `requestNotifications` and `pruneSubscriptions`).
    ///
    /// Grown by `subscribe`, from surfaces the admission resolver considers worth semantic acquisition.
    /// Level is only a positive hint: substantial floating/presentation surfaces are subscribed too.
    private static var wsWindows = Set<CGWindowID>()
    private static var started = false

    /// The cadence the shell re-arms the reducer's re-checks on (hold-release, drag-out). The reducer owns the
    /// attempt CAPS (`WindowEventReducer.holdReleaseMaxAttempts` / `dragOutMaxAttempts`); the wall-clock
    /// backstop is `cap × this`, so changing this silently rescales those caps — keep the two in view together.
    static let recheckInterval: TimeInterval = 0.4
    /// Space switches emit storms of transient animation/snapshot windows; ignore create/destroy briefly
    /// around a Space transition so they aren't mistaken for real windows (RE "transition noise").
    private static var spaceTransitionUntil: TimeInterval = 0
    /// Also read by the switcher's show path, which re-reads the topology while this holds — see
    /// `Windows.updatesBeforeShowing`.
    static var inSpaceTransition: Bool { ProcessInfo.processInfo.systemUptime < spaceTransitionUntil }
    /// debounces the 1329/1401 Space-change burst into one settled handler (replaces SpacesEvents)
    private static var spaceChangeWorkItem: DispatchWorkItem?
    /// **AltTab's own switch names its target.** It is one of the model's namers, so it goes there
    /// directly rather than waiting for the OS to describe what we just did. The activation that follows a
    /// cross-app switch carries the same wid, which is redundant and deliberately so: the two arrive in
    /// either order and naming the same window twice is a no-op.
    static func noteAltTabInitiatedFocus(_ wid: CGWindowID, _ pid: pid_t) {
        let now = ProcessInfo.processInfo.systemUptime
        altTabInitiatedFocus = (wid: wid, pid: pid, at: now)
        TrackedWindowStateBridge.dispatch(.altTabFocusedWindowInFrontmostApp(wid: wid, pid: pid, now: now))
    }

    /// One-shot and time-bounded, for the activation that follows a cross-app switch.
    private static var altTabInitiatedFocus: (wid: CGWindowID, pid: pid_t, at: TimeInterval)?

    static func observe() {
        guard !started else { return }
        started = true
        // Register our notify procs on the (AppKit-shared) main connection. The per-window opt-in is NOT seeded
        // here: `SLSGetOnScreenWindowList` sees only the current Space's on-screen windows, which is a subset
        // of what the inventory sweep enumerates a beat later and misses exactly the windows this opt-in is
        // for (hidden ones that come back). `subscribe` owns the set; see it for why the sweep feeds it.
        // We deliberately DO NOT call `SLSConnectionDispatchNotificationsToMainQueueIfNotMainThread`: on the
        // shared connection it overrode AppKit's own coordinated-notification routing, so AppKit's
        // `activeSpaceChanged:` / appearance handlers started firing inline on the `_NSEventThread` (whichever
        // thread snarfs the datagram), crashing on their main-thread-only AppKit work. Our `notifyProc` hops to
        // main itself, so we don't need that call — letting AppKit keep its main-thread delivery.
        for n in WsEventRouting.Notification.allCases {
            SLSRegisterConnectionNotifyProc(CGS_CONNECTION, notifyProc, n.rawValue, nil)
        }
        Logger.info { "WindowServerEvents: tap installed on cid \(CGS_CONNECTION)" }
        // app activation + hidden state have no WindowServer equivalent (they're AppKit concepts) — NSWorkspace
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            if let app = runningApp(note) {
                guard let pid = trackedPid(app) else { return }
                Applications.frontmostPid = pid
                let frontmostApp = Applications.findOrCreate(pid, false)
                let now = ProcessInfo.processInfo.systemUptime
                var knownTarget: CGWindowID? = nil
                if let intent = altTabInitiatedFocus, intent.pid == pid, now - intent.at < 1 {
                    knownTarget = intent.wid
                    altTabInitiatedFocus = nil
                }
                TrackedWindowStateBridge.dispatch(.appActivated(pid: pid, now: now, altTabTargetWid: knownTarget))
                if let frontmostApp {
                    _ = frontmostApp.addWindowlessWindowIfNeeded()
                    App.checkIfShortcutsShouldBeDisabled(frontmostApp.focusedWindow, frontmostApp)
                }
                // An app the user just went to is worth one more subscription attempt if its earlier ones
                // were refused: it is demonstrably alive and it is the app whose semantics matter next.
                AxObserverRegistry.shared.recover(pid, .processBecameFrontmost)
            }
        }
        center.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main) { note in
            if let app = runningApp(note) { applicationVisibilityChanged(app, hidden: true) }
        }
        center.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main) { note in
            if let app = runningApp(note) { applicationVisibilityChanged(app, hidden: false) }
        }
    }

    /// Non-capturing C callback. The WindowServer calls it on whichever thread snarfs the datagram (often the
    /// `_NSEventThread`, since we don't route this connection's notifications to the main queue — that broke
    /// AppKit's own coordinated handlers). The payload pointer is only valid for this call, so extract the
    /// integers synchronously, then hop to main ourselves before touching the model.
    private static let notifyProc: CGSConnectionNotifyProc = { event, data, len, _, _ in
        // Stamp the ARRIVAL, not the processing: the hop to main can queue behind our own work (a show, a
        // capture), which stretches the apparent gap between two events the WindowServer emitted in the same
        // instant. Every timing decision downstream — above all how long an activation's raise burst is
        // considered in flight — is only as good as this stamp.
        let at = ProcessInfo.processInfo.systemUptime
        var w0: UInt32 = 0, w8: UInt32 = 0
        var s0: UInt64 = 0
        if let d = data, len >= 4 { memcpy(&w0, d, 4) }
        if let d = data, len >= 8 { memcpy(&s0, d, 8) }
        if let d = data, len >= 12 { memcpy(&w8, d.advanced(by: 8), 4) }
        if Thread.isMainThread {
            handle(event, w0, s0, w8, at)
        } else {
            DispatchQueue.main.async { handle(event, w0, s0, w8, at) }
        }
    }

    private static func handle(_ event: UInt32, _ w0: UInt32, _ space: UInt64, _ widInSpace: UInt32,
                              _ at: TimeInterval) {
        guard let n = WsEventRouting.notification(event) else { return }
        switch n {
        case .activeSpaceChanged, .spaceCurrentChanged:
            // The same clock that mutes the transition's window storm also names the burst's LEADING edge:
            // "not already in a transition" is the first 1329/1401 of this switch. That edge gets the cheap
            // half of the reaction (`WindowEventReducer.spaceTransitionStarted`); `route` below debounces
            // the expensive half to the trailing edge, as it always has.
            let isLeadingEdge = !inSpaceTransition
            spaceTransitionUntil = ProcessInfo.processInfo.systemUptime + 0.5
            if isLeadingEdge { TrackedWindowStateBridge.dispatch(.spaceTransitionStarted) }
        case .windowCreated:
            // Creation bookkeeping lives in the reducer (`.windowCreated`). Window numbers are unique for
            // the login session, so this event must not discard facts already learned for the same surface.
            // Discovery subscribes after it has read the level.
            break
        case .windowDestroyed:
            unsubscribe(w0)
            WindowSurfaceInventory.remove(w0)
        case .windowOrderedIn:
            // Our own panel's orderedIn is the true "pixels on screen" moment — it can trail the show's
            // main-thread work by ~500ms while the WindowServer settles a Space transition. Anchor the
            // key-repeat grace to it (see `SwitcherSession.panelBecameVisibleAt`).
            if let session = SwitcherSession.current, session.panelBecameVisibleAt == nil,
               let panel = TilesPanel.shared, panel.windowNumber > 0, w0 == CGWindowID(panel.windowNumber) {
                session.panelBecameVisibleAt = ProcessInfo.processInfo.systemUptime
            }
        default:
            break
        }
        // The raw notification is NOT logged here. Every one of them routes to the reducer, which logs the
        // input plus everything it decided as a single line (`TrackedWindowStateBridge.dispatch`), so a line
        // here just doubled every event — and that duplication is what made `--logs=debug` the firehose a
        // second log channel was invented to escape. The one notification that reaches no reducer input is
        // the Space transition, which is debounced; it logs below.
        route(n, w0, space, widInSpace, at)
    }

    /// Turn a WindowServer notification into a `ReducerInput` and dispatch it through the reducer — which owns
    /// every decision this switch used to make inline (`WindowEventReducer.reduce`). Window events key off
    /// `w0` (the wid); Space-membership events (1325/1326) key off `widInSpace`/`space` from the payload.
    /// Runs on main.
    private static func route(_ n: WsEventRouting.Notification, _ w0: CGWindowID, _ space: CGSSpaceID,
                              _ widInSpace: CGWindowID, _ now: TimeInterval) {
        switch WsEventRouting.action(for: n) {
        case .noteFocusEvent:
            TrackedWindowStateBridge.dispatch(.windowFocused(wid: w0, now: now))
        case .remove:
            TrackedWindowStateBridge.dispatch(.windowDestroyed(wid: w0))
        case .updateGeometry, .refreshVisibility:
            if n == .windowOrderedOut {
                TrackedWindowStateBridge.dispatch(.windowOrderedOut(wid: w0, inSpaceTransition: inSpaceTransition))
            } else if n == .windowOrderedIn {
                TrackedWindowStateBridge.dispatch(.windowOrderedIn(wid: w0, now: now, inSpaceTransition: inSpaceTransition))
            } else {
                TrackedWindowStateBridge.dispatch(.windowMovedOrResized(wid: w0, inSpaceTransition: inSpaceTransition))
            }
        case .updateSpaceMembership:
            TrackedWindowStateBridge.dispatch(.spaceMembershipChanged(wid: widInSpace, spaceId: space,
                added: n == .windowAddedToSpace, now: now, inSpaceTransition: inSpaceTransition))
        case .acquireAndDiscriminate:
            TrackedWindowStateBridge.dispatch(.windowCreated(wid: w0, now: now, inSpaceTransition: inSpaceTransition))
        case .spaceTransition:
            // 1329/1401 fire during the transition (manuallyRefreshAllWindows above stays muted ~0.5s to
            // ignore the create/destroy storm). Debounce, then refresh topology + reconcile once it settles.
            // The half of that reaction a summon can't wait 250ms for already ran on the leading edge, in
            // `handle` above.
            Logger.debug { "WS \(n) space=\(space)" }
            scheduleSpaceChangeHandling()
        }
    }

    /// Arm the hold-release re-check (the reducer's `scheduleHoldReleaseCheck` effect): the shell owns the
    /// timer (`recheckInterval`), the reducer owns the release decision (`.holdReleaseCheck`). Re-checking rather than
    /// waiting a fixed delay is what makes the hold last exactly as long as a discovery is actually pending
    /// — a hardcoded delay expired mid-gap on a slow/busy OS and the tile vanished anyway.
    static func armHoldReleaseCheck(_ wid: CGWindowID, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + recheckInterval) {
            TrackedWindowStateBridge.dispatch(.holdReleaseCheck(wid: wid, attempt: attempt))
        }
    }

    /// Arm the drag-out re-check (the reducer's `scheduleDragOutCheck` effect), mirroring the hold-release
    /// split: shell timer, reducer verdict (`.dragOutCheck`).
    static func armDragOutCheck(_ wid: CGWindowID, previousRepWid: CGWindowID, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + recheckInterval) {
            TrackedWindowStateBridge.dispatch(.dragOutCheck(wid: wid, previousRepWid: previousRepWid, attempt: attempt))
        }
    }

    /// A plain activation names only a process. When the model has no focused-window fact for it, perform the
    /// one read that fills that hole. A dedicated element carries the measured 250ms cap, so a wedged app can
    /// occupy one bounded worker but never the main thread or the observer runloop. The answer carries the
    /// issue sequence allocated by `AttentionDriver`, and therefore loses to any app answer that overtook it.
    static func readFocusedWindowOnActivation(_ pid: pid_t) {
        guard Applications.findOrCreate(pid, false) != nil else { return }
        AXCallScheduler.shared.schedule(key: "pid-\(pid)-activation-focus", pid: pid) {
            let appAx = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appAx, 0.25)
            // Our own windows (e.g. Preferences) are tracked like any app's; both reads use the pid-aware
            // wrappers so an own-process query runs AppKit on main.
            guard let focused = try? appAx.attributes([kAXFocusedWindowAttribute], pid: pid).focusedWindow,
                  let wid = try? focused.cgWindowId(pid: pid) else {
                // A wedged or windowless app. Reported, not dropped: the model asked for this read and would
                // otherwise keep waiting on it forever.
                return DispatchQueue.main.async {
                    TrackedWindowStateBridge.dispatch(.axFocusedWindowReadFailed(pid: pid))
                }
            }
            DispatchQueue.main.async {
                TrackedWindowStateBridge.dispatch(.axFocusedWindowRead(pid: pid, wid: wid,
                    viaActivationRead: true))
            }
        }
    }


    /// 1329/1401 can fire several times during one Space transition; debounce so the topology refresh + UI
    /// reconcile run once, after it settles. The settled reaction (topology refresh + Space re-sync +
    /// fullscreen re-read + shortcut re-check + UI reconcile) is the reducer's `.spaceChangeSettled` branch.
    private static func scheduleSpaceChangeHandling() {
        spaceChangeWorkItem?.cancel()
        let work = DispatchWorkItem { TrackedWindowStateBridge.dispatch(.spaceChangeSettled) }
        spaceChangeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private static func runningApp(_ note: Notification) -> NSRunningApplication? {
        note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    private static func trackedPid(_ runningApp: NSRunningApplication) -> pid_t? {
        if runningApp.processIdentifier > 0 { return runningApp.processIdentifier }
        // Device Hub can report -1 even when acquired using its real WindowServer PID.
        return Applications.list.first { $0.runningApplication.isEqual(runningApp) }?.pid
    }

    /// Replaces AX's kAXApplicationHidden/Shown: "hidden" is an AppKit state the WindowServer doesn't own.
    private static func applicationVisibilityChanged(_ runningApp: NSRunningApplication, hidden: Bool) {
        guard let pid = trackedPid(runningApp), let app = Applications.list.first(where: { $0.pid == pid }) else { return }
        app.isHidden = hidden
        App.refreshOpenUiAfterExternalEvent(Windows.list.filter { $0.application.pid == pid })
    }

    private static func requestNotifications() {
        var list = Array(wsWindows)
        guard !list.isEmpty else { return }
        // The WHOLE set goes out every time, not the delta. `SLSRequestNotificationsForWindows` REPLACES this
        // connection's watch list; it does not add to it. Sending only the new wids left exactly one window
        // watched and every previously-watched one deaf: measured over a QA run, 0 order-outs, 0 destroys and
        // 0 focus events arrived (vs 91 / 143 / 51 for the same tests with the full array), while the
        // connection-wide creates/moves kept coming, so the app looked alive and simply never removed a
        // closed window, never noticed a minimize, and never updated the MRU.
        SLSRequestNotificationsForWindows(CGS_CONNECTION, &list, Int32(list.count))
        // How many wids we can hear from at all. A window missing from the switcher with no event trail in a
        // capture is either not enumerated or not opted in; this separates the two.
        Logger.debug { "opted in to \(list.count) windows" }
    }

    /// Opt the WindowServer into per-window notifications for a wid. Called for EVERY app-level wid the
    /// inventory sweep enumerates, not only the ones we end up tracking: an app that hides its window instead
    /// of closing it (Electron: QQ, WeChat, Notion, Slack) also tears down its a11y tree, so the sweep can
    /// acquire no element and rejects the window — and if rejection also meant "unsubscribed", the re-show
    /// would be silent (it emits no `windowCreated`; the per-window events are the ONLY signal it is back) and
    /// the window stayed invisible until the next switcher-show sweep, seconds later (#5785). Subscribing is a
    /// WindowServer fact (CGS lists this wid at an app window level); being tracked is an AX one. Coalesced so
    /// a sweep sends one request.
    ///
    /// "App-level" is a precondition, not a formality: both callers gate on it (the sweep filters its
    /// enumeration, `Applications.discoverWindow` runs `isApplicationWindow` first). Subscribing before that
    /// verdict is what put every menu, tooltip and Dock indicator on this connection's per-window stream.
    static func subscribe(_ wid: CGWindowID) {
        guard wsWindows.insert(wid).inserted else { return }
        scheduleRequestNotifications()
    }

    /// Drop a wid from the opt-in set. Only for a wid the OS confirmed gone: the destroy event (804), or the
    /// phantom sweep's CGS existence check. Our own model removals never unsubscribe — see `subscribe`.
    /// Dropping IS the unsubscribe, since the next request carries the set as it stands and the call
    /// replaces the watch list; SkyLight exports no explicit counterpart (re-checked with `dyld_info
    /// -exports` on macOS 26.5: no `SLSRemoveNotificationsForWindows` / `SLSStopNotificationsForWindows`).
    /// No request is sent from here: a dead window has nothing left to tell us, and the next real
    /// subscribe carries the shortened set anyway.
    static func unsubscribe(_ wid: CGWindowID) {
        wsWindows.remove(wid)
    }

    /// Drop from the dedup set every wid the WindowServer no longer lists, called with the inventory sweep's
    /// all-Space enumeration. `windowDestroyed` is not a reliable eraser (an app that retains its CGWindow
    /// closes a window without one), so without this the set is the size of the session's HISTORY rather than
    /// of its current windows.
    ///
    /// Dropping a wid here is a real unsubscribe, not just bookkeeping: the next request carries the set as
    /// it stands, and the call replaces the watch list. So the enumeration alone must NOT decide — a window
    /// it happens to miss (an inactive tab, an other-Space window CGS omits, #1324) would go silently deaf,
    /// which is the same failure the delta request caused. Anything still in the model is kept whatever the
    /// enumeration says; what's left to drop is a wid that is neither listed by the OS nor tracked by us.
    static func pruneSubscriptions(_ alive: Set<CGWindowID>) {
        let before = wsWindows.count
        let tracked = Set(Windows.list.compactMap { $0.cgWindowId })
        wsWindows.formIntersection(alive.union(tracked))
        let dropped = before - wsWindows.count
        if dropped > 0 { Logger.debug { "pruned \(dropped) dead subscriptions (\(wsWindows.count) left)" } }
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
