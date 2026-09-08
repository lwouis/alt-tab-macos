import CoreGraphics
import Foundation

/// Replays a transcribed debug-log recording against the pure `WindowEventReducer`, so an adapter-layer
/// regression becomes a failing unit test instead of a live QA session. A fixture is an initial
/// `TrackedWindowState` plus a sequence of steps; after EVERY step the harness checks the cross-cutting invariants
/// the recordings kept violating one path at a time (one tile per group, no cross-frame group, the focused
/// window shown, no on-Space window claimed, Space-less strays hidden, focus picks the representative).
///
/// The harness stands in for the IO shell: reducer effects that MUTATE the model in the live app
/// (`removeWindow`) are applied via pure twins; async requests (AX reads, WS queries) are recorded as
/// pending — the fixture supplies their results as later inputs, transcribed from the recording; timer
/// effects are recorded as pending and fired by explicit `holdReleaseCheck` / `dragOutCheck` steps, so a
/// fixture can replay exactly the timing the recording sampled (or explore the orders it didn't — races
/// are data here).
final class TestReducerRunner {
    /// One step of a replay: a reducer input, or a shell action the reducer doesn't own — the shell
    /// tracking a new window (`findOrCreate`/`appendWindow`, which precedes its `discoveryLanded` input) or
    /// an app's AppKit active flag changing.
    enum Step {
        case input(ReducerInput)
        /// the shell appended a discovered window (assigns `lastFocusOrder` like `Windows.appendWindow`)
        case track(TrackedWindow)
        case setAppActive(pid: pid_t, isActive: Bool)
        case setFrontmost(pid: pid_t?)
        /// The shell's AX `kAXMinimized` write (`Applications.refreshWindowTitleAndTabs`, which sets the flag
        /// on the live `Window` and only then dispatches `.titleAndTabsRead`). A step of its own because that
        /// read is ASYNC and, on a Dock restore, ANSWERS LATE: the WindowServer order-in arrives ~30ms in
        /// while the app still reports minimized for ~530ms (measured). A fixture that wants to replay that
        /// staleness emits the order-in WITHOUT a matching `setMinimized(false)` — which is exactly the
        /// recorded shape, and what no scenario could express before.
        case setMinimized(wid: CGWindowID, isMinimized: Bool)
        /// ambient Space topology the reducer reads but doesn't own (a fullscreen transition / Space switch)
        case setSpaces(visible: [UInt64], current: UInt64, index: (UInt64, Int))
        /// A window capture landed: the shell now has pixels for this wid. Modelled because the tile falls
        /// back to the app ICON whenever `thumbnail == nil`, so a tile handed to a window whose capture
        /// hasn't landed visibly flashes — which is a defect the user sees even when the tile itself never
        /// disappears.
        case thumbnailCaptured(wid: CGWindowID)
        /// `Windows.sort()`: the list is re-sorted by MRU before every show. NOT cosmetic — several reducer
        /// rules are order-sensitive first-wins (`applyWindowSpaces`' sibling backfill walks the list in
        /// order; `matchSiblings` claims the first compatible candidate), so which member of a group comes
        /// first decides outcomes. Live capture (rec26): after switching tabs the new representative sits at
        /// index 0, AHEAD of its own background tabs.
        case sortByMru
    }

    /// Wids the OS is currently moving between Spaces. Such a window is genuinely absent from every Space
    /// for the duration, so it IS hidden — correctly — and the visibility invariants must not read that as a
    /// defect. The driver keeps this in step with `TestInteractionModel.windowsInSpaceTransition`; a replay
    /// fixture that never sets it behaves exactly as before.
    var widsInSpaceTransition = Set<CGWindowID>()

