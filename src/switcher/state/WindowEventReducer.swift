import CoreGraphics
import Foundation

/// The pure orchestration reducer: evolves a `TrackedWindowState` in response to one `ReducerInput` and returns the
/// `ReducerEffect`s the shell must execute. This is where the ADAPTER-LAYER decisions live — which kernel
/// runs when, with which model mutations, on which event or async read result — extracted from
/// `WindowServerEvents.route` / `Applications` / `TabGroup` so a recorded debug log replays as a unit test
/// (see `TestReducerRunner`). The DECISION kernels themselves (`TabGroupResolver`, `PhantomWindowDetector`,
/// `AttentionModel`) are unchanged; the reducer only sequences them and applies their verdicts.
///
/// **Replay fidelity is the constraint:** the reducer must read state at the same point in the same sequence
/// the live path would, so a replayed decision sees identical facts to a live one. Anything that re-decides
/// in the shell, or reads the model at a different moment than the reducer does, breaks that and the corpus
/// stops being evidence.
enum WindowEventReducer {

    /// How long a create / Space-join stays the pairing partner of a backgrounding tab. A tab SWITCH is one
    /// user action the OS reports as two UNLINKED notifications — the mint's Space-join and the outgoing
    /// tab's 1326 — so the only thing correlating them is that they arrive close in time. This is that
    /// window. It gates the hold-visible arming, the group-inheritance handover, and their supersede, so all
    /// of them must agree; a per-site literal drifted them apart once. Deliberately generous: the OS can lag
    /// under load, and pairing a beat late is cheaper than missing the pairing (a split group, a stuck tile).
    /// The true fix is an IDENTITY that links the two notifications (the `AXUIElement`-stability lead in
    /// `Windows`), which would delete this timer; until that is proven, time is the only correlation the OS
    /// hands us.
    static let recentPairingWindow: TimeInterval = 0.5

    /// Re-check caps, in ATTEMPTS. The shell re-arms each check on a fixed interval
    /// (`WindowServerEvents.recheckInterval`, 0.4s), so the wall-clock backstop is `cap × interval`:
    /// hold-release ≈ 20s, drag-out ≈ 3.2s. Kept as counts because the reducer is pure and does not own the
    /// clock — but the two files must be read together, hence the cross-reference. These are BACKSTOPS, not
    /// the mechanism: both checks release on a real signal first (the incoming tab's claim / the joiner's
    /// frame settling). The cap only covers the OS never sending that signal — which happens, and without it
    /// a leaked flag pinned a hold for a whole session (rec13).
    static let holdReleaseMaxAttempts = 50
    static let dragOutMaxAttempts = 8

    // MARK: - the reducer entry point

    /// Evolve the state by one input and return the effects to execute. Covers what `WindowServerEvents.route`
    /// and its `handle` dispatch (create bookkeeping, activation, the hold-release / drag-out re-checks); the
    /// shell routes events here and executes the effects, it decides nothing itself.
    static func reduce(_ state: inout TrackedWindowState, _ input: ReducerInput) -> [ReducerEffect] {
        switch input {
        case .windowCreated(let wid, let now, let inSpaceTransition):
            // Space switches emit storms of transient animation/snapshot windows; ignore create/destroy
            // briefly around a Space transition so they aren't mistaken for real windows.
            guard !inSpaceTransition else { return [] }
            // Remember it's brand-new so its first focus event can promote it even if its app has since
            // gone background (cmd-N spam → open AltTab: the burst's 808s land while the app is inactive).
            state.recentlyCreated.insert(wid)
            state.carried.lastWindowCreatedAt = now
            state.carried.lastWindowCreatedWid = wid
            // Discover just this new wid right away (not the throttled full rescan — that was the ~1-2s
            // "new window is slow to appear" regression). If the window is still 0x0 at create time it'll be
            // rejected on size and re-discovered from its first move/resize (see `.windowMovedOrResized`). A
            // window created on another Space (discoverWindow's current-Space acquisition can't reach it) is
            // picked up by the next switcher-show full rescan.
            return [.discoverWindow(wid: wid, throttled: false)]
        case .windowDestroyed(let wid):
            state.pendingFocusPromotion.removeValue(forKey: wid)
            state.recentlyCreated.remove(wid)
            state.carried.pendingHandoverEdge.removeValue(forKey: wid)
            state.pendingSpaceRemoval.removeValue(forKey: wid)
            state.held.remove(wid)
            state.carried.offScreen.remove(wid)
            // A membership kept for a wid that was never superseded now outlives the drain (see
            // `spaceMembershipChanged`), so a wid created and destroyed without ever being discovered would
            // strand its entry forever. Nothing else drains it — this is the rec13 leak shape, drained here.
            state.carried.pendingGroupInheritance.removeValue(forKey: wid)
            if state.window(wid) != nil {
                if let i = state.windowIndex(wid) { state.windows[i].lifecycle = .surfaceEnded }
                return [.log(state.removalLog(wid, reason: "wsDestroyed")),
                        .retireSurface(wid), .removeWindow(wid)]
                    + refrontAfterFocusedWindowBecomesUnavailable(&state, wid: wid)
            }
            return []
        case .windowMovedOrResized(let wid, let inSpaceTransition):
            return movedResizedOrOrderedIn(&state, wid: wid, orderedIn: false, now: 0, inSpaceTransition: inSpaceTransition)
        case .windowOrderedIn(let wid, let now, let inSpaceTransition):
            return movedResizedOrOrderedIn(&state, wid: wid, orderedIn: true, now: now, inSpaceTransition: inSpaceTransition)
        case .windowOrderedOut(let wid, let inSpaceTransition):
            // Recorded BEFORE the transition guard below, and for untracked wids too: the order-outs this set
            // exists to remember are exactly the ones a Space switch causes, and they can land on either side
            // of the notification that arms `inSpaceTransition` (measured: the fullscreen-enter 816s came in
            // the same millisecond as the Space notification, the exit's 815s came 519ms BEFORE it). Skipping
            // them here would leave the re-show indistinguishable from a raise, which is the whole point.
            state.carried.offScreen.insert(wid)
            // Same reason `offScreen` is recorded above the transition guard: the bit describes the WHOLE
            // order-out stream, including the ones a Space switch causes, so it stays true to the
            // WindowServer rather than to our interpretation of it. Tab-grouping READS this bit, so the pass
            // that owns grouping runs when it flips — leaving it changed without reconciling is a state no
            // later input converges from (the harness's fixed-point check catches exactly that). This is the
            // geometry/normalize pass, NOT the AX tab re-read the comment below rules out.
            var orderedOutEffects = [ReducerEffect]()
            if state.windowIndex(wid) != nil {
                orderedOutEffects = orderedInPhantomEdge(&state, wid: wid) { $0.windows[$1].isOrderedIn = false }
                orderedOutEffects += reconcile(&state)
            }
            // A tracked window left the screen: closed, or merely minimized / hidden / moved to another
            // Space. WS's destroy event (804) lags a real close by seconds — or never fires — for apps
            // that retain the CGWindow (Finder), so we can't wait for it; the AX element dies within
            // ~20ms. Probe AX: dead ⇒ closed ⇒ remove now; alive ⇒ just off-screen ⇒ keep. Skip during
            // a Space transition — then an order-out is just the leaving Space's windows going off
            // -screen, not a close, and the post-transition syncSpacesState reconcile covers it.
            guard state.window(wid) != nil, !inSpaceTransition else { return orderedOutEffects }
            // Minimize has no dedicated WS event — it surfaces as an order-out that isn't a close — so ASK
            // the WindowServer what state the window is in now. `WsWindowState.minimizedTag` answers it and
            // sets ~35ms after the minimize, while this order-out arrives ~500ms in (the animation), so the
            // bit is long settled by the time the query runs. This used to be an AX `kAXMinimized` read, a
            // call into the window's OWN app, which stalls for exactly as long as that app is busy
            // animating; the window then stayed unflagged and the show's phantom pass, seeing it absent from
            // the CGS visible list, latched it and dropped it from the switcher entirely.
            // Do NOT reconcile tabs on an order-out: a window going off-screen
            // (minimize, fullscreen, Space-move) reports its AXTabGroup inconsistently
            // mid-transition, so a transient empty read would wrongly dissolve the tab
            // group and strand its inactive tabs as phantoms (the fullscreen-tab
            // disappearance). Order-out never changes tab membership anyway.
            return orderedOutEffects + [.probeWindowLiveness(wid), .queryWindowServerState(wids: [wid], throttled: false),
                    .readTitleAndTabs(wid: wid, readTabs: false)]
        case .windowFocused(let wid, _):
            return windowFocused(&state, wid: wid)
        case .spaceMembershipChanged(let wid, let spaceId, let added, let now, let inSpaceTransition):
            return spaceMembershipChanged(&state, wid: wid, spaceId: spaceId, added: added, now: now,
                inSpaceTransition: inSpaceTransition)
        case .spaceTransitionStarted:
            return spaceTransitionStarted(&state)
        case .spaceChangeSettled:
            return spaceChangeSettled(&state)
        case .appActivated(let pid, _, _):
            return appActivated(&state, pid: pid)
        case .discoveryLanded(let wid, let accepted, let newlyTracked, let adoptedAsInactiveTab,
                              let spaceMembership, let isOrderedIn, let tabGroup):
            return discoveryLanded(&state, wid: wid, accepted: accepted, newlyTracked: newlyTracked,
                adoptedAsInactiveTab: adoptedAsInactiveTab, spaceMembership: spaceMembership,
                isOrderedIn: isOrderedIn, tabGroup: tabGroup)
        case .titleAndTabsRead(let wid, let tabGroup, let reconcileTabs, let changedSoFar):
            return titleAndTabsRead(&state, wid: wid, tabGroup: tabGroup,
                reconcileTabs: reconcileTabs, changedSoFar: changedSoFar)
        case .axFocusedWindowRead:
            return []
        case .altTabFocusedWindowInFrontmostApp:
            // Our own switch into the app that is already frontmost. It names its target, so it reaches the
            // order through `AttentionDriver` like every other namer.
            return []
        case .axFocusedWindowReadFailed:
            // The app did not answer. `AttentionDriver` records the silence so the read it issued stops
            // being outstanding; nothing about the model changes, because a missing answer is not evidence
            // against whatever the app said last.
            return []
        case .windowServerStateRead(let snapshots):
            return windowServerStateRead(&state, snapshots)
        case .spacesSynced(let windowToSpaces, let queried, let answered, let placedByWindowServer, let topologyChanged):
            return spacesSynced(&state, windowToSpaces: windowToSpaces, queried: queried,
                answered: answered, placedByWindowServer: placedByWindowServer, topologyChanged: topologyChanged)
        case .livenessConfirmedDead(let wid):
            // A CLOSE the OS confirmed twice: the cached element died AND the app no longer lists the wid
            // among its windows (`removeIfClosedAfterOrderOut`, which keeps the window on a stale-ref-only
            // verdict). Logged with its reason so a capture says WHICH path condemned it.
            guard let i = state.windowIndex(wid) else { return [] }
            state.windows[i].lifecycle = .confirmedClosed
            return [.log(state.removalLog(wid, reason: "axElementDead")), .removeWindow(wid)]
                + refrontAfterFocusedWindowBecomesUnavailable(&state, wid: wid)
        case .axElementEnded(let wid):
            guard let i = state.windowIndex(wid) else { return [] }
            state.windows[i].lifecycle = .axElementEnded
            return [.log("lifecycle #\(wid) axElementEnded"), .reconcileAxElementEnd(wid)]
        case .axElementReconciled(let wid, let verdict):
            guard let i = state.windowIndex(wid) else { return [] }
            switch verdict {
            case .replacementFound:
                state.windows[i].lifecycle = .alive
                return [.log("lifecycle #\(wid) replacementFound")]
            case .inconclusive:
                state.windows[i].lifecycle = .replacementPending
                return [.log("lifecycle #\(wid) replacementPending")]
            case .confirmedClosed:
                state.windows[i].lifecycle = .confirmedClosed
                return [.log(state.removalLog(wid, reason: "axDestroyReconciled")), .removeWindow(wid)]
                    + refrontAfterFocusedWindowBecomesUnavailable(&state, wid: wid)
            }
        case .cgsWindowListsRead(let visible, let all, let queried):
            return cgsWindowListsRead(&state, visible: visible, all: all, queried: queried)
        case .zOrderRead(let widsTopFirst):
            let changed = state.seedFocusOrderFromZOrder(widsTopFirst)
            guard !changed.isEmpty else { return [] }
            return [.log("zOrder seed reordered \(changed.count) never-focused window(s)"),
                    .refreshUi(wids: changed, onlyWhileSwitcherOpen: true)]
        case .attentionCommitted(let wid, let observed, let at):
            return attentionCommitted(&state, wid: wid, observed: observed, at: at)
        case .holdReleaseCheck(let wid, let attempt):
            return holdReleaseCheck(&state, wid: wid, attempt: attempt)
        case .dragOutCheck(let wid, let previousRepWid, let attempt):
            return dragOutCheck(&state, wid: wid, previousRepWid: previousRepWid, attempt: attempt)
        }
    }

    // MARK: - WS-event branches (was `WindowServerEvents.route`)

    /// The phantom edge around a write to `isOrderedIn`. The ordered-in bit is now one of the two facts the
    /// verdict is made of (`PhantomWindowDetector`), so flipping it can flip the derived phantom — and a
    /// flip that emits no placeholder effect is the duplicate-tile / no-tile-at-all bug of #5849, which
    /// every OTHER phantom-moving path already guards (`applySpaceMembershipDelta`, `applyWindowSpaces`,
    /// `cgsWindowListsRead`). Call around the write, never instead of it.
    private static func orderedInPhantomEdge(_ state: inout TrackedWindowState, wid: CGWindowID,
                                             _ write: (inout TrackedWindowState, Int) -> Void) -> [ReducerEffect] {
        guard let i = state.windowIndex(wid) else { return [] }
        let before = state.isPhantom(state.windows[i])
        write(&state, i)
        guard state.isPhantom(state.windows[i]) != before, !state.windows[i].isWindowlessApp else { return [] }
        let pid = state.windows[i].pid
        if before { return [.removeWindowlessPlaceholder(pid: pid)] }
        return appHasRealWindow(state, pid: pid) ? [] : [.addWindowlessPlaceholder(pid: pid)]
    }

