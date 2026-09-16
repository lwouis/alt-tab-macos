import Cocoa

/// The IO seam between the live model (`Windows.list` / `Window` objects / `TabGroups` / the pending sets)
/// and the pure `WindowEventReducer`: SNAPSHOT the live model into a `TrackedWindowState`, run the reducer, APPLY
/// the resulting state back onto the live objects, EXECUTE the effects with the exact calls the adapters
/// used to make inline. Runs synchronously on the main thread, so the snapshot can't race the model.
///
/// The per-window half of that is ONE value, not a field list: a live `Window` holds its `TrackedWindow`
/// (`Window.tracked`), so snapshot reads it and apply hands the reduced one back whole. Everything else on
/// `Window` (thumbnail pixels, AX element, screenId…) stays shell-owned and is touched through effects.
class TrackedWindowStateBridge {
    /// Orchestration state with no live-model home — the activation entries, the handover halves, the
    /// off-screen set. Parked here between dispatches, as ONE value: this used to be a field-per-static, and
    /// each new reducer field then needed a static, a snapshot line and an apply line, none of which the
    /// compiler or any test asked for. See `TrackedWindowState.Carried`.
    static var carried = TrackedWindowState.Carried()

    /// Snapshot → reduce → apply → execute, in one call — the shell's one entry point into the reducer.
    ///
    /// The reduction's `.log` facts are JOINED into a single line here rather than printed one by one. One
    /// user action produces one input, and one input routinely decides five things (a Space delta, a hold, a
    /// representative move, an MRU bump, a geometry group) — five lines that only mean anything read
    /// together, interleaved in the log with whatever else was happening. One line per event is what a
    /// capture is actually read as.
    static func dispatch(_ input: ReducerInput) {
        var state = snapshot()
        var effects = WindowEventReducer.reduce(&state, input)
        // **The attention decision lands inside the SAME dispatch.** Deferring it to the next runloop turn
        // would let the switcher draw one frame with the old order before the new one arrived, which is the
        // "right, but late" verdict that is scored separately from being right.
        let attention = AttentionEngine.dispatched(input)
        if let pid = attention.readPid { effects.append(.readFocusedWindowOnActivation(pid: pid)) }
        if let attention = attention.attention {
            effects += WindowEventReducer.reduce(&state, .attentionCommitted(wid: attention.wid,
                observed: attention.observed, at: state.now))
        }
        apply(state)
        execute(effects)
        logDecisions(input, effects)
    }

    private static func logDecisions(_ input: ReducerInput, _ effects: [ReducerEffect]) {
        guard Logger.debugEnabled else { return }
        let facts = effects.compactMap { effect -> String? in
            if case .log(let line) = effect { return line }
            return nil
        }
        // A raw WindowServer event is logged even when it decided nothing — that bare "this event arrived,
        // for this wid" is what the removed per-notification line in `WindowServerEvents` provided, and it is
        // how a capture shows an event being IGNORED (muted mid Space-transition, an untracked wid, a focus
        // that didn't bump). The async read results and timer re-checks are not: those fire on their own
        // schedule (a resize drag re-queries WS state continuously, a hold re-checks every 0.4s) and saying
        // "nothing happened" that often is the noise this whole pass is removing.
        guard !facts.isEmpty || isWindowServerEvent(input) else { return }
        let line = facts.isEmpty ? describe(input) : "\(describe(input)) | \(facts.joined(separator: " | "))"
        Logger.debug { line }
    }

    private static func isWindowServerEvent(_ input: ReducerInput) -> Bool {
        switch input {
        case .windowCreated, .windowDestroyed, .windowMovedOrResized, .windowOrderedIn, .windowOrderedOut,
             .windowFocused, .spaceMembershipChanged, .spaceTransitionStarted, .spaceChangeSettled,
             .appActivated:
            return true
        case .attentionCommitted:
            return false
        case .discoveryLanded, .titleAndTabsRead, .windowServerStateRead, .spacesSynced,
             .axFocusedWindowRead, .livenessConfirmedDead, .axElementEnded, .axElementReconciled,
             .cgsWindowListsRead, .zOrderRead,
             .holdReleaseCheck, .dragOutCheck, .standaloneTabCheck,
             .altTabFocusedWindowInFrontmostApp, .axFocusedWindowReadFailed:
            return false
        }
    }