    private(set) var state: TrackedWindowState
    /// timer effects the reducer scheduled and no fired step has consumed yet
    private(set) var pendingTimers = [ReducerEffect]()
    /// async OS requests the reducer made (AX reads / WS queries / discoveries) — trace + assertions
    private(set) var pendingRequests = [ReducerEffect]()
    /// every log fact the reduction emitted, tagged with its step index — the replay's own recording
    private(set) var trace = [String]()
    /// invariant violations, tagged with the step that caused them; empty = a clean replay
    private(set) var violations = [String]()
    /// every `.refreshUi` the reduction asked for, in order. Recorded because it is the reducer's ONLY way
    /// to repaint a switcher that is ALREADY OPEN, so a state flip that emits none is a defect the user
    /// sees: the tile keeps the stale value until the panel is closed and reopened (the un-minimize case).
    private(set) var refreshes = [(wids: [CGWindowID], onlyWhileSwitcherOpen: Bool)]()
    /// every window whose captures the reduction asked to hold until its restore animation ends, in order
    private(set) var deferredCaptures = [CGWindowID]()
    private var stepIndex = 0
    /// stands in for the shell's `systemUptime` stamp (see `.input`)
    private var clock: TimeInterval = 1
    private let tick: TimeInterval = 0.001

    init(initial: TrackedWindowState) {
        state = initial
        checkInvariants(context: "initial")
    }

    /// Change the visible/current Space topology mid-scenario (a fullscreen transition, a Space switch) —
    /// ambient state the reducer reads but doesn't own. Used by `TestScenarioSimulator`.
    func setSpaces(visible: [UInt64], current: UInt64, index: (UInt64, Int)) {
        state.visibleSpaces = visible
        state.currentSpaceId = current
        state.spaceIndexById[index.0] = index.1
    }

    /// Run all steps; returns self for chaining into assertions.
    @discardableResult
    func run(_ steps: [Step]) -> TestReducerRunner {
        for step in steps { perform(step) }
        return self
    }

    func perform(_ step: Step) {
        stepIndex += 1
        switch step {
        case .track(var window):
            // `Windows.appendWindow`: the new window enters at the back of the MRU; the reducer's
            // `.discoveryLanded` promotion fronts it if it was freshly created / focused while untracked.
            // A bare track is NOT reconciled yet (the app appends, then its `.discoveryLanded` reconciles) —
            // so the per-frame invariants apply but CONVERGENCE does not (reconcile legitimately has pending
            // work until the following input runs it).
            window.lastFocusOrder = state.windows.count
            state.windows.append(window)
            checkInvariants(context: "track \(window.id)", checkConvergence: false)
        case .setAppActive(let pid, let isActive):
            var app = state.apps[pid] ?? TrackedApp(state: ApplicationState(
                pid: pid, bundleIdentifier: nil, localizedName: nil, isHidden: false))
            app.isActive = isActive
            state.apps[pid] = app
        case .setFrontmost(let pid):
            state.frontmostPid = pid
        case .setMinimized(let wid, let isMinimized):
            if let i = state.windowIndex(wid) { state.windows[i].isMinimized = isMinimized }
            checkInvariants(context: "setMinimized \(wid)=\(isMinimized)", checkConvergence: false)
        case .setSpaces(let visible, let current, let index):
            setSpaces(visible: visible, current: current, index: index)
        case .thumbnailCaptured(let wid):
            if let i = state.windowIndex(wid) { state.windows[i].hasThumbnail = true }
        case .sortByMru:
            state.windows.sort { $0.lastFocusOrder < $1.lastFocusOrder }
            checkInvariants(context: "sortByMru", checkConvergence: false)
        case .input(let input):
            // What the shell stamps on every dispatch (`TrackedWindowState.now`): replayed, not read from a
            // clock. An input that carries its own `now` sets it; anything else advances by a tick. Always
            // above zero, since zero is "never focused" and could not move the MRU.
            clock = max(clock + tick, inputTime(input) ?? 0)
            state.now = clock
            let effects = WindowEventReducer.reduce(&state, input)
            consumeFiredTimer(input)
            for effect in effects { apply(effect) }
            // A Space JOIN is half of a swap: its paired 1326 lands a millisecond later, and in between two
            // members legitimately hold the same Space, which reconcile would settle differently on a second
            // pass. Demanding a fixed point there reports the pair itself as churn. Every other input —
            // including the 1326 that completes the swap, and every read — is still checked.
            var isSpaceJoin = false
            if case .spaceMembershipChanged(_, _, let added, _, _) = input { isSpaceJoin = added }
            checkInvariants(context: describe(input), checkConvergence: !isSpaceJoin)
        }
    }