    /// moved/resized/ordered-in. Tracked → refresh just that window's WindowServer facts (geometry,
    /// fullscreen) from a WS query, NOT an AX read; coalesced per-wid so a resize drag collapses to ≤1
    /// query/200ms. An order-in also re-reads kAXMinimized (de-minimize has no dedicated WS event) but does
    /// NOT reconcile tabs: an order-in during a fullscreen or Space transition reports the AXTabGroup
    /// inconsistently, and a transient empty read would dissolve the group and strand its inactive tabs as
    /// phantoms (the fullscreen-tab disappearance). Untracked → mutable physical or semantic evidence may
    /// now make the surface admissible, so discover it again (coalesced; idempotent). Standard and main
    /// windows do not wait for non-zero geometry.
    private static func movedResizedOrOrderedIn(_ state: inout TrackedWindowState, wid: CGWindowID, orderedIn: Bool,
                                                now: TimeInterval, inSpaceTransition: Bool) -> [ReducerEffect] {
        // Consumed here whatever we decide below, and for untracked wids too, so the set stays self-draining
        // and mirrors the WindowServer's own on-screen bit rather than accumulating our interpretation of it.
        _ = orderedIn && state.carried.offScreen.remove(wid) != nil
        if state.window(wid) != nil {
            var effects: [ReducerEffect] = [.queryWindowServerState(wids: [wid], throttled: true)]
            // An order-in IS the ordered-in bit turning on, so it is recorded here rather than waiting for the
            // batched query the effect above schedules — tab-grouping runs on this pass. Only on the order-in:
            // this function also serves 806/807 move/resize (`orderedIn: false` there, meaning "not an
            // order-in", NOT "off screen"), so writing the flag unconditionally asserted that every window
            // being dragged or resized had left the screen. The 816 clears the bit, in its own branch.
            if orderedIn {
                effects += orderedInPhantomEdge(&state, wid: wid) { $0.windows[$1].isOrderedIn = true }
            }
            if orderedIn {
                effects.append(.readTitleAndTabs(wid: wid, readTabs: false))
                // An order-in of a window we believe is MINIMIZED is the un-minimize, and the WindowServer is
                // the only timely witness of it. Measured live (macOS 26, Finder and Chrome alike): a Dock
                // restore emits this 815 ~30ms in, while the app keeps answering kAXMinimized=true for
                // ~530ms. So the AX read queued one line above lands INSIDE that stale window and writes
                // `true` straight back, and nothing re-reads it afterwards — the full re-review only runs on
                // `windowDidBecomeKey`, i.e. only when the panel actually shows, so a burst of quick alt+tabs
                // never triggers it. The window then sits in the minimized bucket, and with
                // `showMinimizedWindows == .showAtTheEnd` it is stranded at the very back of the list until
                // some later show happens to fix it (the reported "the queue flashed and the window
                // appeared"). Restoring the same window through AX instead does NOT show this: there the flag
                // flips in ~35ms, which is why the AX-driven QA paths never caught it.
                //
                // Deriving it from the event needs no timing at all: a minimized window is off-screen by
                // definition, and the OS never orders one in for any other reason — a Space re-show brings
                // back the Space's ON-screen windows and leaves its minimized ones minimized. The AX read
                // stays, now as confirmation rather than as the only source.
                let unminimized = state.windowIndex(wid).map { i -> Bool in
                    guard state.windows[i].isMinimized else { return false }
                    state.windows[i].isMinimized = false
                    return true
                } ?? false
                if unminimized {
                    effects.append(.log("unminimized #\(wid) (ws orderedIn while flagged minimized)"))
                    // inactive tabs mirror their active tab's minimized state, so the group must re-derive
                    effects.append(contentsOf: reconcile(&state))
                    // ...and REPAINT, because the switcher may be open right now: minimizing from the panel
                    // (the "m" shortcut) leaves it open, so the un-minimize that follows has to clear the
                    // minimized indicator on a tile the user is looking at. Nothing else on this event does
                    // it: the WS query queued above ends up a no-op (the frame is unchanged and its late
                    // `isMinimized=true` is rejected once the wid left `offScreen`), the title read reports
                    // no change, and the MRU bump below — the only other repaint here — is gated on the
                    // window's app being frontmost, which it is not while our panel holds the key window.
                    // So the tile kept the indicator until the panel was closed and reopened.
                    // No wids to re-capture HERE: the window comes back with the frame and content it had,
                    // and the restore animation is still running, so a capture now grabs a partial frame —
                    // the OS draws the window scaled down mid-animation, which lands in the switcher as a
                    // mini window in a transparent tile. The capture is deferred to the end of the animation
                    // instead, and every capture asked for meanwhile is held back with it.
                    effects.append(.refreshUi(wids: [], onlyWhileSwitcherOpen: true))
                    effects.append(.deferCaptureUntilRestoreEnds(wid: wid))
                }
                // **An 815 is not a raise the user made.** It is emitted for every window of a Space being
                // re-shown, for every window of an app being activated, and for a genuine Cmd+` alike, and
                // measurement found no way to tell them apart from the event: on an in-app raise the app
                // posts `AXFocusedWindowChanged` FIRST and the 815 arrives 0.5-4ms later, so the answer was
                // always going to come from the app. What is left here is the un-minimize bookkeeping above,
                // which is about window STATE rather than about the user's attention.
            }
            return effects
        }
        guard !inSpaceTransition else { return [] }
        // The same in-app raise, for a window we do not track YET. An app that hides its window instead of
        // closing it (WeChat to the tray) has that window removed from the model, keeps the CGWindow, and on
        // reopen the OS re-shows the SAME wid: no create event, no 808, just this order-in. Discovery then
        // takes ~80ms, and if the user alt-tabs inside that gap the window used to land at the very BACK of
        // the MRU, behind even the windowless placeholders (#5785, Weixin on the last tile). Remember the
        // signal with the time it happened so discovery can place it where it belongs. `requirePid` because
        // the frontmost-app test above cannot run yet: an untracked wid has no pid, so we keep the pid that
        // was frontmost at this instant and let discovery confirm the window is that app's.
        if state.pendingFocusPromotion[wid] == nil, let frontmostPid = state.frontmostPid {
            state.pendingFocusPromotion[wid] = .circumstantial(at: now, frontmostPid: frontmostPid)
        }
        return [.discoverWindow(wid: wid, throttled: true)]
    }

    /// **An 808 is not attention.** Measured across twelve scenarios: the WindowServer never names a window
    /// accessibility had not already named, it always names it later, and on an activation it fires once per
    /// on-Space window, which is a set rather than an answer. Everything it used to decide about the order
    /// now comes from the app itself, through `AttentionDriver`.
    ///
    /// It stays as evidence that a window EXISTS, which is the one thing it is authoritative about.
    private static func windowFocused(_ state: inout TrackedWindowState, wid: CGWindowID) -> [ReducerEffect] {
        guard state.window(wid) != nil else { return untrackedWindowFocused(&state, wid: wid) }
        state.recentlyCreated.remove(wid)
        return []
    }

    /// An 808 for a wid we do not track yet is not attention, but it IS evidence the window exists: discover
    /// just it, rather than a whole inventory.
    private static func untrackedWindowFocused(_ state: inout TrackedWindowState, wid: CGWindowID) -> [ReducerEffect] {
        [.discoverWindow(wid: wid, throttled: false)]
    }

    /// Closing the window that holds MRU slot 0 hands the front to whoever held slot 1 — which can belong to
    /// a DIFFERENT app than the one still frontmost. macOS never moves focus across apps because a window
    /// closed, so re-front the frontmost app's own next window instead. Without this, a dialog that took slot
    /// 0 while its app's main window's 808 was swallowed as an activation raise leaves the previous app at the
    /// front forever: every alt-tab then lands back on the window the user is already in, and nothing corrects
    /// it (a re-focus of the already-focused window of the already-frontmost app emits neither an activation
    /// nor an 808). #5346, REAPER + its "Insert Multiple Media Items" dialog.
    private static func refrontAfterFocusedWindowBecomesUnavailable(_ state: inout TrackedWindowState,
                                                                    wid: CGWindowID) -> [ReducerEffect] {
        guard let window = state.window(wid), window.lastFocusOrder == 0,
              let pid = state.frontmostPid, window.pid == pid else { return [] }
        let successor = state.windows
            .filter { $0.wid != nil && $0.wid != wid && $0.pid == pid && !$0.isWindowlessApp
                && !$0.isMinimized && !state.isTabbed($0) && !state.isPhantom($0) }
            .min { $0.lastFocusOrder < $1.lastFocusOrder }
        guard let successorWid = successor?.wid else { return [] }
        return applyFocusAndBump(&state, wid: successorWid, at: nil, .structuralRepair)
    }

    /// **An app naming one of its background tabs IS the tab switch.** `AttentionDriver` maps a tab to the tile
    /// that currently stands for its group, because that is where attention lands visually; but the window it
    /// NAMED is the one the app just made active, so the group's representative moves there first. Without
    /// this the switch is invisible: the order gets bumped and the tile keeps showing the tab the user left.
    private static func attentionCommitted(_ state: inout TrackedWindowState, wid: CGWindowID,
                                           observed: CGWindowID, at: TimeInterval) -> [ReducerEffect] {
        var effects = [ReducerEffect]()
        var target = wid
        if observed != wid, state.window(observed) != nil,
           let group = state.groups.groupId(of: observed), state.groups.groupId(of: wid) == group {
            effects += state.setGroupRepresentative(observed, reason: "semanticTab").logs.map { .log($0) }
            target = observed
        }
        guard state.window(target) != nil else { return effects }
        effects += inheritHeldGroupAtAttention(&state, target: target)
        effects += applyFocusAndBump(&state, wid: target, at: at, .attentionReducer)
        normalizeGroupVisibility(&state, into: &effects)
        return effects
    }

    /// Finder can publish two new fullscreen surfaces for one tab while the WindowServer handover has room
    /// to remember only the latest join. The semantic focus answer names the real destination after its model
    /// object exists but before `discoveryLanded`; use the still-held outgoing representative to settle that
    /// ambiguous physical pair atomically. The hold and shared Space are the in-flight handover proof.
    private static func inheritHeldGroupAtAttention(_ state: inout TrackedWindowState,
                                                    target: CGWindowID) -> [ReducerEffect] {
        guard state.groups.groupId(of: target) == nil, let incoming = state.window(target) else { return [] }
        let incomingSpaces = Set(incoming.spaceIds)
        guard !incomingSpaces.isEmpty,
              let outgoing = state.held.compactMap({ state.window($0) }).filter({ candidate in
                  candidate.wid != target && candidate.pid == incoming.pid
                      && (!incomingSpaces.isDisjoint(with: candidate.spaceIds)
                          || candidate.lastLeftSpaceId.map(incomingSpaces.contains) == true)
              }).min(by: { $0.lastFocusOrder < $1.lastFocusOrder }),
              let outgoingWid = outgoing.wid else { return [] }
        // **The held side must bring tab evidence of its own**, because the hold is not any: it says "kept
        // drawable through a discovery gap", and a window ENTERING FULLSCREEN fits that description by
        // accident — it goes Space-less while the transition mints its own surfaces, so the recent-create arm
        // of `shouldHoldVisibleThroughDiscovery` arms the hold, and the app then answers the activation with
        // the OTHER window it still has on the windowed Space. Same app, held, and naming the Space it just
        // left: every clause above passes, and on the hold alone the merge joined two SEPARATE windows into
        // one. Nothing re-splits an established group, so the window that went fullscreen was hidden for the
        // rest of the session (measured 2026-09-09, two 620x472 windows of one app, the background one sent to
        // fullscreen: `group form ... reason=semanticHandover` 519ms into the transition, and the window read
        // `shown=false tabbed=true` from then on — `testSemanticFocusDoesNotCarryAHeldWindowThatCarriesNoGroup`).
        guard let members = heldTabEvidence(state, outgoing: outgoingWid, target: target) else { return [] }
        let formed = state.formGroup([target] + members, representative: target, reason: "semanticHandover")
        return formed.logs.map { .log($0) }
    }

    /// The two forms that evidence takes. A GROUP the held window already carries is the plain one.
    ///
    /// The other is the MINTED CHAIN, which exists precisely when the group does not yet: a cmd+T burst mints
    /// a wid per tab, each displacing the last before discovery reaches it, and `spaceMembershipChanged` hands
    /// the membership down (`inheritance #a → #b`), so `siblingWids` says nothing for the whole burst. A chain
    /// member adopted early — an AX window-created answer lands mid-burst and attention admits the wid — then
    /// stands as a SECOND TILE until the burst's last mint is discovered and forms the group: a tab visibly
    /// escapes its group (QA T-02, measured 2026-09-10, 250ms of two tiles during a 5x cmd+T on Finder).
    /// Both wids in ONE chain is the link. Fullscreen never has it: the chain that hold arms carries only the
    /// window going fullscreen, and its key is an UNTRACKED joiner, so the tracked window the app answers with
    /// can be neither.
    private static func heldTabEvidence(_ state: TrackedWindowState, outgoing: CGWindowID,
                                        target: CGWindowID) -> [CGWindowID]? {
        if let members = state.groups.siblingWids(of: outgoing), members.count > 1 { return members }
        let linked = state.carried.pendingGroupInheritance.contains { key, members in
            let chain = Set(members + [key])
            return chain.contains(outgoing) && chain.contains(target)
        }
        return linked ? [outgoing] : nil
    }

    /// **The one place the window order is written.** The trio every focus-bump site fires (focusedWindow +
    /// shortcut re-check + background capture — one effect), then the MRU promotion and the re-render of the
    /// windows that moved. `at` is the time the OS brought the window forward: the input's own `now` wherever
    /// the input carries one, and `state.now` (the time of the input being reduced) for the branches that
    /// move the MRU without an event of their own.
    ///
    /// `source` says what entitles this call to write, and only two things do: an attention decision, which
    /// is the model saying the user is now looking at this window, and a structural repair, which is not a
    /// claim about the user at all (the front window closed, or a tab group changed which member it draws).
    /// A raw physical event cannot use this as an attention claim. Physical evidence reaches it only through
    /// a narrowly-named structural repair, where the model is preserving a replacement/representative rather
    /// than asserting that an 808, order-in, or activation raise revealed key focus.
    private static func applyFocusAndBump(_ state: inout TrackedWindowState, wid: CGWindowID,
                                          at: TimeInterval? = nil,
                                          _ source: AttentionWriteSource) -> [ReducerEffect] {
        var effects: [ReducerEffect] = [.applyFocus(wid), .log(state.mruBumpLog(wid))]
        // Focusing proves the window is real: clear any stale phantom latch NOW rather than waiting for the
        // next show's CGS pass, and drop the placeholder its app grew while it looked windowless (#5849).
        if state.clearPhantomOnFocus(wid), let pid = state.window(wid)?.pid {
            effects.append(.removeWindowlessPlaceholder(pid: pid))
        }
        let changed = state.noteFocus(wid, at: at ?? state.now)
        effects.append(source == .attentionReducer
            ? .refreshUiImmediately(wids: changed)
            : .refreshUi(wids: changed, onlyWhileSwitcherOpen: false))
        return effects
    }