    /// The input as a short log prefix: the case name and its wid, not the whole associated-value dump.
    private static func describe(_ input: ReducerInput) -> String {
        let full = String(describing: input)
        guard let paren = full.firstIndex(of: "(") else { return full }
        let name = String(full[..<paren])
        guard let wid = full.range(of: #"wid: (\d+)"#, options: .regularExpression) else { return name }
        return "\(name) #\(full[wid].dropFirst(5))"
    }

    /// This builds a FRESH `TrackedWindowState()` per dispatch, so a state-level field it does not
    /// repopulate is not "occasionally stale": it is empty at the start of every single input, and any set
    /// written by one event and read by the next silently never fires. No replay test can catch that —
    /// `TestReducerRunner` threads one state through the whole scenario and never round-trips it through
    /// here — so the reducer's unit tests pass green against an app in which the feature does nothing at
    /// all. Eight fields shipped that way; `state.carried` and `TrackedWindowStateFieldsTests` exist so it
    /// cannot happen again silently. The PER-WINDOW fields are immune by construction: they are one value
    /// the live `Window` stores, not a copy this file has to remember to make.
    ///
    /// Everything else here is a PROJECTION of the live model and is rebuilt from it, which is why those
    /// fields need no parking: `Windows.list`, the app list, `TabGroups.table`, the `Windows.*` pending sets,
    /// the `Spaces` topology, the frontmost pid.
    static func snapshot() -> TrackedWindowState {
        var state = TrackedWindowState()
        state.windows = Windows.list.map { modelWindow($0) }
        // `isActive` is DERIVED, never read off `NSRunningApplication`. Its getter is a full LaunchServices
        // dynamic-property refresh (mach round trip + sysctl + CFString building, allocating throughout), and
        // this loop ran one per app on EVERY dispatch, and a title/tab refresh dispatches once per window,
        // so a switcher show cost O(windows × apps) cross-process calls. Measured on a 51s Instruments trace:
        // 4.9s of 7.6s total main-thread CPU and 53% of the process's entire malloc/free traffic, all of it
        // re-deriving a fact `frontmostPid` already holds. Deriving also makes the snapshot self-consistent:
        // it could previously carry `frontmostPid = A` together with `apps[B].isActive = true`, and different
        // reducer rules read different halves of that.
        let frontmostPid = Applications.frontmostPid
        for app in Applications.list {
            state.apps[app.pid] = TrackedApp(state: app.state, isActive: app.pid == frontmostPid)
        }
        state.groups = TabGroups.table
        state.held = Windows.windowsHeldVisibleForTab
        state.recentlyCreated = Windows.recentlyCreatedWindows
        state.pendingSpaceRemoval = Windows.windowsPendingSpaceRemoval
        state.pendingFocusPromotion = Windows.windowsPendingFocusPromotion
        state.carried = carried
        state.visibleSpaces = Spaces.visibleSpaces
        state.currentSpaceId = Spaces.currentSpaceId
        for (id, index) in Spaces.idsAndIndexes where state.spaceIndexById[id] == nil {
            state.spaceIndexById[id] = index
        }
        state.frontmostPid = frontmostPid
        // The time of the input about to be reduced. Stamped here so no reducer branch reads a clock itself
        // (a pure reducer can't) yet every MRU write can say WHEN it happened — see `TrackedWindowState.now`.
        state.now = ProcessInfo.processInfo.systemUptime
        return state
    }

    /// `Window` → the pure record: the live object HOLDS one, so this is a read and not a copy (see
    /// `Window.tracked`). Also used by `TabGroups.repPicker`, the one group mutation still made against the
    /// live model, so that path reaches the kernels through the SAME projection this one does.
    static func modelWindow(_ w: Window) -> TrackedWindow { w.tracked }

    /// Write the reduced state back onto the live model. The per-window half is one assignment
    /// (`Window.adopt`); what remains here are the state-level fields, which have no single owner to hand to.
    static func apply(_ state: TrackedWindowState) {
        TabGroups.replace(state.groups)
        Windows.windowsHeldVisibleForTab = state.held
        Windows.recentlyCreatedWindows = state.recentlyCreated
        Windows.windowsPendingSpaceRemoval = state.pendingSpaceRemoval
        Windows.windowsPendingFocusPromotion = state.pendingFocusPromotion
        carried = state.carried
        Applications.frontmostPid = state.frontmostPid
        // `Windows.byWindowId` is already maintained, so the common row (a tracked window) is an O(1) hit and
        // no per-dispatch map is built. The id check keeps this EXACTLY as strict as matching on `id` was:
        // a wid whose entry points at some other `Window` falls through to the map, same as a windowless
        // placeholder (`pid-N`, no wid), which is built once and only if such a row shows up.
        var byId: [String: Window]?
        func liveWindow(_ mw: TrackedWindow) -> Window? {
            if let wid = mw.wid, let w = Windows.byWindowId[wid], w.id == mw.id { return w }
            if byId == nil {
                var map = [String: Window]()
                map.reserveCapacity(Windows.list.count)
                for w in Windows.list { map[w.id] = w }
                byId = map
            }
            return byId?[mw.id]
        }
        for mw in state.windows {
            guard let w = liveWindow(mw) else { continue }
            w.adopt(mw)
        }
    }

    /// Wids awaiting a WindowServer state query, and whether a flush is already booked for this runloop turn.
    /// Main-thread only, like everything else here.
    private static var pendingWsStateWids = Set<CGWindowID>()
    private static var wsStateFlushScheduled = false

    /// **One query per runloop turn, not one per window.** The per-wid throttle above coalesces a window
    /// self-flooding (a resize drag); it does nothing for a burst ACROSS windows, which is the shape a Space
    /// switch, a display wake and an app un-hide all take — every window emits its own order-in in the same
    /// turn. Each used to become its own `SLSWindowQueryWindows`, its own hop back to main, its own reducer
    /// dispatch and its own possible UI reconcile. The query is batched by nature (it takes an array and the
    /// iterator getters read the local snapshot), and it is measured at ~27ms while the WindowServer is busy
    /// with a Space transition — so 50 windows meant ~50 × 27ms of a 4-wide lane, competing with the very
    /// Space read the summon itself needs.
    private static func queueWindowServerStateQuery(_ wids: [CGWindowID]) {
        pendingWsStateWids.formUnion(wids)
        guard !wsStateFlushScheduled else { return }
        wsStateFlushScheduled = true
        DispatchQueue.main.async {
            wsStateFlushScheduled = false
            let batch = Array(pendingWsStateWids)
            pendingWsStateWids.removeAll(keepingCapacity: true)
            Applications.updateWindowStatesViaWindowServer(batch)
        }
    }

    /// Execute the reducer's effect list with the same calls the adapters used to make inline — the
    /// throttlers/schedulers those calls contain keep doing the coalescing they always did.
    static func execute(_ effects: [ReducerEffect]) {
        for effect in effects {
            switch effect {
            case .discoverWindow(let wid, let throttled):
                if throttled {
                    Applications.windowAttributesThrottler.throttleOrProceed(key: "wid-\(wid)-discover") {
                        Applications.discoverWindow(wid)
                    }
                } else {
                    Applications.discoverWindow(wid)
                }
            case .probeWindowLiveness(let wid):
                if let w = Windows.byWindowId[wid] { Applications.removeIfClosedAfterOrderOut(w) }
            case .readTitleAndTabs(let wid, let readTabs):
                if let w = Windows.byWindowId[wid], let ax = w.axUiElement {
                    Applications.refreshWindowTitleAndTabs(ax, wid, w.application, readTabs)
                }
            case .queryWindowServerState(let wids, let throttled):
                if throttled, let wid = wids.first {
                    Applications.windowAttributesThrottler.throttleOrProceed(key: "wid-\(wid)-wsstate") {
                        queueWindowServerStateQuery([wid])
                    }
                } else {
                    queueWindowServerStateQuery(wids)
                }
            case .discoverInactiveTabs(let pid, let untrackedTitles, let requesterWid):
                if let app = Applications.list.first(where: { $0.pid == pid }) {
                    Applications.discoverInactiveTabs(app, untrackedTitles, requesterWid)
                }
            case .applyFocus(let wid):
                if let w = Windows.byWindowId[wid] {
                    w.application.focusedWindow = w
                    App.checkIfShortcutsShouldBeDisabled(w, nil)
                    WindowThumbnails.captureFocusedInBackground(w)
                }
            case .refreshUi(let wids, let onlyWhileSwitcherOpen):
                if !onlyWhileSwitcherOpen || SwitcherSession.isActive {
                    App.refreshOpenUiAfterExternalEvent(wids.compactMap { Windows.byWindowId[$0] })
                }
            case .refreshUiImmediately(let wids):
                App.refreshOpenUiImmediatelyAfterExternalEvent(wids.compactMap { Windows.byWindowId[$0] })
            case .removeWindow(let wid):
                if let w = Windows.byWindowId[wid] { Windows.removeWindows([w], true) }
            case .reconcileAxElementEnd(let wid):
                Applications.reconcileAxElementEnd(wid)
            case .retireSurface(let wid):
                Windows.retireSurfaceForReplacement(wid)
            case .deferCaptureUntilRestoreEnds(let wid):
                if let w = Windows.byWindowId[wid] { WindowThumbnails.deferCaptureUntilRestoreEnds(w) }
            case .copyThumbnail(let from, let to):
                if let src = Windows.byWindowId[from], let dst = Windows.byWindowId[to], dst.thumbnail == nil {
                    dst.thumbnail = src.thumbnail
                }
            case .scheduleHoldReleaseCheck(let wid, let attempt):
                WindowServerEvents.armHoldReleaseCheck(wid, attempt: attempt)
            case .scheduleDragOutCheck(let wid, let previousRepWid, let attempt):
                WindowServerEvents.armDragOutCheck(wid, previousRepWid: previousRepWid, attempt: attempt)
            case .scheduleStandaloneTabCheck(let wid, let siblingWid, let attempt):
                WindowServerEvents.armStandaloneTabCheck(wid, siblingWid: siblingWid, attempt: attempt)
            case .refreshSpacesTopology:
                Spaces.refresh()
            case .refreshSpacesTopologyAndSync:
                Applications.syncSpacesState()
            case .updateScreenId(let wid):
                Windows.byWindowId[wid]?.updateScreenId()
            case .removeWindowlessPlaceholder(let pid):
                if let app = Applications.list.first(where: { $0.pid == pid }) {
                    // async: callers can run inside a Windows.list iteration, and removing the placeholder
                    // mutates that list (see `Window.dropStaleWindowlessPlaceholderIfUnphantomed`)
                    DispatchQueue.main.async { app.removeWindowlessAppWindow() }
                }
            case .addWindowlessPlaceholder(let pid):
                if let app = Applications.list.first(where: { $0.pid == pid }) {
                    // async for the same reason as the removal above: the caller can be iterating Windows.list
                    DispatchQueue.main.async { app.addWindowlessWindowIfNeeded() }
                }
            case .readFocusedWindowOnActivation(let pid):
                WindowServerEvents.readFocusedWindowOnActivation(pid)
            case .checkShortcutsForFocusedWindow:
                if let frontmostPid = Applications.frontmostPid,
                   let frontmostApp = Applications.findOrCreate(frontmostPid),
                   let focusedWindow = frontmostApp.focusedWindow {
                    App.checkIfShortcutsShouldBeDisabled(focusedWindow, nil)
                }
            case .log:
                break  // joined into one line per input by `logDecisions`
            }
        }
    }
}