    /// The model-affecting effects get pure twins of what the shell does; requests and timers are recorded.
    private func apply(_ effect: ReducerEffect) {
        switch effect {
        case .removeWindow(let wid):
            removeWindowTwin(wid)
        case .scheduleHoldReleaseCheck, .scheduleDragOutCheck:
            pendingTimers.append(effect)
        case .discoverWindow, .probeWindowLiveness, .readTitleAndTabs, .queryWindowServerState,
             .discoverInactiveTabs, .reconcileAxElementEnd,
             .refreshSpacesTopology, .refreshSpacesTopologyAndSync:
            pendingRequests.append(effect)
        case .log(let line):
            trace.append("[\(stepIndex)] \(line)")
        case .refreshUi(let wids, let onlyWhileSwitcherOpen):
            refreshes.append((wids, onlyWhileSwitcherOpen))
        case .refreshUiImmediately(let wids):
            refreshes.append((wids, false))
        case .deferCaptureUntilRestoreEnds(let wid):
            deferredCaptures.append(wid)
        case .copyThumbnail, .applyFocus, .updateScreenId, .removeWindowlessPlaceholder,
             .addWindowlessPlaceholder, .readFocusedWindowOnActivation,
             .checkShortcutsForFocusedWindow, .retireSurface:
            break  // display/AppKit-side; no model content beyond what the reducer already wrote
        }
    }

    /// The model half of `Windows.removeWindows`, for one wid: drop it from the list, close the MRU gap,
    /// drain its pending-set entries, shrink its group.
    private func removeWindowTwin(_ wid: CGWindowID) {
        guard let i = state.windowIndex(wid) else { return }
        let order = state.windows[i].lastFocusOrder
        state.windows.remove(at: i)
        for j in state.windows.indices where state.windows[j].lastFocusOrder > order {
            state.windows[j].lastFocusOrder -= 1
        }
        state.pendingFocusPromotion.removeValue(forKey: wid)
        state.recentlyCreated.remove(wid)
        state.pendingSpaceRemoval.removeValue(forKey: wid)
        state.held.remove(wid)
        for line in state.removeFromGroup(wid, reason: "windowRemoved") { trace.append("[\(stepIndex)] \(line)") }
    }

    /// A fired timer input consumes its pending entry (attempt-agnostic: the reducer re-schedules with
    /// attempt+1, which `apply` re-records).
    private func consumeFiredTimer(_ input: ReducerInput) {
        switch input {
        case .holdReleaseCheck(let wid, _):
            if let i = pendingTimers.firstIndex(where: {
                if case .scheduleHoldReleaseCheck(let w, _) = $0 { return w == wid } else { return false }
            }) { pendingTimers.remove(at: i) }
        case .dragOutCheck(let wid, _, _):
            if let i = pendingTimers.firstIndex(where: {
                if case .scheduleDragOutCheck(let w, _, _) = $0 { return w == wid } else { return false }
            }) { pendingTimers.remove(at: i) }
        default:
            break
        }
    }

    private func describe(_ input: ReducerInput) -> String {
        String(describing: input)
    }

    /// The `now` an input carries, where it carries one — the truest stamp for that step's clock.
    private func inputTime(_ input: ReducerInput) -> TimeInterval? {
        switch input {
        case .windowCreated(_, let now, _), .windowOrderedIn(_, let now, _),
             .windowFocused(_, let now), .appActivated(_, let now, _),
             .altTabFocusedWindowInFrontmostApp(_, _, let now),
             .spaceMembershipChanged(_, _, _, let now, _):
            return now
        default:
            return nil
        }
    }