    /// **Record one half of a Space HANDOVER, and pair it with the other if that one just landed.** A window
    /// taking another's place on a Space is the only shape a tab switch has at the WindowServer: 1326 for the
    /// tab going off, 1325 for the tab coming on, same Space, a beat apart. Nothing in the delivery path
    /// orders those two, so each half is remembered per Space and pairs with whichever arrives second.
    ///
    /// Deliberately narrow, because a wrong edge is worse than no edge — it would hide a real window rather
    /// than merely fail to group a tab:
    /// - **Same app.** Time-pairing alone crosses wires between apps. Where both wids are tracked the pid is
    ///   available now and is checked now; where one is not, the check moves to consumption, exactly as
    ///   `pendingGroupInheritance` does it.
    /// - **Not during a Space transition**, where a switch emits joins and leaves for many windows at once and
    ///   any pairing between them is invented (the same reason the transition mutes discovery).
    /// - **Within `recentPairingWindow`**, the one clock every other pairing in this file already uses.
    ///
    /// An UNTRACKED half is deferred rather than dropped (`pendingHandoverEdge`). Finder mints a brand-new wid
    /// per tab switch with no create event, so the incoming half of that handover is a wid we have never seen
    /// — the very case with the least other evidence, since a minted tab shares no size cluster with the
    /// frozen siblings it belongs to and fullscreen exposes no AXTabGroup to re-read. Dropping the edge there
    /// would have left the edge working only where geometry already coped.
    private static func recordHandover(_ state: inout TrackedWindowState, wid: CGWindowID, spaceId: UInt64,
                                       added: Bool, now: TimeInterval, inSpaceTransition: Bool) {
        guard !inSpaceTransition else { return }
        // This window's own edge is stale the moment it moves again: joining a Space means it is no longer
        // the one that was replaced, leaving one means it is no longer the incumbent that replaced anybody.
        if let i = state.windowIndex(wid) {
            if added { state.windows[i].replacedByWid = nil } else { state.windows[i].replacedWid = nil }
        }
        let half = TrackedWindowState.SpaceHandoverHalf(wid: wid, at: now)
        let opposite = added ? state.carried.lastSpaceLeave[spaceId] : state.carried.lastSpaceJoin[spaceId]
        if added { state.carried.lastSpaceJoin[spaceId] = half } else { state.carried.lastSpaceLeave[spaceId] = half }
        guard let other = opposite, other.wid != wid, now - other.at < recentPairingWindow else { return }
        let leftWid = added ? other.wid : wid
        let joinedWid = added ? wid : other.wid
        guard let leftIndex = state.windowIndex(leftWid) else {
            // the LEAVING half is untracked: remember the edge for its discovery, if it ever comes
            if state.window(joinedWid) != nil {
                state.carried.pendingHandoverEdge[leftWid] = .init(partnerWid: joinedWid, pendingSideJoined: false)
            }
            return
        }
        guard let joinedIndex = state.windowIndex(joinedWid) else {
            state.carried.pendingHandoverEdge[joinedWid] = .init(partnerWid: leftWid, pendingSideJoined: true)
            return
        }
        guard state.windows[leftIndex].pid == state.windows[joinedIndex].pid else { return }
        state.windows[leftIndex].replacedByWid = joinedWid
        state.windows[joinedIndex].replacedWid = leftWid
    }

    /// Apply a handover edge that was recorded while this wid was still untracked (a minted tab switch). The
    /// pid check that `recordHandover` does inline for two tracked windows happens HERE instead, because the
    /// pid is what we were missing: a time pairing between two apps is a coincidence, and this is the first
    /// moment it can be told from a handover.
    /// Returns the wid this window REPLACED, when that is what the edge said — the caller uses it to group
    /// the pair. Only from this one-shot application, never from the stored `replacedWid`: the edge is paired
    /// within `recentPairingWindow` and consumed exactly once here, so it is fresh by construction, whereas
    /// the stored field lives until the window rejoins a Space and can be arbitrarily old.
    @discardableResult
    private static func applyPendingHandoverEdge(_ state: inout TrackedWindowState, wid: CGWindowID) -> CGWindowID? {
        guard let pending = state.carried.pendingHandoverEdge.removeValue(forKey: wid),
              let mine = state.windowIndex(wid), let theirs = state.windowIndex(pending.partnerWid),
              state.windows[mine].pid == state.windows[theirs].pid else { return nil }
        if pending.pendingSideJoined {
            state.windows[mine].replacedWid = pending.partnerWid
            state.windows[theirs].replacedByWid = wid
            return pending.partnerWid
        }
        state.windows[mine].replacedByWid = pending.partnerWid
        state.windows[theirs].replacedWid = wid
        return nil
    }

    /// 1325/1326 carry (spaceId, wid) in the payload, so update just that window's spaceIds — no CGS
    /// re-query / full rescan. See the comments inline; this is `route`'s `.updateSpaceMembership` branch.
    private static func spaceMembershipChanged(_ state: inout TrackedWindowState, wid: CGWindowID, spaceId: UInt64,
                                               added: Bool, now: TimeInterval,
                                               inSpaceTransition: Bool) -> [ReducerEffect] {
        var effects = [ReducerEffect]()
        recordHandover(&state, wid: wid, spaceId: spaceId, added: added, now: now,
                       inSpaceTransition: inSpaceTransition)
        guard let window = state.window(wid) else {
            // Untracked wid → remember a removal so discovery can honor the empty Space (a rapid-burst
            // background tab whose remove fires before it's tracked, #5830); a later add cancels it. Then
            // the missed delta no longer strands the tab shown-as-separate until the next show.
            if !added {
                state.pendingSpaceRemoval[wid] = spaceId
            } else {
                state.pendingSpaceRemoval.removeValue(forKey: wid)
                // An UNtracked window joining the CURRENT Space is being brought forward. In fullscreen,
                // switching to a background tab re-discovers it (fullscreen background tabs drop out of
                // tracking) — and since it arrives via a Space-add, not a create, it isn't fronted and
                // landed at the BACK of the MRU (the switched-to tile appearing "on the right", then
                // jumping left once a focus pass re-sorted it). Flag it so discovery fronts it the
                // moment it's added, like a focus would. It is also the REPLACEMENT SIGNAL for a
                // Finder-style tab switch (a brand-new wid, no create event) — the outgoing tab's 1326
                // lands a beat later and must be held through the discovery gap (rec24).
                state.carried.untrackedJoinedSpace[wid] = spaceId
                state.carried.lastUntrackedSpaceJoinWid = wid
                state.carried.lastUntrackedSpaceJoinAt = now
                armInheritanceAfterJoin(&state, joiner: wid)
                if state.visibleSpaces.contains(spaceId) {
                    state.pendingFocusPromotion[wid] = .asserted
                    state.carried.lastUntrackedVisibleSpaceJoinAt = now
                    state.carried.lastUntrackedVisibleSpaceJoinWid = wid
                    // Discover it NOW, not at the next summon's full scan. A fullscreen tab switch to a
                    // REUSED background wid emits ONLY this Space-join — no create (811), no focus (808) —
                    // so nothing else schedules its discovery, and until it's tracked the group keeps
                    // showing the HELD outgoing tab: the switcher shows the PREVIOUS tab on open and only
                    // catches up when the next scan lands, seconds later (the "switched to Movies, opened
                    // the switcher, it showed the old tab" report — the tab had joined 5s earlier but stayed
                    // undiscovered). This is the 1325 analogue of the 808 path above, which already
                    // discovers an untracked focused wid. A join onto a VISIBLE Space means the window is on
                    // the current Space, reachable by the current-Space acquisition. Idempotent (discovery
                    // no-ops if already tracked); skipped mid Space-transition, where joins are animation
                    // noise, not a switch.
                    if !inSpaceTransition {
                        effects.append(.discoverWindow(wid: wid, throttled: false))
                    }
                }
            }
            if !added {
                // An UNTRACKED window leaving its Space was superseded before discovery ever reached it —
                // a burst of tabs outruns discovery, so each Cmd-T's window is created, added, and removed
                // within ~300ms while we never see it. Its creation flag must die with it. Nothing else
                // drains it: discovery never appends it, focus never lands on it, and 804 "lags a real
                // close by seconds — or never fires — for apps that retain the CGWindow (Finder)". So every
                // burst leaked a wid into `recentlyCreated` FOREVER, `discoveryPending` was then permanently
                // true, and every hold-visible ran to its 20s safety cap instead of releasing (rec13).
                // ...but ONLY if it was superseded, not if it merely MOVED. A window going fullscreen joins
                // its new Space and then leaves the old one, so the leave arrives for a Space it is no longer
                // on — draining there killed the promotion of a brand-new fullscreen tab (it never got
                // fronted) and the group it was due to inherit. Compare against the Space it last joined.
                let movedElsewhere = state.carried.untrackedJoinedSpace[wid].map { $0 != spaceId } ?? false
                guard !movedElsewhere else {
                    effects.append(.log("removed untracked#\(wid) space=\(spaceId) (moved, kept pending)"))
                    return effects
                }
                state.carried.untrackedJoinedSpace.removeValue(forKey: wid)
                state.recentlyCreated.remove(wid)
                // ...and the handover edge it was holding: it names a wid that never became a window.
                state.carried.pendingHandoverEdge.removeValue(forKey: wid)
                // Same staleness for `pendingFocusPromotion`: a tab that joined the visible Space untracked
                // (a switch/fullscreen re-front) armed its promotion, but if it BACKGROUNDS before discovery
                // ever adopts it (superseded by the next switch or an opened tab), that promotion is now
                // STALE — the wid is no longer the active tab. Left armed, it fires when the wid is later
                // adopted as a BACKGROUND tab, wrongly fronting it and making it the group's representative
                // over the real active (found by the generative simulator: newWindow → openTab → switchTab →
                // openTab → show hid the active behind the superseded tab). Drain it here, with the creation
                // flag — the promotion only survives to a genuine discovery-while-still-active.
                state.pendingFocusPromotion.removeValue(forKey: wid)
                // The MEMBERSHIP this wid was going to claim is different: it must be HANDED ON, not dropped,
                // when the wid was SUPERSEDED by another brand-new one rather than simply abandoned. Finder
                // mints a wid per switch, so a quick second switch (or a new tab) supersedes the first mint
                // before discovery reaches it, and the group that mint was carrying died with it: the whole
                // pre-swap generation was left as its OWN group, one real window became TWO, and the orphan's
                // representative stood as a permanent SECOND TILE — held, therefore exempt from the phantom
                // rule, so only the 20s safety cap ended it live (generator seeds 106/125).
                // Do NOT reach for the two obvious alternatives. Releasing the HOLD instead gives a vanish, or
                // a wholly phantom window, and cannot work: while the generation is split off as its own
                // group, nothing tells "a redundant orphan" from "this window's only group". Keeping the
                // generation in ONE group is what makes the stale wids derive `isTabbed` and hide by
                // themselves, with no phantom-rule exception at all. Dropping the membership without handing
                // it on is what SPLITS the generation in the first place.
                // The successor is whichever replacement signal just fired — a minted wid announcing itself on
                // the same Space (a switch), or a WS create (a new tab) — most recent first. `wid` rides along
                // so it is folded in once discovered. The pairing is by TIME, so it can cross wires between
                // apps; that is caught at consumption, where the pid is finally known.
                // With NO successor the wid was not superseded at all and the membership simply STAYS with it:
                // the commonest way to arrive here is a Space TRANSITION, where the active tab drops its Space
                // for the length of the animation and rejoins when it settles (the app cannot know a transition
                // has begun, so nothing distinguishes that leave at event time). Draining there stranded the
                // window's whole group while its own active was still in flight — one real window, two tiles
                // (seed 106's reachable repro: fullscreen, open another window, then switch back).
                if let carried = state.carried.pendingGroupInheritance[wid] {
                    let joiner = state.carried.lastUntrackedSpaceJoinWid.flatMap {
                        $0 != wid && now - state.carried.lastUntrackedSpaceJoinAt < recentPairingWindow
                            && state.carried.untrackedJoinedSpace[$0] == spaceId && state.window($0) == nil
                            ? ($0, state.carried.lastUntrackedSpaceJoinAt) : nil
                    }
                    let created = state.carried.lastWindowCreatedWid.flatMap {
                        $0 != wid && now - state.carried.lastWindowCreatedAt < recentPairingWindow && state.window($0) == nil
                            ? ($0, state.carried.lastWindowCreatedAt) : nil
                    }
                    if let successor = [joiner, created].compactMap({ $0 }).max(by: { $0.1 < $1.1 })?.0 {
                        state.carried.pendingGroupInheritance.removeValue(forKey: wid)
                        state.carried.pendingGroupInheritance[successor] = carried + [wid]
                        effects.append(.log("inheritance #\(wid) → #\(successor) members=\(carried)"))
                    }
                }
            }
            effects.append(.log("\(added ? "added" : "removed") untracked#\(wid) space=\(spaceId)"))
            return effects
        }
        let isTabbedBefore = state.isTabbed(window)
        effects.append(.log("\(added ? "added" : "removed") tracked#\(wid) space=\(spaceId) isTabbed=\(isTabbedBefore) sp\(window.spaceIds)"))
        // Remember WHICH Space it just left (and forget it once it joins one again). This is the only fact
        // that later distinguishes "a tab that backgrounded inside the window on Space A" from "a brand-new
        // tab of the window on Space B" — by then both are simply Space-less, same app, same size, unlinked,
        // and geometry handed the first to the second (generator seed 6). Kept on the window rather than in a
        // pending set because it must survive until the tab is claimed, which can be many events later.
        if let i = state.windowIndex(wid) {
            state.windows[i].lastLeftSpaceId = added ? nil : spaceId
        }
        // Hold a backgrounding tab visible through the new-tab discovery gap (the kernel decides; see
        // `shouldHoldVisibleThroughDiscovery`). The derived `isPhantom` keeps a held wid non-phantom, so
        // it shows its last thumbnail until the incoming tab's claim folds it in — a clean one-tile swap.
        if !added,
           TabGroupResolver.shouldHoldVisibleThroughDiscovery(
               isTabbed: isTabbedBefore,
               becomesSpaceless: window.spaceIds.filter({ $0 != spaceId }).isEmpty,
               hadRecentWindowCreate: now - state.carried.lastWindowCreatedAt < recentPairingWindow,
               hadRecentUntrackedSpaceJoin: now - state.carried.lastUntrackedVisibleSpaceJoinAt < recentPairingWindow) {
            effects.append(.log("hold-visible #\(wid) space=\(spaceId) (recent create)"))
            state.held.insert(wid)
            // If an untracked wid announced itself an instant ago, THIS is the tab it replaced: record the
            // membership for it to inherit at discovery. Without it a minted switch loses the group entirely
            // — the new tab shares no size cluster with the frozen siblings it should join, and fullscreen
            // exposes no AXTabGroup to re-read — so the window ended up showing two tiles, one for the new
            // active and one for the orphaned old group (generator seeds 7/11/15).
            // ...and only when the joiner arrived on the SAME Space this one is leaving. The pairing is by
            // time, so without that it crosses wires: under a different read ordering a tab joining one
            // window's fullscreen Space was matched with an unrelated window's representative leaving the
            // windowed Space, and the two windows were merged into one group (generator seed 30).
            //
            // **THIS IS THE FULLSCREEN ARM.** `discoveryLanded` arms the same `pendingGroupInheritance` from
            // the handover EDGE, which is strictly better evidence (it names a wid rather than pairing on
            // time, it is recorded from either arrival order, and its pid is confirmed at consumption) — so
            // this looks redundant and is not. The edge arm is WINDOWED-only, because in fullscreen forming a
            // partial group from it PRE-EMPTS the per-Space geometry fold that owns fullscreen grouping
            // (seed 77). Measured, both directions: dropping the edge's fullscreen exclusion breaks seed 31;
            // deleting THIS block breaks `testMintedTabSwitchInheritsTheGroupItTookOver` and both
            // `testSupersededMintedTab…` scenarios, every one of them a fullscreen one. So the two arms
            // partition the problem by regime — fullscreen here, windowed there — and neither subsumes the
            // other. Do not "consolidate" them without re-running that pair of experiments.
            if let joiner = exactUntrackedSuccessor(of: wid, in: state) {
                let members = state.groups.siblingWids(of: wid) ?? [wid]
                state.carried.pendingGroupInheritance[joiner] = members
            } else if now - state.carried.lastUntrackedVisibleSpaceJoinAt < recentPairingWindow,
               let joiner = state.carried.lastUntrackedVisibleSpaceJoinWid, joiner != wid,
               state.carried.untrackedJoinedSpace[joiner] == spaceId,
               state.window(joiner) == nil {
                let members = state.groups.siblingWids(of: wid) ?? [wid]
                state.carried.pendingGroupInheritance[joiner] = members
            }
            // Release is event-driven, NOT a fixed delay (the OS's discovery latency is unbounded — a busy
            // machine can take seconds to size the new window). See `.holdReleaseCheck`.
            effects.append(.scheduleHoldReleaseCheck(wid: wid, attempt: 0))
        }
        // The Space swap is the physical fallback for selecting a tab representative (1325 for the tab
        // coming on-screen, 1326 for the one leaving). The app-level AX observer normally names the same tab,
        // but it may be delayed or absent while the WindowServer state is already visible. Repair the group's
        // representative here when an inactive tab joins the front app's Space; an eventual AX answer is
        // idempotent.
        // Read `isTabbed` BEFORE reconcile flips it, and bump OUTSIDE the delta guard: the tab machinery
        // backfills a background tab's spaceIds from its active sibling, so the 1325 add is usually a
        // no-op delta (`applySpaceMembershipDelta` returns false).
        // `isTabbed` is not the only way to be a background tab: a tab we ADOPTED but never managed to GROUP
        // is one too. Two Finder tabs of one window share a title and keep a stale frame while backgrounded,
        // so the AX-title match names nothing and geometry sees different positions — the tab sits tracked,
        // Space-less and ordered-out, linked to no one. Switching to it then failed this gate, no bump was
        // written, and the group (formed a beat later, once the tab was on-screen and readable) re-elected
        // the tab the user had just LEFT as the one it draws. Space-less and not ordered-in is what
        // "background tab" means physically, so take that as the second arm.
        let wasOffScreenTab = !window.isOrderedIn && window.spaceIds.isEmpty && state.visibleSpaces.contains(spaceId)
        let inactiveTabBecameActive = added && (isTabbedBefore || wasOffScreenTab)
            && (state.apps[window.pid]?.isActive ?? false)
        let delta = state.applySpaceMembershipDelta(wid, spaceId: spaceId, added: added)
        if delta.changed {
            effects.append(.updateScreenId(wid))
            if delta.unphantomedRealWindow { effects.append(.removeWindowlessPlaceholder(pid: window.pid)) }
            // switching a fullscreen window's tabs swaps which one holds the Space — regroup so the
            // newly-backgrounded tab stays shown instead of being flagged phantom
            effects.append(contentsOf: reconcile(&state))
            effects.append(.refreshUi(wids: [wid], onlyWhileSwitcherOpen: true))
        }
        // A window that just went Space-less is a freshly-backgrounded tab: re-read its on-screen same-app
        // sibling's AXTabGroup NOW so that sibling claims it as an inactive tab, instead of leaving it
        // shown as a separate 2nd tile until the next switcher show (creation-race flash / stuck tile).
        if !added, state.window(wid)?.spaceIds.isEmpty == true, !inSpaceTransition {
            effects.append(contentsOf: reconcileTabsForAppEffects(state, pid: window.pid))
        }
        // Don't try to reap the accumulated wids by AX-liveness here: the premise is wrong (rec25). Finder
        // mints a new wid per fullscreen tab switch and the old minted wids accumulate in the group, but
        // they are NOT dead — their AX elements stay ALIVE and reachable,
        // which is exactly how `discoverInactiveTabs` ADOPTS inactive tabs (rec25 log: the same wids that
        // pile up are then `discovered ... adoptedTab`). An AX-liveness probe answers "alive" and reaps
        // nothing, while adding an off-main AX call on every tab backgrounding for no benefit. The real
        // fullscreen accumulation is harder: no readable AXTabGroup (fullscreen), and the stale minted wids
        // are alive + same-size + same-fullscreen-Space, indistinguishable from current background tabs by
        // geometry alone. This is the churn class the TestScenarioSimulator must model (a faithful Finder wid
        // lifecycle + async interleaving) before it can be fixed against a test rather than reactively.
        if inactiveTabBecameActive {
            // Joining a Space puts the window ON-SCREEN: it is now its group's ACTIVE tab (a tab switch —
            // the common case) or it was dragged out to stand alone. A switch is a REPRESENTATIVE move,
            // nothing more: membership is unchanged, so mutate exactly that — one atomic swap, the old
            // rep derives tabbed and hides, the incoming shows. (It used to leave the group and wait
            // ~800ms for an AX read to re-derive membership, and that churn oscillated the open switcher
            // through several layouts per switch, rec19.) A drag-out is indistinguishable at event time —
            // the dragged tab starts at the parent's frame — so it is confirmed asynchronously by frame
            // divergence (`.dragOutCheck`) and taken out of the group then.
            let previousRepWid = state.groups.groupId(of: wid)
                .flatMap { state.groups.representativeByGroup[$0] }
            effects.append(contentsOf: state.setGroupRepresentative(wid, reason: "joinedSpace").logs.map { .log($0) })
            // Hand the incoming tab what it needs to be DRAWN as the group's tile — above all the outgoing
            // tab's pixels, until its own capture lands. The swap is atomic and immediate, but this borrow
            // used to happen only inside `reconcile`, which this path does not always reach: the tile
            // therefore fell back to the app ICON for a beat (`TileView` draws it whenever `thumbnail ==
            // nil`), which is the "screenshot → app icon → screenshot" flicker in its reused-wid form.
            if let gid = state.groups.groupId(of: wid), let members = state.groups.membersByGroup[gid] {
                showAsGroupRepresentative(&state, repWid: wid, memberWids: members, into: &effects)
            }
            if let previousRepWid, previousRepWid != wid {
                // Refresh both frames from the WindowServer before the first verdict: a background tab
                // gets no geometry events, so the joiner's stored position is stale for a beat after a
                // switch (~215ms, rec13) and a stale frame reads as a drag-out
                // (`testDragOutVerdictUndecidedWhileTheIncomingFrameIsStale`).
                effects.append(.queryWindowServerState(wids: [wid, previousRepWid], throttled: false))
                effects.append(.scheduleDragOutCheck(wid: wid, previousRepWid: previousRepWid, attempt: 0))
            }
            effects.append(contentsOf: applyFocusAndBump(&state, wid: wid, at: now, .structuralRepair))
            // Converge the former group's membership: on a tab SWITCH the new active re-matches its
            // siblings; on a drag-out the former active's `toUntabWids` clears the now-standalone window's
            // stale link (the cleanup the removed nil-titles dissolution used to do).
            effects.append(contentsOf: reconcileTabsForAppEffects(state, pid: window.pid))
        }
        return effects
    }

    private static func exactUntrackedSuccessor(of wid: CGWindowID, in state: TrackedWindowState) -> CGWindowID? {
        state.carried.pendingHandoverEdge.first { joiner, edge in
            edge.pendingSideJoined && edge.partnerWid == wid && state.window(joiner) == nil
        }?.key
    }

    /// The leave-first half of a tab handover. The outgoing representative is already held when the
    /// untracked successor joins, and the exact handover edge names the group it must inherit. The
    /// join-first half is armed in the tracked leave branch above. The hold is the freshness gate; unlike a
    /// fullscreen flag it is present on both sides of the transition and is not mirrored between tabs.
    private static func armInheritanceAfterJoin(_ state: inout TrackedWindowState, joiner: CGWindowID) {
        guard let edge = state.carried.pendingHandoverEdge[joiner], edge.pendingSideJoined,
              state.held.contains(edge.partnerWid) else { return }
        state.carried.pendingGroupInheritance[joiner] = state.groups.siblingWids(of: edge.partnerWid) ?? [edge.partnerWid]
    }

    /// Re-read the AXTabGroup of an app's ON-SCREEN (non-tabbed, Space-holding) windows right when a
    /// Space-membership event signals a tab change, so the tab state reconciles NOW instead of waiting for
    /// the next switcher show (was `Applications.reconcileTabsForAppOnSpaceEvent` — see its comment there
    /// for the two callers and why converging BETWEEN shows is load-bearing).
    /// FULLSCREEN windows are skipped: AX exposes no AXTabGroup for them, so the read yields no titles and
    /// the update no-ops — pure IPC for nothing, in exactly the case that generates the most Space events.
    /// Their grouping is geometry's job, which needs no AX at all.
    static func reconcileTabsForAppEffects(_ state: TrackedWindowState, pid: pid_t) -> [ReducerEffect] {
        state.windows.filter { w in
            w.pid == pid && !state.isTabbed(w) && !w.spaceIds.isEmpty && !w.isWindowlessApp
                && !w.isFullscreen && w.wid != nil
        }.map { .readTitleAndTabs(wid: $0.wid!, readTabs: true) }
    }

    /// The Space-switch reaction's CHEAP half, on the leading edge of the 1329/1401 burst: re-read the Space
    /// topology and re-render an open switcher. It exists because everything below waits for the burst to
    /// settle, and a summon lands inside that wait routinely — a Space switch and the Cmd+Tab that follows it
    /// are one gesture (#5864: 50ms apart in the reporter's capture, against a 250ms debounce), so the
    /// switcher filtered and sorted against the Space the user had just LEFT and visibly re-ordered under
    /// them a beat later. v11.3.1 had no such gap: it reacted on the leading edge of NSWorkspace's
    /// `activeSpaceDidChange`. The split is what the debounce is FOR — the per-window Space membership and
    /// the WS state re-query below are expensive and would be re-run by every event of the burst, while the
    /// topology is one CGS round-trip (0.1ms p50, measured) and is the only part a summon needs.
    private static func spaceTransitionStarted(_ state: inout TrackedWindowState) -> [ReducerEffect] {
        // Deliberately NO `.refreshUi`. Repainting here looks free and is not: `refreshOpenUiAfterExternalEvent`
        // is throttled at 200ms with a leading edge, so a repaint fired the instant the Space flips SPENDS that
        // edge, and the update that actually matters — the semantic focus answer following the Space change
        // — then waits out the tail. Live capture, switcher open
        // across the transition: repainting here pushed the MRU correction from ~15ms to 220ms after the
        // summon. The topology write below is what the leading edge is for; the repaint it feeds is the
        // settled pass's job, 250ms later, exactly as before.
        [.refreshSpacesTopology]
    }

    /// The Space-switch reaction, once the 1329/1401 burst settles (was `handleSpaceChanged`): refresh the
    /// Space topology + per-window membership (cached for the switcher's hot path, #5721), re-read
    /// fullscreen for the current Space (the Safari full-screen-video window emits no resize/move event),
    /// re-check shortcut disabling for the focused window, and reconcile any open switcher.
    private static func spaceChangeSettled(_ state: inout TrackedWindowState) -> [ReducerEffect] {
        let trackedWids = state.windows.filter { !$0.isWindowlessApp }.compactMap { $0.wid }
        return [.refreshSpacesTopologyAndSync,
                .queryWindowServerState(wids: trackedWids, throttled: false),
                .checkShortcutsForFocusedWindow,
                .refreshUi(wids: state.windows.compactMap { $0.wid }, onlyWhileSwitcherOpen: false)]
    }

    /// An app became frontmost (NSWorkspace — no WS equivalent). It names an app and nothing else: the 808s
    /// macOS emits alongside it fire once per on-Space window, which is a set rather than an answer, so which
    /// window the user landed on can only come from the app. `AttentionModel` reuses that app's last answer,
    /// or requests one bounded `kAXFocusedWindow` read when it has no answer yet.
    private static func appActivated(_ state: inout TrackedWindowState, pid: pid_t) -> [ReducerEffect] {
        state.frontmostPid = pid
        return []
    }

    // MARK: - async read results landing