    // MARK: - invariants (checked after every step)

    /// Is this window a tile the switcher would show? The replay-level notion: not an inactive tab, not
    /// phantom. (User filters — minimized/hidden-app placement, Space filters — are display preferences the
    /// recordings don't exercise; phantom + tab visibility are what every recorded bug broke.)
    private func isDisplayed(_ w: TrackedWindow) -> Bool {
        !state.isTabbed(w) && !state.isPhantom(w)
    }

    private func violation(_ context: String, _ message: String) {
        violations.append("step \(stepIndex) (\(context)): \(message)")
    }

    /// The per-frame invariants run after EVERY step; convergence only after a reducer `.input` settled the
    /// model (a bare `.track`/`.setAppActive` leaves reconcile legitimately pending — see `.track`).
    private func checkInvariants(context: String, checkConvergence: Bool = true) {
        checkOneTilePerGroup(context)
        checkNoGroupSpansDistinctFrames(context)
        checkFocusedWindowNeverHidden(context)
        checkRealOnSpaceWindowNeverClaimed(context)
        checkSpacelessUngroupedHidden(context)
        checkRepresentativeFollowsFocus(context)
        if checkConvergence { checkReconcileHasConverged(context) }
    }

    /// A normalized, group-id-independent fingerprint of everything `reconcile` reads or writes — the group
    /// PARTITION (each group as its sorted member set + representative, the whole thing sorted) plus the
    /// per-window facts reconcile mutates. Two states with the same fingerprint are the same as far as tab
    /// detection is concerned, regardless of the `nextGroupId` counter.
    private func reconcileFingerprint(_ s: TrackedWindowState) -> String {
        let groups = s.groups.membersByGroup.values.map { wids -> String in
            let gid = s.groups.groupId(of: wids.first ?? 0)
            let rep = gid.flatMap { s.groups.representativeByGroup[$0] } ?? 0
            return "{\(wids.sorted().map(String.init).joined(separator: ","))}=\(rep)"
        }.sorted().joined(separator: " ")
        let windows = s.windows.sorted { ($0.wid ?? 0) < ($1.wid ?? 0) }.map { w in
            "\(w.wid ?? 0):sp\(w.spaceIds.sorted())b\(w.spaceIsBorrowed ? 1 : 0)f\(w.isFullscreen ? 1 : 0)m\(w.isFullscreenMirrored ? 1 : 0)"
        }.joined(separator: " ")
        return "G[\(groups)] W[\(windows)]"
    }

    /// CONVERGENCE / IDEMPOTENCE: after a step settles, running `reconcile` again must be a NO-OP. A reducer
    /// that re-forms a group with a fresh id every pass, or re-derives a Space differently each time, never
    /// reaches a fixed point — the model churns forever while the switcher is open (tiles reorder, flap,
    /// vanish; rec24f). None of the local per-frame invariants can see this: each individual frame is valid,
    /// it's the SEQUENCE that never settles. So we take the fingerprint, run one more reconcile on a copy,
    /// and require the fingerprint to be unchanged.
    private func checkReconcileHasConverged(_ context: String) {
        let before = reconcileFingerprint(state)
        var copy = state
        _ = WindowEventReducer.reconcile(&copy)
        let after = reconcileFingerprint(copy)
        if before != after {
            violation(context, "reconcile is NOT at a fixed point (not idempotent):\n    before: \(before)\n    after:  \(after)")
        }
    }