    /// The apply-side of `Applications.addDiscoveredWindow`, after the shell acquired/discriminated the
    /// window and applied its raw AX/WS attributes. Decisions owned here: the pending-removal consume, the
    /// MRU promotion (was `Windows.appendWindow`'s), the Space override for background tabs, the tab-state
    /// update with the newly-CREATED gate, the reconcile, the adopted-tab convergence, the re-render.
    private static func discoveryLanded(_ state: inout TrackedWindowState, wid: CGWindowID, accepted: Bool,
                                        newlyTracked: Bool, adoptedAsInactiveTab: Bool,
                                        spaceMembership: SpaceMembershipObservation, isOrderedIn: Bool,
                                        tabGroup: TabGroupObservation) -> [ReducerEffect] {
        let queriedSpaceIds = spaceMembership.spaceIds
        let tabTitles = tabGroup.titles
        let tabGroupToken = tabGroup.token
        // A not-yet-admitted wid the OS has just CREATED is not a dead wid. A custom AXWindow root can be
        // published without enough geometry or semantics to admit it, then become admissible on its first
        // move/resize. Everything below CONSUMES this wid's pending state, so a latent landing must not spend
        // it on a discovery that never happened.
        //
        // It is the handover edge that pays. Live #5785 capture, opening the first tab in a Terminal window:
        // `windowCreated #4131` → the 1325/1326 pair records the edge naming the tab it replaced (#4125) →
        // a latent landing eats it 8ms later → the real landing 211ms after that inherits nothing. The new tab
        // then forms no group, and neither of the other two paths can fill in: the tab bar grows the window
        // (1017×610 against the outgoing tab's 1017×565) so geometry has no cluster, and Terminal composes
        // tab titles unlike window titles so `matchSiblings` names nobody. Two tiles for one window, until
        // the hold hit its 20s cap. Nothing else drains on this path (destroy, and the untracked-Space leave
        // that marks a supersede, both still do), so deferring to the real landing loses no anti-leak cover.
        guard accepted || !state.recentlyCreated.contains(wid) else { return [] }
        // Consume the pending-removal marker up-front, so a surface rejected by admission can't
        // leave it dangling — the set stays self-draining. `pendingSpaceRemoval` remembers a
        // removed-from-Space event that arrived while the window was still untracked (a rapid-burst
        // background tab, #5830).
        // Consuming it also decides whether it still MEANS anything: if the window has since been placed on
        // a DIFFERENT Space than the one it left, it didn't background — it moved (fullscreen). Only a
        // removal the query agrees with (nothing, or the same Space it left, which the per-window CGS query
        // reports stale right after backgrounding) says "background tab".
        state.carried.untrackedJoinedSpace.removeValue(forKey: wid)
        let removedFromSpaceWhileUntracked = state.pendingSpaceRemoval.removeValue(forKey: wid)
        let wasRemovedFromSpaceWhileUntracked = removedFromSpaceWhileUntracked.map { left in
            guard let queriedSpaceIds else { return false }
            return queriedSpaceIds.isEmpty || queriedSpaceIds == [left]
        } ?? false
        // ...and the same self-draining logic for the two maps the HANDOVER fills. A wid admission currently
        // rejects is not becoming a destination, and `accepted: false` is the only moment we learn that for
        // certain: the other drains all hang off events that may never come. Finder's 804 "lags a real close
        // by seconds — or never fires" for apps that retain the CGWindow, and a wid that joined a NON-visible
        // Space is never even scheduled for discovery, so without this the entries wait forever. That is the
        // rec13 leak shape, which is why `pendingSpaceRemoval` above is already drained on this exact path.
        //
        // It is more than tidiness for `pendingHandoverEdge`, because consumption is NOT time-bounded:
        // `applyPendingHandoverEdge` pairs within `recentPairingWindow` but applies whenever its wid is
        // finally discovered, so a leaked entry could later dress a window in a stale `replacedWid` — which
        // `dragOutVerdict` reads as a settled verdict ("replaced someone ⇒ a switch; stop checking").
        if !accepted {
            state.carried.pendingHandoverEdge.removeValue(forKey: wid)
            state.carried.pendingGroupInheritance.removeValue(forKey: wid)
        }
        guard accepted, let window = state.window(wid) else { return [] }
        recordTabObservation(&state, wid: wid, observation: tabGroup)
        var effects = [ReducerEffect]()
        // "Newly TRACKED" (`newlyTracked`) is not "newly CREATED": at launch every window is newly tracked.
        // Only a WindowServer create event means the user just made this window. Read BEFORE the promotion
        // below consumes the flag.
        let wasJustCreated = state.recentlyCreated.contains(wid)
        /// The wid this window replaced, if its handover edge was applied on THIS arrival (see
        /// `applyPendingHandoverEdge`). Fresh by construction, unlike the stored `replacedWid`.
        var replacedOnArrival: CGWindowID?
        var justCreated = false
        if newlyTracked {
            // Apply the promotion this window earned while it was still UNTRACKED, whichever path recorded
            // it (`pendingFocusPromotion`: a visible-Space join, or an in-app raise that outran the async
            // discovery). Consumed here, so it happens exactly once.
            //
            // A CIRCUMSTANTIAL promotion is applied at the time the signal happened, not now: discovery is
            // async, so the user may already have focused something else in between, and fronting the window
            // then would steal a front they have left (the switcher would offer the window they are already
            // in). `noteFocus` slots it behind anything focused since. It must also prove the window belongs
            // to the app that was frontmost when it appeared.
            //
            // **A minted tab arriving is a group repair, not the user going anywhere.** A tab SWITCH in a
            // fullscreen group mints a brand-new wid with no create event and no focus event, so the only
            // way the group's representative can follow the user's switch is for the promotion recorded at
            // the Space-join to be applied here, when the wid finally becomes a window. It is a structural
            // repair by definition: membership already changed, and this only settles which member is drawn.
            //
            // A window merely being BORN is not promoted, which is the deliberate half (twenty background
            // windows at once; a launch finishing after the user had moved on). The app's own
            // focused-window notification names a new window when it really did take keys, and that is a
            // namer; nothing here has to guess. The price is known and was accepted: a window that never took
            // keys has no attention record, so it sorts behind every window the user has ever focused.
            justCreated = state.recentlyCreated.contains(wid)
            // A handover edge recorded while this wid was still untracked — the minted half of a tab switch —
            // can only be applied now, and the pid it was missing is finally readable. BEFORE the promotion
            // below, which asks whether this window took another's place.
            replacedOnArrival = applyPendingHandoverEdge(&state, wid: wid)
            // Did this window arrive in another's place? Either arm of the tab handover says so: the edge
            // (windowed) names the wid it replaced, and `pendingGroupInheritance` (fullscreen) carries the
            // membership it is about to inherit. Both are armed only by a tab taking over.
            let tookAnothersPlace = replacedOnArrival != nil || state.carried.pendingGroupInheritance[wid] != nil
            let promotedTab: TimeInterval? = {
                switch state.pendingFocusPromotion.removeValue(forKey: wid) {
                // The assertion is armed by a join of the visible Space. For a REUSED wid, arriving with no
                // create event, that can only be saying "the user switched to me". A window being BORN joins
                // that same Space though, so every birth was fronted too, whatever the user was doing (twenty
                // background windows at once; a launch finishing after the user had moved to Finder).
                // So a created wid keeps the promotion only when it took another window's place, which is
                // what a new tab does and what a new window does not. A created tab that forms its group
                // later is bumped by the `justCreated` branch below instead.
                case .asserted: return justCreated && !tookAnothersPlace ? nil : state.now
                case let .circumstantial(at, frontmostPid): return frontmostPid == window.pid ? at : nil
                case nil: return nil
                }
            }()
            state.recentlyCreated.remove(wid)
            if let at = promotedTab {
                effects.append(contentsOf: applyFocusAndBump(&state, wid: wid, at: at, .structuralRepair))
                // The minted tab inherits the outgoing one's pixels, or the tile draws the app icon until its
                // own capture lands (`checkNoIconFlash`).
                if let gid = state.groups.groupId(of: wid), let members = state.groups.membersByGroup[gid] {
                    showAsGroupRepresentative(&state, repWid: wid, memberWids: members, into: &effects)
                }
            }
            // Seed the ordered-in bit from the same WindowServer row this discovery was discriminated on.
            // Without it the bit is false for every window that was already open when AltTab launched — no
            // order event ever fires for those — so tab-grouping's "an on-screen window is nobody's
            // background tab" rule would be unarmed exactly at cold start, which is when a whole desktop of
            // same-frame windows is discovered at once. Forced false for a tab we already know is in the
            // background, like its Space below.
            if let i = state.windowIndex(wid) {
                state.windows[i].isOrderedIn = isOrderedIn && !adoptedAsInactiveTab
                state.windows[i].spaceMembershipObservation = spaceMembership
            }
            // Override Window.init's current-Space default with the real Space resolved off-main (new
            // windows only; existing ones stay live via events / spacesSynced).
            if wasRemovedFromSpaceWhileUntracked || adoptedAsInactiveTab {
                // A background tab. Force it Space-less: the per-window CGS query still reports its OLD
                // Space (stale right after backgrounding, and for a long-backgrounded tab adopted by
                // brute-force), so trusting it would keep the tab looking like a separate on-screen window;
                // the empty is what lets it be claimed/grouped (#5830, rec15's cold-start ghost flood).
                let r = state.applyWindowSpaces(wid, spaceIds: [])
                effects.append(.updateScreenId(wid))
                if r.unphantomedRealWindow { effects.append(.removeWindowlessPlaceholder(pid: window.pid)) }
            } else if let queriedSpaceIds, !queriedSpaceIds.isEmpty || !isOrderedIn {
                let r = state.applyWindowSpaces(wid, spaceIds: queriedSpaceIds)
                effects.append(.updateScreenId(wid))
                if r.unphantomedRealWindow { effects.append(.removeWindowlessPlaceholder(pid: window.pid)) }
            }
        }
        var tabStateChanged = false
        if tabTitles != nil || state.groups.siblingWids(of: wid) != nil {
            // A window the user JUST CREATED which carries an AXTabGroup is a new tab that took over its
            // group, so `matchSiblings` may claim the previous active tab even before its "removed from
            // Space" event lands — grouping the pair atomically so the old tab never flashes as a 2nd tile.
            // It must be newly CREATED, not merely newly tracked (the "void" trap — see above).
            let r = updateTabState(&state, activeWid: wid, siblingTitles: tabTitles, tabGroupToken: tabGroupToken,
                activeIsNewlyDiscovered: newlyTracked && wasJustCreated)
            effects.append(contentsOf: r.effects)
            tabStateChanged = r.changed
        }
        // a newly-discovered tab (e.g. switching to a fullscreen window's other tab) joins its fullscreen
        // sibling's group here, so it's grouped before the next show rather than during it. Pass the wid:
        // in fullscreen AX can't name the tabs, and a brand-new tab is often momentarily Space-less —
        // indistinguishable from a background tab by facts alone — so this is what tells geometry which
        // member just took over (else it picked the OLD tab and the switcher showed the previous one).
        // EXCEPT an adopted INACTIVE tab: `newlyDiscovered` means "the brand-new ACTIVE tab that just took
        // over", and an adopted inactive tab is the opposite — a known BACKGROUND tab back-filled into
        // tracking. Passing it made geometry elect the Space-less adopted tab as the group's visible and
        // backfill its empty Space onto every real member, wiping the genuine fullscreen active's Space →
        // the whole group went phantom → zero tiles until the next CGS read (rec24e: switching to a
        // fullscreen tab, the group's tile vanished for ~1s).
        // A minted tab switch: this wid announced itself on the visible Space as the outgoing representative
        // left, so it inherits that group and becomes its representative — one atomic handover, exactly what
        // a REUSED wid gets for free via `setGroupRepresentative(reason: "joinedSpace")`. Mints used to lose
        // the group instead, for no principled reason. The `.dragOutCheck` already scheduled by the pairing
        // is the escape hatch if the frames later say the tab was torn out into its own window.
        // **THE WINDOWED ARM** of `pendingGroupInheritance`; the other is in `spaceMembershipChanged`'s hold
        // branch, which owns FULLSCREEN. Read that one's comment for why the split is real and measured; the
        // short version is that the two are not alternatives, they partition by regime, and the fullscreen
        // gate at the bottom of this condition is what draws the line.
        //
        // The handover edge says this window took another's place on the Space, pid-confirmed and recorded
        // from EITHER arrival order (`applyPendingHandoverEdge` above filled it in if the join raced ahead of
        // the leave). The hold-branch arm expresses the same handover but is armed only in the LEAVE branch,
        // off "an untracked wid joined a moment ago" — so when the leave lands FIRST there is no joiner to
        // pair with yet, nothing arms, and the incoming tab forms no group. That is the residual #5785
        // symptom: opening the first tab in a standalone window showed two tiles, one for the new tab and one
        // for the tab it replaced, because the pair could only be linked in one of the two orders. The edge
        // makes the handover order irrelevant, which is what the `HandoverOrder` fuzz axis keeps honest.
        // Gated on the replaced window still being HELD, i.e. the handover is genuinely in flight. The edge
        // itself lives on until the window joins a Space again, and `applyPendingHandoverEdge` consumes a
        // PENDING edge whenever its wid is finally discovered, which can be arbitrarily later than the
        // pairing that recorded it — so "paired within `recentPairingWindow`" does not make the edge fresh
        // AT CONSUMPTION. Inheriting from a stale one is destructive rather than merely useless, because
        // `formGroup` is exact-set: generator seed 77 rebuilt a fullscreen group around a late arrival and
        // EJECTED the tab that was actually active, leaving the window showing two tiles. The hold is armed
        // by the same handover and released when it completes, so it dates the edge. Verified to bite: with
        // the test inverted, `testFirstTabInAStandaloneWindowIsOneTileDespiteTheTabBarResize` and the
        // generated-scenario sweep both fail, so the sanctioned case is always held and only a stale edge
        // is refused.
        // WINDOWED only, and this is the line between the two arms. In fullscreen the Space invariant already
        // owns grouping — one Space holds one window and its tabs, which `geometryGroups` folds without
        // needing any of this — and forming a partial group here from the handover instead PRE-EMPTS that
        // fold: generator seed 77 made the minted tab the representative of the frozen siblings, and the
        // genuinely-active tab, not yet a member, could no longer be absorbed into a group it did not belong
        // to, so the window showed two tiles. Re-measured when the two arms were considered for merging:
        // drop this gate and generator seed 31 breaks under `.inOrder / .swapped / .prompt`. The fullscreen
        // minted switch is served by the hold-branch arm, which is narrower (same Space, joiner still
        // untracked, hold in flight) and does not pre-empt the fold.
        if newlyTracked, state.carried.pendingGroupInheritance[wid] == nil,
           let replaced = replacedOnArrival, state.held.contains(replaced),
           let replacedWindow = state.window(replaced),
           !state.tabWindow(replacedWindow).isFullscreen,
           !(state.window(wid).map { state.tabWindow($0).isFullscreen } ?? true) {
            state.carried.pendingGroupInheritance[wid] = state.groups.siblingWids(of: replaced) ?? [replaced]
        }
        if newlyTracked, let inherited = state.carried.pendingGroupInheritance.removeValue(forKey: wid) {
            // Same app only. Both ways this can be armed pair a replacement with a departure BY TIME, and
            // under a different read ordering that crossed wires once already — a tab joining one window's
            // fullscreen Space matched an unrelated window's representative leaving the windowed one, merging
            // two windows into a group (seed 30). The arming side can only compare Spaces; here the pid is
            // known, so this is where the pairing is actually confirmed.
            let members = inherited.filter { state.window($0).map { $0.pid == window.pid } ?? false }
            if !members.isEmpty {
                // **The handover claims a REPRESENTATIVE, not a membership**, and `formGroup` is exact-set, so
                // forming from the inherited set ALONE ejects whatever a better-informed signal already put in
                // the group. That set is what `replaced` had when it left, which is a floor, not the answer:
                // when the app's own AXTabGroup titles land in the same pass and group this wid with MORE of
                // its tabs, they are the stronger claim about who is in the group. Live QA C-10: a tab opened
                // while the cold scan was still running formed the right 4-tab group from `axTitles`, and the
                // handover split it back into [new, replaced] plus the two it evicted — one window, two tiles.
                // Union, so neither side can shrink the other. When the two agree, `form` takes its same-set
                // fast path and only moves the representative.
                let alreadyGrouped = state.groups.siblingWids(of: wid) ?? []
                let formed = state.formGroup([wid] + members + alreadyGrouped, representative: wid,
                    reason: "mintedTabSwitch")
                effects.append(contentsOf: formed.logs.map { .log($0) })
                // Refresh the frames, exactly as the TRACKED half of this handover does on `joinedSpace`.
                // This wid was discovered by the brute-force AX scan while it was still a background tab, so
                // the position it arrived with is the one it wore THERE — and the order-in that moved it onto
                // its parent's frame fired before we ever subscribed to its notifications, so no geometry
                // event will ever correct it. Live QA T-20 caught it: clicking a background window's tab
                // brought that window to the front, and the minted tab still sat at the other window's
                // cascade position, which is a frame every geometry rule below then reasons from.
                effects.append(.queryWindowServerState(wids: [wid] + members, throttled: false))
                // ...and give it the standing to KEEP that. A mint arrives with no focus history at all, and
                // `normalizeGroupVisibility` re-elects by recency on the very next pass — handing the group
                // straight back to a background tab that does have some, whose missing thumbnail then draws
                // as an app icon. Naming it representative without this is undone before anything is shown.
                // Structural: the window did not change, only which wid stands for it.
                effects.append(contentsOf: applyFocusAndBump(&state, wid: wid, at: state.now,
                    .structuralRepair))
                if let gid = state.groups.groupId(of: wid), let all = state.groups.membersByGroup[gid] {
                    showAsGroupRepresentative(&state, repWid: wid, memberWids: all, into: &effects)
                }
            }
        }
        // **A tab that was just CREATED takes over its group.** Which member a group draws is decided by
        // focus recency, and a brand-new tab has none, so without this the group keeps drawing the tab the
        // new one displaced — while the newcomer holds the Space, which the replay harness flags outright
        // ("holds a GENUINE Space yet is claimed as a tab"). This is a structural repair and not a claim
        // about the user: the group's active member changed, and this only records which one it is.
        //
        // BEFORE `reconcile`, which elects the representative: after it, the election has already run on the
        // old recency and the pass is no longer a fixed point.
        if newlyTracked, justCreated, !adoptedAsInactiveTab, let gid = state.groups.groupId(of: wid),
           state.window(wid)?.spaceIds.isEmpty == false {
            effects.append(contentsOf: applyFocusAndBump(&state, wid: wid, at: state.now, .structuralRepair))
            // Hand it the outgoing tab's pixels in the same pass, or the tile draws the app icon for a beat
            // while its own capture lands — the flash `checkNoIconFlash` exists to catch.
            if let members = state.groups.membersByGroup[gid] {
                showAsGroupRepresentative(&state, repWid: wid, memberWids: members, into: &effects)
            }
        }
        if newlyTracked {
            effects.append(contentsOf: reconcile(&state, newlyDiscovered: adoptedAsInactiveTab ? nil : wid))
        }
        // Converge the group NOW: the adopted tab is Space-less, so re-reading its app's on-screen actives
        // lets their AXTabGroup claim it immediately, instead of it sitting phantom-hidden until the next
        // show's review.
        if newlyTracked && adoptedAsInactiveTab {
            effects.append(contentsOf: reconcileTabsForAppEffects(state, pid: window.pid))
        }
        if newlyTracked {
            let w = state.window(wid)
            effects.append(.log("discovered new#\(wid) app=\(state.apps[window.pid]?.state.localizedName ?? "?") axTitles=\(tabTitles ?? []) isTabbed=\(w.map { state.isTabbed($0) } ?? false) siblings=\(state.groups.siblingWids(of: wid) ?? []) sp\(w?.spaceIds ?? []) pendingRemoval=\(wasRemovedFromSpaceWhileUntracked)\(adoptedAsInactiveTab ? " adoptedTab" : "")"))
        }
        if newlyTracked {
            effects.append(.refreshUi(wids: [wid], onlyWhileSwitcherOpen: false))
        } else if tabStateChanged {
            effects.append(.refreshUi(wids: [wid], onlyWhileSwitcherOpen: true))
        }
        return effects
    }

    /// The apply-side of `Applications.refreshWindowTitleAndTabs` (the shell already wrote title/main and
    /// reports whether they changed): the tab reconcile and the re-render decision. Minimized is NOT here —
    /// it comes from the WindowServer query, which cannot be blocked by the window's own app.
    private static func titleAndTabsRead(_ state: inout TrackedWindowState, wid: CGWindowID,
                                         tabGroup: TabGroupObservation, reconcileTabs: Bool,
                                         changedSoFar: Bool) -> [ReducerEffect] {
        guard state.window(wid) != nil else { return [] }
        var effects = [ReducerEffect]()
        var changed = changedSoFar
        // only when the caller actually read tabs — an order-out skips the kAXChildren read, so its nil says
        // nothing about the window's tab group
        var tabCountMoved = false
        if reconcileTabs { tabCountMoved = recordTabObservation(&state, wid: wid, observation: tabGroup) }
        let tabTitles = tabGroup.titles
        let tabGroupToken = tabGroup.token
        if reconcileTabs, tabTitles != nil || state.groups.siblingWids(of: wid) != nil {
            let r = updateTabState(&state, activeWid: wid, siblingTitles: tabTitles, tabGroupToken: tabGroupToken)
            effects.append(contentsOf: r.effects)
            // ...or the COUNT moved, even when nothing else did. The count is a fact only this read supplies
            // and only geometry consumes (`TabGroupResolver.tabCountAccountsForEveryMember`), and it lands
            // AFTER the events that last ran geometry: measured on a Merge All Windows (live
            // 2026-07-30), the tabs' three 1326s reconciled at 19:40:50.477 while `tabCount` was still 0, and
            // the read that set it to 4 landed at 19:40:50.488 — eleven milliseconds too late, with nothing
            // left to re-ask. `updateTabState` reports `changed: false` there (it matched nobody: same title,
            // four different positions), so the group never formed for as long as the window lived.
            if r.changed || tabCountMoved {
                changed = true
                // Membership moved, so the DERIVED per-member facts must be re-derived — above all the
                // fullscreen mirror, which is copied from each group's active tab. Without this the
                // discovery path reconciled after `updateTabState` and this one did not, so a tab that had
                // left a fullscreen group kept wearing that group's mirrored fullscreen flag until some
                // unrelated later pass happened to run. That is a state which is not a reconcile fixed
                // point, which is exactly what the convergence invariant is for (generator seed 30).
                effects.append(contentsOf: reconcile(&state))
            }
        }
        if changed { effects.append(.refreshUi(wids: [wid], onlyWhileSwitcherOpen: true)) }
        return effects
    }

    /// A batched WS state query landed (the apply-side of `Applications.updateWindowStatesViaWindowServer`):
    /// write the WindowServer-owned facts (geometry, GENUINE fullscreen — so the mirror marker clears, as in
    /// `Window.updateFromWindowServer`), then regroup — a window entering/leaving fullscreen forms or
    /// dissolves a fullscreen tab group. Re-capture only on-screen windows: a window that just ordered out
    /// can't be screenshotted (a capture grabs a torn-down/blank "skeleton"), so keep its last on-screen
    /// frame and just refresh the layout for the geometry change.
    private static func windowServerStateRead(_ state: inout TrackedWindowState, _ snapshots: [WsWindowSnapshot]) -> [ReducerEffect] {
        var changedAny = false
        var toCapture = [CGWindowID]()
        var focusRepairs = [ReducerEffect]()
        for snap in snapshots {
            guard let i = state.windowIndex(snap.wid) else { continue }
            var changed = state.windows[i].position != snap.position || state.windows[i].size != snap.size
                || state.windows[i].isFullscreen != snap.isFullscreen
                || (state.windows[i].isOrderedIn != snap.isVisible
                    && !(!snap.isVisible && snap.isMinimized && !state.carried.offScreen.contains(snap.wid)))
            state.windows[i].position = snap.position
            state.windows[i].size = snap.size
            state.windows[i].isFullscreen = snap.isFullscreen
            state.windows[i].isFullscreenMirrored = false
            // The ordered-in bit, straight from the same snapshot. Tab-grouping reads it to refuse folding a
            // window the WindowServer still shows on screen (see `TrackedWindow.isOrderedIn`); it is not a
            // visibility decision of ours, so it is written whatever else this snapshot says.
            let wasPhantom = state.isPhantom(state.windows[i])
            // **Refuse only the stale PAIR, not every `false`.** On a Dock restore the WindowServer's bits
            // settle when the animation ends (~644ms, measured), later than the 815 that already put the
            // window back on screen: the snapshot then says minimized AND off-screen together, both stale.
            // The minimized write below already refuses its half; believing the other half undid the
            // order-in, and once `PhantomWindowDetector` started reading this bit that did not merely delay
            // a tab decision, it flagged the restored window phantom and hid it (generator seed 13,
            // `newWindow → minimize → restoreFromDock → show`).
            //
            // Narrow on purpose. A plain `isVisible: false` with no minimized claim is the query doing the
            // job only it can do — correcting a window whose order-OUT we never saw — and that must still
            // land (`testTheWindowServerQueryResyncsTheOnScreenBit`).
            let staleRestorePair = !snap.isVisible && snap.isMinimized
                && !state.carried.offScreen.contains(snap.wid)
            if !staleRestorePair { state.windows[i].isOrderedIn = snap.isVisible }
            // Alpha, from the same snapshot and for the same reason: it is a fact the WindowServer reports,
            // not a decision of ours, and `PhantomWindowDetector` needs it stated rather than inferred.
            if state.windows[i].alpha != snap.alpha {
                state.windows[i].alpha = snap.alpha
                changed = true
            }
            // Both writes above feed the phantom verdict, so the derived flag can flip here — and a flip with
            // no placeholder effect is #5849 in one direction or the other.
            if state.isPhantom(state.windows[i]) != wasPhantom, !state.windows[i].isWindowlessApp {
                let pid = state.windows[i].pid
                if wasPhantom {
                    focusRepairs.append(.removeWindowlessPlaceholder(pid: pid))
                } else if !appHasRealWindow(state, pid: pid) {
                    focusRepairs.append(.addWindowlessPlaceholder(pid: pid))
                }
                changed = true
            }
            // Minimized comes from this query now rather than from an AX read into the window's own app.
            // The bit is prompt on the way IN (~35ms) but LATE on the way OUT — on a Dock restore it only
            // clears when the animation ends, ~644ms after the order-in that already put the window back on
            // screen. So a `true` is believed only while the WindowServer still says the window is off
            // screen; once it has come back, `movedResizedOrOrderedIn` has already ruled and this query is
            // reporting the state it is replacing. A `false` is always believed — that direction is never
            // stale, so no un-minimize can be missed here.
            if state.windows[i].isMinimized != snap.isMinimized,
               !snap.isMinimized || state.carried.offScreen.contains(snap.wid) {
                state.windows[i].isMinimized = snap.isMinimized
                changed = true
                if snap.isMinimized {
                    focusRepairs += refrontAfterFocusedWindowBecomesUnavailable(&state, wid: snap.wid)
                }
            }
            if changed {
                changedAny = true
                if snap.isVisible { toCapture.append(snap.wid) }
            }
        }
        guard changedAny else { return [] }
        var effects = focusRepairs + reconcile(&state)
        effects.append(.refreshUi(wids: toCapture, onlyWhileSwitcherOpen: true))
        return effects
    }

    /// The off-main Spaces re-query landed (the apply-side of `Applications.syncSpacesState`): backfill the
    /// Space membership from every completed scoped answer, then regroup if anything moved.
    ///
    /// Windows outside `queried` are skipped unless the all-Space enumeration positively names them. A wid
    /// inside `queried` but outside `answered` is skipped too: the direct query failed, which is not the same
    /// fact as a completed `[]`. Flattening either silence into empty asserted the strong phantom signal about
    /// a window for which CGS had supplied no answer.
    ///
    /// UNLESS the map places it anyway, in which case we hold an answer and it would be daft to drop it. The
    /// map is NOT built from `queried`: `Spaces.query` enumerates every Space and takes whatever windows CGS
    /// lists (the same call the summon's discovery sweep reads), so a window appended mid-flight usually IS in
    /// it, and it is the fresher fact — a discovery whose own per-window query came back empty leaves the
    /// window on `Window.init`'s current-Space GUESS, which is wrong the moment the window is on another
    /// Space. Only SILENCE is ambiguous; an answer is an answer whoever it was asked for.
    private static func spacesSynced(_ state: inout TrackedWindowState, windowToSpaces: [CGWindowID: [UInt64]],
                                     queried: Set<CGWindowID>, answered: Set<CGWindowID>,
                                     placedByWindowServer: Set<CGWindowID>,
                                     topologyChanged: Bool) -> [ReducerEffect] {
        var effects = [ReducerEffect]()
        var changed = topologyChanged
        for w in state.windows {
            guard let wid = w.wid else { continue }
            let ids = windowToSpaces[wid]
            let scopedAnswer = queried.contains(wid) && answered.contains(wid)
            let positiveEnumeration = ids?.isEmpty == false
            guard scopedAnswer || positiveEnumeration else { continue }
            // Two OS reads disagree: CGS named no Space for this wid, the WindowServer says it is on one.
            // An empty CGS answer is also what a wid it has never heard of returns, so on its own it cannot
            // carry the weight the strong phantom signal puts on it. Keep the last membership CGS itself
            // reported — stale at worst, and the window stays reachable instead of disappearing with no way
            // back (#5954). The wids the WindowServer does NOT know fall through and are wiped as before;
            // those are the corpses, and `discardDeadPhantomWindows` removes them outright.
            if ids?.isEmpty == true, placedByWindowServer.contains(wid) {
                effects.append(.log("spacesSync keepPlaced #\(wid) sp\(w.spaceIds) (WindowServer places it, CGS named none)"))
                continue
            }
            guard let ids else { continue }
            let r = state.applyWindowSpaces(wid, spaceIds: ids)
            effects.append(.updateScreenId(wid))
            if r.unphantomedRealWindow { effects.append(.removeWindowlessPlaceholder(pid: w.pid)) }
            if r.changed { changed = true }
        }
        guard changed else { return effects }
        effects.append(contentsOf: reconcile(&state))
        effects.append(.refreshUi(wids: [], onlyWhileSwitcherOpen: true))
        return effects
    }