    /// Each group shows EXACTLY one tile while it has a claim to the screen, and none once it's dead
    /// remains (rec22's ghost group). More than one shown member is the 2-tile flash (rec13/rec19).
    private func checkOneTilePerGroup(_ context: String) {
        for (gid, wids) in state.groups.membersByGroup.sorted(by: { $0.key < $1.key }) {
            let members = wids.compactMap { state.window($0) }
            let displayed = members.filter { isDisplayed($0) }.compactMap { $0.wid }
            let hasClaim = state.groups.hasScreenClaim(gid) { m in
                !(state.window(m)?.spaceIds.isEmpty ?? true) || state.held.contains(m)
            }
            if displayed.count > 1 {
                violation(context, "group g\(gid) shows \(displayed.count) tiles \(displayed) — must be ≤ 1")
            }
            if hasClaim && displayed.isEmpty && !members.isEmpty {
                violation(context, "group g\(gid) has a screen claim but shows ZERO tiles (members \(wids))")
            }
        }
    }

    /// A group's members must agree on their frame — the cross-cutting rule every theft broke (rec8/10/11/12;
    /// see `frameCorpus`) — but HOW MUCH they must agree depends on whether the group was guessed or proven.
    ///
    /// Guessed (nothing but geometry noticed these windows look alike): the FULL frame must match, as it
    /// always did. That is precisely where a window at one frame stole a window at another, so the guard
    /// stays at full strength exactly where it earned its place.
    ///
    /// Proven (the OS itself reported this window has tabs — `tabCount > 1`): only the WIDTH must match.
    /// Requiring the whole frame there asserts something FALSE about real tab groups: a tab bar appearing
    /// changes the window's height, and after "Merge All Windows" background tabs keep their pre-merge
    /// POSITION indefinitely — both measured live on macOS 26. Width is the one thing that held across every
    /// case measured, so it is what the rule now says. Without this split the invariant fires on correctly
    /// grouped windows, and no fix for the tab-bar case could ever pass it.
    ///
    /// Transitional states the design accepts are excluded: a group with an
    /// in-flight drag-out verdict (frames legitimately diverge until the kernel rules), a held member
    /// (mid-swap), or an unrenderable frame (the OS publishes a new tab at 0×0 and sizes it later).
    ///
    /// A group with a GENUINELY-fullscreen member is skipped whole. Fullscreen resizes only the ACTIVE tab,
    /// so a fullscreen window's tabs legitimately wear several frames at once: tabs backgrounded before the
    /// transition stay frozen at the old windowed size, while one backgrounded after it is frozen at the
    /// fullscreen size. Frames simply carry no theft signal there — which is why the per-member fullscreen
    /// exemption already existed; it just missed that a MIRRORED tab (`tw.isFullscreen` masked to false) is
    /// one of those frozen tabs too.
    private func checkNoGroupSpansDistinctFrames(_ context: String) {
        for (gid, wids) in state.groups.membersByGroup.sorted(by: { $0.key < $1.key }) {
            let members = wids.compactMap { state.window($0) }
            if members.contains(where: { $0.wid.map { state.held.contains($0) } ?? false }) { continue }
            if members.contains(where: { state.tabWindow($0).isFullscreen }) { continue }
            if wids.contains(where: { wid in pendingTimers.contains {
                if case .scheduleDragOutCheck(let w, _, _) = $0 { return w == wid } else { return false }
            } }) { continue }
            // The OS confirmed a tab group here, so this membership is evidence rather than a guess.
            let osConfirmedTabs = members.contains { $0.tabCount > 1 }
            let frames = members.compactMap { w -> String? in
                let tw = state.tabWindow(w)
                guard !tw.isFullscreen, let s = w.size, let p = w.position,
                      s.width > 0, s.height > 0 else { return nil }
                return osConfirmedTabs
                    ? "\(Int(s.width.rounded()))w"
                    : "\(Int(s.width.rounded()))x\(Int(s.height.rounded()))@\(Int(p.x.rounded())),\(Int(p.y.rounded()))"
            }
            if Set(frames).count > 1 {
                violation(context, "group g\(gid) spans distinct \(osConfirmedTabs ? "widths" : "frames") "
                    + "\(Set(frames).sorted()) (members \(wids))")
            }
        }
    }