    /// The phantom-detection pass (the apply-side of `Applications.applyPhantomVerdict`): the CGS verdict
    /// per window via the kernel, latched; re-render only windows whose DERIVED phantom actually flipped
    /// (a verdict absorbed by the hold / group-member exemptions doesn't re-render anything).
    private static func cgsWindowListsRead(_ state: inout TrackedWindowState, visible: Set<CGWindowID>,
                                           all: Set<CGWindowID>, queried: Set<CGWindowID>) -> [ReducerEffect] {
        var effects = [ReducerEffect]()
        var changed = [CGWindowID]()
        for i in state.windows.indices {
            guard let wid = state.windows[i].wid, wid != CGWindowID(bitPattern: -1),
                  queried.contains(wid) || all.contains(wid) else { continue }
            // No focus exemption any more. It existed because CGS keeps a reopened Electron window tagged
            // invisible for seconds after it is on screen and focused (#5849), and the weak signal read that
            // tag; the ordered-in bit says the window is on screen, so the case resolves on a fact instead
            // of on "but the user is looking at it".
            let verdict = PhantomWindowDetector.cgsVerdict(state.windowState(state.windows[i]),
                state.appState(state.windows[i].pid),
                inVisibleList: visible.contains(wid),
                inAllList: all.contains(wid),
                isOrderedIn: state.windows[i].isOrderedIn,
                alpha: state.windows[i].alpha,
                visibleSpaceIds: state.visibleSpaces)
            let before = state.isPhantom(state.windows[i])
            state.windows[i].cgsPhantomLatch = verdict
            if state.isPhantom(state.windows[i]) != before {
                effects.append(.log("PhantomDetect flip \(state.windows[i].id) isPhantom=\(state.isPhantom(state.windows[i])) (inVisible=\(visible.contains(wid)) inAll=\(all.contains(wid)) isMinimized=\(state.windows[i].isMinimized) isTabbed=\(state.isTabbed(state.windows[i])) spaceIds=\(state.windows[i].spaceIds))"))
                // Un-phantoming here must drop the app's windowless placeholder, exactly as the Space paths
                // do (`applySpaceMembershipDelta` / `applyWindowSpaces`). This path was the omission: the
                // placeholder is added while the app's only window looks phantom, and CGS-list detection is
                // the path that clears Slack's verdict — so the app kept BOTH a real tile and a windowless
                // one, permanently ("appears twice and won't change even if I wait", #5849).
                if before, !state.windows[i].isWindowlessApp {
                    effects.append(.removeWindowlessPlaceholder(pid: state.windows[i].pid))
                }
                // ...and the OPPOSITE edge, which had no owner at all: an app whose last real window turns
                // phantom needs its placeholder NOW. It used to arrive from the shell's per-app sweep, which
                // runs in the same block but BEFORE these verdicts are applied — so it judged "does this app
                // still have a real window?" against the previous latch, and the app had no tile whatsoever
                // until the NEXT sweep. Live: closing Slack's window gave three different switchers in three
                // consecutive summons (open window / nothing at all / closed-app icon), #5849.
                if !before, !state.windows[i].isWindowlessApp, !appHasRealWindow(state, pid: state.windows[i].pid) {
                    effects.append(.addWindowlessPlaceholder(pid: state.windows[i].pid))
                }
                changed.append(wid)
            }
        }
        if !changed.isEmpty {
            effects.append(.refreshUi(wids: changed, onlyWhileSwitcherOpen: false))
        }
        return effects
    }

    /// Whether the app still has a real window to show — the predicate
    /// `Application.addWindowlessWindowIfNeeded` re-checks in the shell, so the two agree on when an app is
    /// "windowless": every non-phantom window counts, including a minimized one and a hidden background tab.
    private static func appHasRealWindow(_ state: TrackedWindowState, pid: pid_t) -> Bool {
        state.windows.contains { $0.pid == pid && !$0.isWindowlessApp && !state.isPhantom($0) }
    }

    // MARK: - timer checks (was `checkHoldRelease` / `checkDragOut`)

    /// Re-check whether to release a held tab (`TabGroupResolver.shouldReleaseHold` owns the decision; the
    /// shell owns the 0.4s timer). Re-checking rather than waiting a fixed delay is what makes the hold last
    /// exactly as long as a discovery is actually pending — a hardcoded delay expired mid-gap on a slow/busy
    /// OS and the tile vanished anyway.
    private static func holdReleaseCheck(_ state: inout TrackedWindowState, wid: CGWindowID, attempt: Int) -> [ReducerEffect] {
        guard state.held.contains(wid) else { return [] }
        guard let window = state.window(wid) else {
            state.held.remove(wid)
            return []
        }
        let sameApp = state.windows.filter { $0.pid == window.pid && $0.wid != nil }
        guard TabGroupResolver.shouldReleaseHold(isTabbed: state.isTabbed(window),
                hasPresentableReplacement: TabGroupResolver.hasPresentableReplacement(
                    for: state.tabWindow(window), among: sameApp.map { state.tabWindow($0) }),
                attemptsExhausted: attempt >= holdReleaseMaxAttempts) else {
            return [.scheduleHoldReleaseCheck(wid: wid, attempt: attempt + 1)]
        }
        state.held.remove(wid)
        // Claimed by the incoming tab ⇒ already a hidden background tab, nothing to redraw.
        guard !state.isTabbed(window) else { return [] }
        return [.refreshUi(wids: [wid], onlyWhileSwitcherOpen: true)]
    }

    /// A group member that joined a Space is optimistically its group's new active tab (see
    /// `spaceMembershipChanged`); this confirms or refutes the drag-out alternative once the joiner's frame
    /// settles — the kernel decides (`dragOutVerdict`), the shell owns the timer. Undecided (frame not yet
    /// known — a new window is 0×0 for a beat) ⇒ re-check, up to a small cap; on the cap the switch
    /// interpretation stands (safe: a real drag-out's next frames keep diverging and the user sees a
    /// correct tile either way once its own window shows).
    private static func dragOutCheck(_ state: inout TrackedWindowState, wid: CGWindowID, previousRepWid: CGWindowID,
                                     attempt: Int) -> [ReducerEffect] {
        guard let window = state.window(wid), let prevRep = state.window(previousRepWid),
              let gid = state.groups.groupId(of: wid), state.groups.groupId(of: previousRepWid) == gid else { return [] }
        // Attempt 0 already fires `recheckInterval` (0.4s) after the join, and each retry adds another — so
        // from the FIRST retry we are past `recentPairingWindow` (0.5s) and the absence of a paired leave has
        // stopped meaning "still in flight" and started meaning "there isn't one". Attempt 0 itself lands
        // just inside that window, so it must not conclude from silence.
        switch TabGroupResolver.dragOutVerdict(joiner: state.tabWindow(window),
                                               previousRepresentative: state.tabWindow(prevRep),
                                               pairingWindowElapsed: attempt > 0) {
        case .some(true):
            var effects: [ReducerEffect] = [.log("dragOut confirmed #\(wid) left the group of #\(previousRepWid)")]
            effects.append(contentsOf: state.removeFromGroup(wid, reason: "dragOut").map { .log($0) })
            effects.append(.refreshUi(wids: [wid, previousRepWid], onlyWhileSwitcherOpen: true))
            return effects
        case .some(false):
            return []  // same frame ⇒ a tab switch, as assumed
        case .none:
            return attempt < dragOutMaxAttempts ? [.scheduleDragOutCheck(wid: wid, previousRepWid: previousRepWid, attempt: attempt + 1)] : []
        }
    }

    // MARK: - reconcile (was `TabGroup.reconcile` + its three passes)

    /// Re-derive the tab state AX can't keep live, in order:
    /// 1. `inferTabGroupsByGeometry` — link siblings AX can't name (a tab switch; anything fullscreen).
    /// 2. `normalizeGroupVisibility` — each group shows exactly ONE tile, and members that left are unlinked.
    /// 3. `mirrorActiveTabStateToInactiveTabs` — push the visible tab's fullscreen/minimized onto its tabs.
    /// All three read only geometry/Space/fullscreen facts that change on WindowServer events, so this runs
    /// from those reactive handlers — NOT from the synchronous show path, where mutating the model mid-render
    /// reorders tiles (UI jump). By the time the switcher opens the model is already grouped. Cheap and
    /// idempotent: each step no-ops when there's nothing to do.
    /// `newlyDiscovered`: the wid this pass just discovered, if any — the only reliable way to know which
    /// same-frame member is the brand-new active tab (see `TabGroupResolver.geometryGroups`).
    static func reconcile(_ state: inout TrackedWindowState, newlyDiscovered: CGWindowID? = nil) -> [ReducerEffect] {
        var effects = [ReducerEffect]()
        inferTabGroupsByGeometry(&state, newlyDiscovered: newlyDiscovered, into: &effects)
        normalizeGroupVisibility(&state, into: &effects)
        mirrorActiveTabStateToInactiveTabs(&state)
        return effects
    }

    /// Link tab siblings AX can't reconcile in time, from geometry. AX tab titles are read by
    /// `updateTabState`, but only at discovery and the post-show review — not on a tab switch (order events
    /// skip tab reconcile since the fullscreen-dissolve fix) — and never at all for a fullscreen window (it
    /// exposes no readable AXTabGroup). So after switching tabs, the newly-backgrounded tab is left
    /// Space-less (CGS lists no background tab on any Space) with a stale `isTabbed`, the phantom rule hides
    /// it, and it only reappears on the late post-show pass: the "pop-in". Switching repeatedly just swaps
    /// which tab is hidden.
    ///
    /// The grouping decision (which windows form a group, by app + size + Space-less-ness) is the pure
    /// `TabGroupResolver.geometryGroups`; here we DISCOVER nothing (a background tab still enters the list
    /// only once focused), we link windows already tracked, set the visible tab as the group's active one,
    /// and backfill each background tab's Space from it — handing off to the normal machinery (the
    /// `isTabbed` phantom exemption, "show every tab").
    private static func inferTabGroupsByGeometry(_ state: inout TrackedWindowState, newlyDiscovered: CGWindowID?,
                                                 into effects: inout [ReducerEffect]) {
        let candidates = state.windows.filter { !$0.isWindowlessApp && !$0.isMinimized && $0.wid != nil && $0.size != nil }
        guard candidates.count > 1 else { return }
        let candidateWids = Set(candidates.compactMap { $0.wid })
        for group in TabGroupResolver.geometryGroups(candidates.map { state.tabWindow($0) }, newlyDiscovered: newlyDiscovered) {
            guard candidateWids.contains(group.visibleWid) else { continue }
            // **Geometry may not take a member away from a group that already has its own visible tab.**
            // Position is the only fact separating two same-size windows, and it is not always that window's
            // own: rec28 measured a background tab of one Finder window reporting the ORIGIN of the other —
            // not a stale frame of its own, a frame that was never its. Geometry then put it in the wrong
            // partition, and the membership union pulled its whole group across: six windows in one group
            // under a representative declaring three tabs, five of them undrawn.
            //
            // A window whose established group still has an on-screen representative is spoken for by
            // evidence geometry does not have — the AX tab titles of that representative's own AXTabGroup —
            // so a frame is not enough to move it. Ungrouped members, and members of the representative's
            // own group, are untouched: that is every case geometry legitimately decides.
            let background = group.backgroundWids.filter { wid in
                guard candidateWids.contains(wid) else { return false }
                guard let existing = state.groups.groupId(of: wid),
                      existing != state.groups.groupId(of: group.visibleWid),
                      let rep = state.groups.representativeByGroup[existing], rep != wid,
                      let repWindow = state.window(rep), !repWindow.spaceIds.isEmpty else { return true }
                return false
            }
            guard !background.isEmpty else { continue }
            // Geometry's view is PARTIAL: its candidates exclude minimized / size-less windows, so a member
            // it can't see is NOT evidence of departure (absence of a signal, not a signal of absence —
            // unlike the AX-titles path, whose kept-rule accounts for every member). Union the geometry
            // group with the existing memberships of its members, so re-linking a subset never drops the
            // unseen rest of the group.
            var wids = [group.visibleWid] + background
            for w in wids {
                for m in state.groups.siblingWids(of: w) ?? [] where !wids.contains(m) { wids.append(m) }
            }
            let formed = state.formGroup(wids, representative: group.visibleWid, reason: "geometry")
            effects.append(contentsOf: formed.logs.map { .log($0) })
            // The tab the user just SWITCHED TO is the member geometry elected as visible from the
            // `newlyDiscovered` signal. A fullscreen window's switch to a REUSED background wid can reach
            // physical discovery with no promotion attached (the wid was untracked when it joined the Space,
            // so the `joinedSpace` bump and `pendingFocusPromotion` never armed for it), and `.track` lands it
            // at the BACK of the MRU. Left un-bumped, `normalizeGroupVisibility`'s
            // focus-order representative pick keeps a still-tracked sibling that was focused more recently
            // (the outgoing tab, or a background tab) as the tile, so the switcher shows the WRONG tab until
            // that stale sibling is ordered out on the next close ("switched to Movies, opened the switcher,
            // it didn't update; reopening fixed it"). Bump it here, at discovery, exactly as
            // `groupRepresentative`'s contract assumes ("the new tab is bumped at discovery"). Idempotent:
            // if the AX attention answer already fronted it, `noteFocus` no-ops.
            if group.visibleWid == newlyDiscovered {
                effects.append(.log("bumpElectedVisible #\(group.visibleWid) (newlyDiscovered took over group)"))
                effects += applyFocusAndBump(&state, wid: group.visibleWid, at: state.now, .structuralRepair)
            }
            guard let visible = state.window(group.visibleWid) else { continue }
            for wid in background {
                guard let i = state.windowIndex(wid) else { continue }
                state.windows[i].spaceIds = visible.spaceIds
                state.windows[i].spaceIndexes = visible.spaceIndexes
                state.windows[i].isOnAllSpaces = visible.isOnAllSpaces
                state.windows[i].spaceIsBorrowed = !visible.spaceIds.isEmpty
            }
            effects.append(.log("geometryGroup \(state.apps[visible.pid]?.state.localizedName ?? "?") visible#\(group.visibleWid) sp\(visible.spaceIds) background=\(background)"))
        }
    }

    /// Enforce the invariant that a tab group shows EXACTLY ONE tile — its current active tab — and drop
    /// members that have left it. As tabs are created/switched there is an async gap between the old active
    /// backgrounding (1326 → Space-less → phantom → hidden) and the new active being discovered, in which a
    /// group can momentarily have ZERO visible members (the app-icon placeholder pops in) or TWO. Both flash
    /// the group's tile. So per group: keep one representative visible, hide the rest, unlink the departed.
    /// Iterates the registry's groups directly — a standalone window (in no group) is never affected.
    /// (Sorted by gid for replay determinism; groups are disjoint, so order carries no semantics.)
    private static func normalizeGroupVisibility(_ state: inout TrackedWindowState, into effects: inout [ReducerEffect]) {
        // iterate a snapshot: the registry mutates (shrink/dissolve) as departed members are removed
        for (_, wids) in state.groups.membersByGroup.sorted(by: { $0.key < $1.key }) {
            let members = wids.compactMap { state.window($0) }
            guard members.count > 1 else { continue }
            // Which member this group shows — the kernel decides. (Members share one registry entry, so the
            // links always agree and the kernel's incoherent-group nil can no longer fire; guard anyway.)
            guard let repWid = TabGroupResolver.groupRepresentative(members.map { state.tabWindow($0) }),
                  let rep = members.first(where: { $0.wid == repWid }) else { continue }
            // Members that LEFT the group (a tab dragged out of a FULLSCREEN window onto its own new
            // fullscreen Space, still carrying the stale membership). Decided by the kernel — see
            // `membersThatLeftGroup` for why this is fullscreen-only. Removing them shows them as the
            // separate windows they are; without this the group hid every extracted window but one.
            for wid in TabGroupResolver.membersThatLeftGroup(
                visible: state.tabWindow(rep), members: members.map { state.tabWindow($0) }) {
                effects.append(contentsOf: state.removeFromGroup(wid, reason: "leftFullscreenGroup").map { .log($0) })
            }
            effects.append(contentsOf: state.setGroupRepresentative(repWid, reason: "normalize").logs.map { .log($0) })
            showAsGroupRepresentative(&state, repWid: repWid, memberWids: wids, into: &effects)
            // Every member of a group is a tab of ONE window, so they share its Space. Geometry backfills the
            // members IT saw, but membership can also come from AX titles or the minted-switch handover, and
            // those members were left Space-less until some later pass happened to re-run geometry over them
            // — a state that is not a reconcile fixed point. Backfill here, from the representative, marked
            // borrowed because it is our inference and not CGS evidence (generator seed 106).
            if let repSpaces = state.window(repWid)?.spaceIds, !repSpaces.isEmpty {
                for wid in wids where wid != repWid {
                    guard let i = state.windowIndex(wid), state.windows[i].spaceIds.isEmpty else { continue }
                    state.windows[i].spaceIds = repSpaces
                    state.windows[i].spaceIndexes = repSpaces.compactMap { state.spaceIndexById[$0] }
                    state.windows[i].isOnAllSpaces = repSpaces.count > 1
                    state.windows[i].spaceIsBorrowed = true
                    effects.append(.updateScreenId(wid))
                }
            }
        }
    }

    /// Make the representative presentable as the tile its group shows (its `isTabbed` already derives to
    /// false from being the representative). Two facts that would blank the tile mid-transition are borrowed
    /// from its siblings (all tabs of one window, so the facts are interchangeable):
    /// - a Space, when it lost its own while backgrounding — else Space-based display (which Space number the
    ///   tile shows, screen attribution) is wrong for the discovery gap;
    /// - a thumbnail, when it's freshly active and its own capture hasn't landed — else the tile flashes the
    ///   app icon (`TileView` renders the icon exactly when `thumbnail == nil`). The pixels move in the shell
    ///   (`ReducerEffect.copyThumbnail`); the state only tracks that a thumbnail now exists.
    /// The CGS phantom latch is dropped: a verdict taken while this tab was mid-transition must not outlive
    /// the group (the derived group-member exemption covers it only while it stays grouped).
    /// `memberWids` is the group's PRE-shrink member list — sources are looked up against the CURRENT state,
    /// exactly like the live code's lazy reads over its pre-shrink `members` array.
    private static func showAsGroupRepresentative(_ state: inout TrackedWindowState, repWid: CGWindowID,
                                                  memberWids: [CGWindowID], into effects: inout [ReducerEffect]) {
        guard let ri = state.windowIndex(repWid) else { return }
        // Never borrow a Space that CONTRADICTS the representative's own history. Requiring a genuine source
        // was tried and is too strict — every tab of a windowed window carries a borrowed Space, and refusing
        // those made the representative vanish mid-swap (generator seed 15). What actually distinguishes the
        // bad case is staleness: a background tab kept the borrowed Space of the window's PRE-fullscreen
        // life, and when the fullscreen representative briefly went Space-less it borrowed that back, landing
        // the group on a Space it had just left. `lastLeftSpaceId` says which Space that was, so a source
        // offering a different one is stale by definition (generator seed 8).
        if state.windows[ri].spaceIds.isEmpty,
           let src = memberWids.compactMap({ state.window($0) }).first(where: { m in
               !m.spaceIds.isEmpty
                   && (state.windows[ri].lastLeftSpaceId.map { m.spaceIds.contains($0) } ?? true)
           }),
           src.wid != repWid {
            state.windows[ri].spaceIds = src.spaceIds
            state.windows[ri].spaceIndexes = src.spaceIndexes
            state.windows[ri].isOnAllSpaces = src.isOnAllSpaces
            state.windows[ri].spaceIsBorrowed = true
        }
        state.windows[ri].cgsPhantomLatch = false
        if !state.windows[ri].hasThumbnail,
           let src = memberWids.compactMap({ state.window($0) }).first(where: { $0.hasThumbnail }),
           let srcWid = src.wid {
            state.windows[ri].hasThumbnail = true
            effects.append(.copyThumbnail(from: srcWid, to: repWid))
        }
    }

    /// Inactive tabs share their parent window's frame, so an inactive tab is fullscreen/minimized exactly
    /// when its active sibling is. A background tab gets no WindowServer geometry event of its own (only the
    /// visible tab does) and its `isFullscreen` is never read from AX, so those flags would otherwise stay
    /// stale (a fullscreened window's inactive tabs kept showing as non-fullscreen). Mirror the active
    /// sibling onto every inactive tab — the same idea as the spaceIds propagation.
    private static func mirrorActiveTabStateToInactiveTabs(_ state: inout TrackedWindowState) {
        for i in state.windows.indices where state.isTabbed(state.windows[i]) {
            guard let active = state.activeTabSibling(of: state.windows[i]) else { continue }
            // MARK the mirror: this is a display/filter fact, not OS evidence. A frozen background tab
            // wearing an unmarked mirrored fullscreen flag poisoned the whole windowed size-cluster (rec21).
            if state.windows[i].isFullscreen != active.isFullscreen {
                state.windows[i].isFullscreen = active.isFullscreen
                state.windows[i].isFullscreenMirrored = active.isFullscreen
            }
            state.windows[i].isMinimized = active.isMinimized
        }
    }

    // MARK: - updateTabState (was `TabGroup.updateState`)

    /// Update tab state for a window and its siblings using AX-discovered tab titles.
    /// Resolves titles to WIDs (via `TabGroupResolver.matchSiblings`), propagates space info from active to
    /// inactive tabs, and clears stale state on windows no longer in the group.
    /// Returns whether any window's tab state or space changed, plus the effects (inactive-tab discovery,
    /// log lines).
    /// Store the AXTabGroup's button count from a read, the half of it that is never in doubt (the per-tab
    /// TITLES are what an app can compose differently, #5785). Retiring it needs care for exactly the reason
    /// the nil-titles policy exists: an active tab reports NO AXTabGroup transiently while tabs are created
    /// or switched, so a nil read alone can't mean "no longer tabbed". A nil read of a window that is ALSO in
    /// no group can, though: the group is only ever dissolved by a positive signal, so by then the window
    /// really is standalone and the stale count must go, or it would keep the geometry gate open for a window
    /// whose tabs are gone.
    /// Returns whether the stored count actually MOVED — a fact geometry has never seen, and the only thing
    /// that can open its tab-count confirmation (`TabGroupResolver.tabCountAccountsForEveryMember`). The caller
    /// must reconcile on it: see the call site for the merge that formed no group because of the 11ms gap.
    @discardableResult
    private static func recordTabObservation(_ state: inout TrackedWindowState, wid: CGWindowID,
                                             observation: TabGroupObservation) -> Bool {
        guard let i = state.windowIndex(wid) else { return false }
        let before = state.windows[i].tabCount
        if observation != .unknown { state.windows[i].tabGroupObservation = observation }
        if let titles = observation.titles, titles.count > 1 {
            state.windows[i].tabCount = titles.count
        } else if observation == .standalone, state.groups.groupId(of: wid) == nil {
            state.windows[i].tabCount = 0
        }
        return state.windows[i].tabCount != before
    }

    static func updateTabState(_ state: inout TrackedWindowState, activeWid: CGWindowID?, siblingTitles: [String]?,
                               tabGroupToken: TabGroupToken? = nil,
                               activeIsNewlyDiscovered: Bool = false) -> (changed: Bool, effects: [ReducerEffect]) {
        var effects = [ReducerEffect]()
        var changed = false
        guard let titles = siblingTitles else {
            // The active tab reported no AXTabGroup. We used to dissolve the group here (drag-out / last
            // sibling closed). But a nil read is ALSO returned transiently while tabs are being created or
            // switched — an active Terminal tab mid-animation exposes no AXTabGroup for a beat — and
            // dissolving on that tore apart a live group: both tabs flashed as separate windows, and once
            // the siblings were un-tabbed with still-stale `spaceIds` they could no longer be matched as
            // inactive tabs (indistinguishable from a genuine new same-title window, cf.
            // `testOnScreenWindowNeverClaimedAsTab`), so the group could never reform — the 2-tile flash and
            // the stuck extra tiles in the 2026-07-14 capture. So NEVER dissolve on a nil read now:
            // a group shrinks only on a POSITIVE signal — a window removed (`removeFromGroup` on 804 /
            // order-out) or a tab that rejoined a Space (`inactiveTabBecameActive` takes it out of its
            // group). Any member that genuinely left is also dropped by the next read that DOES return
            // titles (`form` is exact-set).
            let siblings = activeWid.flatMap { state.groups.siblingWids(of: $0) } ?? []
            effects.append(.log("updateState active#\(activeWid ?? 0) nilTitles keptGroup siblings=\(siblings)"))
            return (changed, effects)
        }
        guard let activeWid, let active = state.window(activeWid) else { return (changed, effects) }
        let pid = active.pid
        // BEFORE the projection, so this read's own token is what the kernel compares against. Recorded on
        // every read that names a tab group, which is how membership accrues: each tab hands out the same
        // element as it becomes selected, so the group learns its members from the user simply using them.
        state.groups.recordToken(tabGroupToken, for: activeWid)
        let sameApp = state.windows.filter { $0.pid == pid && $0.wid != nil }
        let match = TabGroupResolver.matchSiblings(active: state.tabWindow(active), axTitles: titles,
            sameAppWindows: sameApp.map { state.tabWindow($0) }, activeIsNewlyDiscovered: activeIsNewlyDiscovered)
        // AX named two or more tabs and not ONE window could be matched to any of them. That says nothing
        // about this window having left its group; it says the titles aren't comparable to window titles at
        // all (an app composing the two differently — #5785 — where even the prefix fallback misses), or that
        // every sibling is still untracked. Same rule as the nil-titles path above: a group shrinks only on a
        // POSITIVE signal. Without this the read DISSOLVED the group geometry had just formed, geometry
        // re-formed it on the next WindowServer event, and the pair churned between one tile and two for as
        // long as the window lived.
        let titlesNamedNothing = titles.count > 1 && match.matchedWids.isEmpty
        // Some AXTabGroup titles had no tracked window: these are INACTIVE tabs, whose window is in no CGS
        // list so normal discovery never finds them — that's why a tabbed window shows only its focused tab
        // until you click another. The inactive tab's accessibility element is still reachable, so discover
        // it from there.
        if !match.untrackedTitles.isEmpty {
            effects.append(.discoverInactiveTabs(pid: pid, untrackedTitles: match.untrackedTitles, requesterWid: activeWid))
        }
        // A group of ONE is not a group. With nothing matched, this window's other tabs simply aren't tracked
        // yet (they're in `untrackedTitles`, being discovered right now), so a self-only membership states
        // nothing about any other window — yet a group membership is precisely what geometry reads as "this
        // is an AX-CONFIRMED tab cluster". Writing one handed that confirmation to whatever same-size window
        // geometry happened to cluster this one with, and an unrelated Finder window annexed it (rec8:
        // `geometryGroup visible#74625 background=[74626]`, 74626 being a real window mid new-tab). The
        // registry can't hold a group of one, and this active leaves any group it was in.
        if match.siblingWids.count > 1 {
            // FOCUS — not read order — decides which member the group shows. This read usually comes from the
            // group's current active tab, but AX reads are queued and can land right after the user switched
            // to another member (rec18): making the reader the representative displaced the real active. The
            // kernel picks from the pre-mutation facts; nil (members' links still disagree, e.g. a brand-new
            // group mid-formation) falls back to the reader.
            let memberSnapshots = match.siblingWids.compactMap { state.window($0) }.map { state.tabWindow($0) }
            let repWid = TabGroupResolver.groupRepresentative(memberSnapshots) ?? activeWid
            // form() is exact-set: windows in the active's old group that the match no longer names are
            // ungrouped by it (that IS the `toUntabWids` cleanup); the loop below covers the edge where a
            // toUntab window sits in a group the active isn't in.
            let formed = state.formGroup(match.siblingWids, representative: repWid, reason: "axTitles")
            effects.append(contentsOf: formed.logs.map { .log($0) })
            if formed.changed { changed = true }
        } else if !titlesNamedNothing, state.groups.groupId(of: activeWid) != nil {
            effects.append(contentsOf: state.removeFromGroup(activeWid, reason: "axTitlesSolo").map { .log($0) })
            changed = true
        }
        let activeNow = state.window(activeWid) ?? active
        for wid in match.matchedWids {
            guard let i = state.windowIndex(wid) else { continue }
            if state.windows[i].spaceIds != activeNow.spaceIds { changed = true }
            state.windows[i].spaceIds = activeNow.spaceIds
            state.windows[i].spaceIndexes = activeNow.spaceIndexes
            state.windows[i].isOnAllSpaces = activeNow.isOnAllSpaces
            state.windows[i].spaceIsBorrowed = !activeNow.spaceIds.isEmpty
        }
        for wid in match.toUntabWids where !titlesNamedNothing {
            if state.groups.groupId(of: wid) != nil {
                effects.append(contentsOf: state.removeFromGroup(wid, reason: "axUntab").map { .log($0) })
                changed = true
            }
        }
        effects.append(.log("updateState active#\(activeWid)\(activeIsNewlyDiscovered ? " NEW" : "") tok=\(tabGroupToken.map(String.init) ?? "-") titles=\(titles) matched=\(match.matchedWids) untracked=\(match.untrackedTitles) untab=\(match.toUntabWids)\(titlesNamedNothing ? " namedNothing keptGroup" : "") changed=\(changed)"))
        return (changed, effects)
    }
}