    /// The focused window is never hidden: the most recently focused window of the frontmost, active app
    /// must be shown (a focused window can never be a background tab — `finderFocusedWindowWronglyTabbed`).
    private func checkFocusedWindowNeverHidden(_ context: String) {
        guard let focused = state.windows.first(where: { $0.lastFocusOrder == 0 }),
              !(focused.wid.map { widsInSpaceTransition.contains($0) } ?? false),
              let pid = state.frontmostPid, focused.pid == pid,
              state.apps[pid]?.isActive == true,
              !focused.isWindowlessApp, !focused.isMinimized,
              state.apps[pid]?.state.isHidden != true else { return }
        if !isDisplayed(focused) {
            violation(context, "focused window \(focused.id) is hidden (isTabbed=\(state.isTabbed(focused)) isPhantom=\(state.isPhantom(focused)))")
        }
    }

    /// A real on-Space window is never claimed as a tab: tabbed ⇒ its Space is empty, borrowed, or the hold
    /// says it's mid-swap. Two sanctioned transitional shapes are exempt: a window creation in flight — the
    /// count-driven atomic claim DELIBERATELY claims the old active whose 1326 hasn't landed (the creation
    /// race, `terminalNewTab*`) — and a rep swap with an in-flight drag-out verdict, where the OUTGOING
    /// representative keeps its genuine Space for the few ms until its own 1326 lands (rec19's switch shape).
    private func checkRealOnSpaceWindowNeverClaimed(_ context: String) {
        guard state.recentlyCreated.isEmpty else { return }
        for w in state.windows where state.isTabbed(w) {
            guard let wid = w.wid else { continue }
            if pendingTimers.contains(where: {
                if case .scheduleDragOutCheck(_, let prev, _) = $0 { return prev == wid } else { return false }
            }) { continue }
            if !w.spaceIds.isEmpty && !w.spaceIsBorrowed && !state.held.contains(wid) {
                violation(context, "window \(w.id) holds a GENUINE Space \(w.spaceIds) yet is claimed as a tab")
            }
        }
    }

    /// A Space-less, ungrouped, unheld window is hidden (phantom) — the strays the recordings kept finding
    /// shown (rec15's ghost flood arrived visible; rec20's orphan stood as a stray tile).
    ///
    /// ORDERED-IN windows are exempt, because `PhantomWindowDetector.syncVerdict` says so before it ever
    /// reaches Space-lessness: "a window the WindowServer is still showing on screen is not a phantom".
    /// Demanding otherwise here states a rule the app deliberately does not have, and the state is reachable
    /// — a window LEAVING fullscreen is ordered back in while CGS has not yet listed it on the windowed
    /// Space (`exitFullscreen`). A real stray is ordered OUT, which is what the recordings above caught.
    private func checkSpacelessUngroupedHidden(_ context: String) {
        for w in state.windows {
            guard let wid = w.wid, w.spaceIds.isEmpty, !w.isWindowlessApp, !w.isMinimized, !w.isOrderedIn,
                  state.apps[w.pid]?.state.isHidden != true,
                  state.groups.groupId(of: wid) == nil, !state.held.contains(wid) else { continue }
            if !state.isPhantom(w) {
                violation(context, "Space-less ungrouped window \(w.id) is not hidden")
            }
        }
    }

    /// The group representative is the most recently focused presentable member — focus is authoritative
    /// (rec18/rec19); anything else is read-order-sensitive.
    private func checkRepresentativeFollowsFocus(_ context: String) {
        for (gid, wids) in state.groups.membersByGroup.sorted(by: { $0.key < $1.key }) {
            let members = wids.compactMap { state.window($0) }
            guard let expected = TabGroupResolver.groupRepresentative(members.map { state.tabWindow($0) }),
                  let actual = state.groups.representativeByGroup[gid] else { continue }
            if expected != actual {
                violation(context, "group g\(gid) representative is #\(actual), focus says #\(expected)")
            }
        }
    }
}
