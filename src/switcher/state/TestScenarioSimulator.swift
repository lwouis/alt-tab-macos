import CoreGraphics
import Foundation

/// A named sequence of user actions — a `TestScenario` IS a test. The simulator runs it (through
/// `TestInteractionModel` + `TestReducerRunner`) and, in `fuzz`, RE-runs it under several event ORDERINGS.
typealias TestScenario = [TestUserAction]

/// Drives a `TestScenario`: asks `TestInteractionModel` for each action's OS events, feeds them to the
/// reducer via `TestReducerRunner`, and checks the GROUND-TRUTH property no raw-`TrackedWindowState`
/// invariant can — **N real windows ⇒ N tiles**, each shown by its own active tab, no group spanning two
/// windows. `fuzzFailure` replays the scenario under multiple orderings of the async read landings (the
/// interleaving), so one written scenario exercises many races — the churn class lives there.
final class TestScenarioSimulator {
    /// How a scenario's async read UNITS (per action, esp. a `show`'s reads) are ordered as they land — the
    /// fuzz axis (same actions, different event races). Kept to IMMEDIATE orderings: each action's reads land
    /// before the next action. Faithful CROSS-action deferral (a read landing one or two actions late — the
    /// rec18/19/24 class) is a HOLE: it must be BOUNDED (a blunt "defer every read to the next show" is
    /// unfaithful — a new window's discovery lands in ~ms, not many actions later — and produces false
    /// failures; verified). See the spec's "Holes".
    enum Ordering: CaseIterable {
        case inOrder            // forward — the baseline (reads land promptly, in sequence)
        case reversed           // reverse landing order
        case settleFirst        // the Space re-query + phantom pass land BEFORE the discovery/title reads
        func order(_ units: [[TestReducerRunner.Step]]) -> [[TestReducerRunner.Step]] {
            switch self {
            case .inOrder: return units
            case .reversed: return units.reversed()
            case .settleFirst:
                guard units.count >= 2 else { return units }
                return Array(units.suffix(2)) + units.dropLast(2)
            }
        }
    }

    /// The SECOND fuzz axis: which half of a Space HANDOVER arrives first. A tab switch is one window leaving
    /// a Space (1326) and another joining it (1325), and those are two separate WindowServer datagrams. Our
    /// notify proc runs on whichever thread snarfs each one and then hops to main
    /// (`WindowServerEvents.notifyProc`), so nothing in the delivery path pins their relative order. The live
    /// captures show both: a fullscreen tab switch arrived JOIN-first, the outgoing tab's 1326 lagging
    /// (`RealWorldScenariosTests.fullscreenTabSwitchEvents`), while moving a window between Spaces arrived
    /// LEAVE-first. The model emits one canonical order per action; this axis replays the other,
    /// so a rule that quietly depends on the pair arriving one way round fails here rather than in the field.
    ///
    /// A HANDOVER is defined narrowly, and the definition is the whole design: **two DIFFERENT wids, opposite
    /// directions, the SAME Space**. That is one window taking another's place on a Space, which is the only
    /// thing a tab switch can look like from the WindowServer. Two other membership shapes are deliberately
    /// left alone:
    /// - the SAME wid leaving one Space and joining another is a window MOVING (entering fullscreen), not a
    ///   handover. Swapping it makes the window transiently Space-less, and the first version of this axis
    ///   did exactly that: 10 of 22 scenarios "failed", every one of them a fullscreen transition the model
    ///   has no settle for. Rule out the model first — that was the model, or rather this axis, being wrong.
    /// - the create→leave order of a new tab, which IS guaranteed (the new tab is what backgrounds the old,
    ///   so its 811 precedes the old tab's 1326, `RealWorldScenariosTests`). Permuting a guaranteed order
    ///   manufactures races the OS never delivers, and each one costs a triage.
    enum HandoverOrder: CaseIterable {
        case asEmitted
        case swapped
        func order(_ steps: [TestReducerRunner.Step]) -> [TestReducerRunner.Step] {
            guard self == .swapped else { return steps }
            var out = steps
            var swapped = Set<Int>()
            let slots = steps.indices.filter { membership(steps[$0]) != nil }
            for (n, i) in slots.enumerated() {
                guard !swapped.contains(i), let a = membership(steps[i]) else { continue }
                for j in slots[(n + 1)...] {
                    guard !swapped.contains(j), let b = membership(steps[j]),
                          a.spaceId == b.spaceId, a.wid != b.wid, a.added != b.added else { continue }
                    // The TIMESTAMPS stay in their slots and only the payloads move: `now` is stamped at
                    // DELIVERY (`WindowServerEvents.route` reads the clock when it handles the datagram),
                    // not when the WindowServer emitted it. Carrying each event's own `now` along with it
                    // would hand the reducer a clock that runs backwards — not a race the app can ever
                    // see — and the recency windows it drives (`hadRecentWindowCreate`, the minted-tab
                    // pairing) would be measured against a negative interval.
                    out[i] = rebuilt(b, now: a.now)
                    out[j] = rebuilt(a, now: b.now)
                    swapped.insert(i)
                    swapped.insert(j)
                    break
                }
            }
            return out
        }
        private func rebuilt(_ m: (wid: CGWindowID, spaceId: UInt64, added: Bool, now: TimeInterval,
                                   inSpaceTransition: Bool), now: TimeInterval) -> TestReducerRunner.Step {
            .input(.spaceMembershipChanged(wid: m.wid, spaceId: m.spaceId, added: m.added, now: now,
                                           inSpaceTransition: m.inSpaceTransition))
        }
        private func membership(_ step: TestReducerRunner.Step)
                -> (wid: CGWindowID, spaceId: UInt64, added: Bool, now: TimeInterval, inSpaceTransition: Bool)? {
            guard case .input(let input) = step,
                  case .spaceMembershipChanged(let wid, let spaceId, let added, let now, let inTransition) = input
            else { return nil }
            return (wid, spaceId, added, now, inTransition)
        }
    }

    /// The THIRD axis: an ordinary AX read landing LATE — after the user has already done the next thing.
    /// This is the rec18/rec19 class, and it was the corpus's oldest hole: reads have always landed inside
    /// their own action, so a read could never be stale by the time it applied. Live, they can be very stale —
    /// rec18's queued titles read landed ~800ms after the click that superseded it, and treating the reader as
    /// the current active ejected the REAL active from its own group.
    ///
    /// BOUNDED to the TITLES read, one action deep, which is the shape the spec's earlier attempt lacked: a
    /// blunt "defer every read to the next show" was tried and REVERTED as unfaithful (a discovery lands in
    /// ~ms, not many actions later) after failing 7 of 8 scenarios falsely. The titles read is the one that is
    /// genuinely queued behind `AXCallScheduler`, and it is the one the recording caught landing late.
    enum LateRead: CaseIterable {
        case prompt
        case titlesOneActionLate
        func isTitleRead(_ unit: [TestReducerRunner.Step]) -> Bool {
            unit.contains { step in
                if case .input(let i) = step, case .titleAndTabsRead = i { return true }
                return false
            }
        }
    }

    private(set) var model: TestInteractionModel
    let runner: TestReducerRunner
    private let ordering: Ordering
    private let handoverOrder: HandoverOrder
    private let lateRead: LateRead
    /// title-read units held back from an earlier action, landing at the end of this one
    private var deferredReads = [[TestReducerRunner.Step]]()
    /// A Space transition from the previous action, settling during THIS one (by window identity — the wid
    /// it settles onto is decided when it fires).
    private var settling = [Int]()

    /// `preexisting` is the COLD-START condition: windows that already existed when AltTab launched, seeded
    /// into the world without emitting a single event. Every other scenario starts from nothing and watches
    /// every window from birth, which is the one condition under which any history-based detector looks
    /// perfect — the real world hands us a Finder window that has had six tabs since before we were running.
    init(ordering: Ordering = .inOrder, handoverOrder: HandoverOrder = .asEmitted,
         lateRead: LateRead = .prompt, duplicateTitles: Bool = false, reusesTabWindows: Bool = true,
         tabBarResizesWindow: Bool = false, composedWindowTitles: Bool = false,
         preexisting: [TestInteractionModel.PreexistingWindow] = []) {
        self.ordering = ordering
        self.handoverOrder = handoverOrder
        self.lateRead = lateRead
        model = TestInteractionModel(duplicateTitles: duplicateTitles, reusesTabWindows: reusesTabWindows,
                                     tabBarResizesWindow: tabBarResizesWindow,
                                     composedWindowTitles: composedWindowTitles)
        model.seed(preexisting)
        var s = TrackedWindowState()
        s.visibleSpaces = [model.windowedSpace]
        s.currentSpaceId = model.windowedSpace
        s.spaceIndexById = [model.windowedSpace: 1]
        // A pre-existing fullscreen window's Space is part of the topology AltTab reads at launch, even
        // though no transition of ours ever created it.
        for w in model.world where w.isFullscreen { s.spaceIndexById[w.space] = 2 }
        runner = TestReducerRunner(initial: s)
    }

    /// Perform one action: its ordered (synchronous) steps, then its read units in the ordering, and LAST
    /// whatever the previous action deferred into this one. The deferred units stay out of the ordering on
    /// purpose — they are a slow transition SETTLING, so they close the gap by definition; landing them
    /// earlier would model a transition that ended before it ended. Everything this action reads therefore
    /// lands inside the gap, which is the rec24c situation: summon the switcher mid-Space-switch and its
    /// reads all see the transitioning window as Space-less.
    func perform(_ action: TestUserAction) {
        let events = model.apply(action)
        run(unit: handoverOrder.order(events.ordered))
        var units = ordering.order(events.readUnits)
        var holdBack = [[TestReducerRunner.Step]]()
        if lateRead == .titlesOneActionLate {
            holdBack = units.filter { lateRead.isTitleRead($0) }
            units = units.filter { !lateRead.isTitleRead($0) }
        }
        for unit in units { run(unit: unit) }
        // reads held back by the PREVIOUS action land now, against a model the user has moved on from
        let overdue = deferredReads
        deferredReads = holdBack
        for unit in overdue { run(unit: unit) }
        // settle the transitions queued by EARLIER actions (not one started by this one — it straddles the
        // next action, which is the whole point of the deferral)
        let due = settling
        settling = []
        for id in due { run(unit: model.spaceTransitionSettleSteps(for: id)) }
        if let started = events.settlingWindow { settling.append(started) }
    }

    /// A unit is ATOMIC to the vanish check. Its steps model ONE thing the app does in one dispatch — a
    /// discovery is a `.track` plus its `.discoveryLanded`, and between those two the new window is appended
    /// but not yet grouped, so mid-unit every new tab looks like a second tile. That is an artifact of how
    /// the model spells a read out, not a state the app is ever in.
    private func run(unit: [TestReducerRunner.Step]) {
        runner.widsInSpaceTransition = model.windowsInSpaceTransition
        for s in unit { runner.perform(s) }
        lastUnit = unit.map { "\($0)" }.joined(separator: " | ")
        checkNothingVanished()
        checkNoIconFlash()
    }
    private var lastUnit = "(initial)"

    /// **A tile may never vanish.** Checked after every UNIT, because the bugs this catches are TRANSIENTS —
    /// the tile came back a beat later, so the settled state at the end of the scenario looks perfect (rec24:
    /// the group's tile disappeared for ~800ms mid-switch; rec24e: ~1s). Deliberately weaker than the
    /// end-of-run property: it does NOT demand that the ACTIVE tab be the one shown, because mid-switch the
    /// outgoing tab is legitimately held as the visible one — it demands only that SOME tile stands for the
    /// window. A window AltTab has never tracked doesn't count (it can't show what it hasn't discovered), nor
    /// does one the OS is currently moving between Spaces.
    private func checkNothingVanished() {
        guard vanishFailures.isEmpty else { return }
        for w in model.world where !model.windowsInSpaceTransition.contains(w.activeWid) {
            let known = w.allWids.filter { runner.state.window($0) != nil }
            guard !known.isEmpty else { continue }
            let shown = known.filter { wid in
                guard let mw = runner.state.window(wid) else { return false }
                return !runner.state.isTabbed(mw) && !runner.state.isPhantom(mw)
            }
            if shown.count == 1 {
                everShown.insert(w.identity)
                continue
            }
            // A window that has NEVER had a tile is not vanishing — it is still being discovered. At cold
            // start the launch pass tracks a window's members in whatever order its AX reads land, and
            // landing a background tab first leaves the window tracked-but-not-yet-showable for a beat.
            // Reading that as a vanish blamed the app for a tile it had not had the chance to draw yet.
            // Only the ZERO case is gated: a window showing TWO tiles is a defect whenever it happens.
            if shown.isEmpty && !everShown.contains(w.identity) { continue }
            vanishFailures.append("window #\(w.identity) (\(w.tabs.count) tab(s), fullscreen=\(w.isFullscreen)) "
                + "showed \(shown.count) tiles \(shown) (tracked wids \(known)) — a tile must never vanish or "
                + "double, even for a beat — right after: \(lastUnit.prefix(150))\n" + debugState())
            return   // first vanish only: everything after it is downstream noise
        }
    }
    private var vanishFailures = [String]()
    /// Windows that have had a tile at least once — what makes "vanish" mean something. See above.
    private var everShown = Set<Int>()

    /// **A tile never falls back to the app icon once the window had pixels.** `TileView` draws the app icon
    /// exactly when `thumbnail == nil`, so a window whose tile is handed to a wid with no capture yet FLASHES
    /// — screenshot, icon, screenshot — even though the tile itself never disappears. That is a distinct
    /// defect from the vanish, invisible to every other check here, and the one the user reported after the
    /// vanish was fixed. Only counts once some wid of the window HAS been captured: before that there is
    /// legitimately nothing to draw.
    private func checkNoIconFlash() {
        guard iconFlashFailures.isEmpty else { return }
        for w in model.world {
            let mine = w.allWids.compactMap { runner.state.window($0) }
            guard mine.contains(where: { $0.hasThumbnail }) else { continue }
            let shown = mine.filter { !runner.state.isTabbed($0) && !runner.state.isPhantom($0) }
            for tile in shown where !tile.hasThumbnail {
                iconFlashFailures.append("window #\(w.identity) shows wid \(tile.wid ?? 0) with NO thumbnail "
                    + "while a sibling still has one — the tile flashes the app icon; the incoming wid should "
                    + "inherit the outgoing one's pixels — right after: \(lastUnit.prefix(120))")
                return
            }
        }
    }
    private var iconFlashFailures = [String]()

    /// Run a whole scenario, then drain anything the last action deferred — ground truth is a STEADY-state
    /// property, so the scenario must be allowed to settle before it is checked.
    @discardableResult
    func run(_ scenario: TestScenario) -> TestScenarioSimulator {
        for action in scenario { perform(action) }
        for id in settling { run(unit: model.spaceTransitionSettleSteps(for: id)) }
        settling = []
        // a held-back read still has to land: ground truth is a SETTLED property, and a read in flight at the
        // end of the scenario would be judged as though the app had chosen never to apply it
        for unit in deferredReads { run(unit: unit) }
        deferredReads = []
        return self
    }

    // MARK: - ground truth (checked at steady state, after a `show` settles)

    /// Failures = the runner's per-frame + convergence invariants, plus the ground-truth count property.
    ///
    /// `requireCompleteGroups` adds the third property: every tracked tab of one window is in ONE group with
    /// the others. Off by default because the tile count — the property the user actually sees — is satisfied
    /// either way: an un-grouped background tab is Space-less, therefore phantom, therefore hidden, so a
    /// window whose tabs were never linked still shows exactly one tile and passes. That makes the count
    /// property BLIND to whether tab detection worked at all, which is fine for the churn scenarios (they
    /// exist to catch tiles vanishing) and not fine for the cold-start ones (they exist to ask whether the
    /// groups were ever learned). It is also what "Group tabs: separate window for each tab" renders from,
    /// so a group that never forms is a user-visible defect there even when the default mode looks perfect.
    func groundTruthFailures(requireCompleteGroups: Bool = false) -> [String] {
        var failures = runner.violations + vanishFailures + iconFlashFailures
        for w in model.world {
            let ownWids = Set(w.allWids)
            let shown = runner.state.windows.filter { mw in
                mw.wid.map { ownWids.contains($0) } ?? false
                    && !runner.state.isTabbed(mw) && !runner.state.isPhantom(mw)
            }.compactMap { $0.wid }
            if shown != [w.activeWid] {
                failures.append("window #\(w.identity) (pid \(w.pid), \(w.tabs.count) tab(s), \(w.staleWids.count) stale, fullscreen=\(w.isFullscreen)) shows \(shown), must be exactly [\(w.activeWid)] (its active tab)")
            }
        }
        for (gid, wids) in runner.state.groups.membersByGroup {
            let identities = Set(wids.compactMap { wid in model.world.first { $0.allWids.contains(wid) }?.identity })
            if identities.count > 1 {
                failures.append("group g\(gid) spans \(identities.count) real windows \(identities.sorted()) — a group must be tabs of ONE window")
            }
        }
        if requireCompleteGroups {
            // LIVE tabs only: a stale wid left over from a minted switch is a corpse the OS still hands back,
            // and whether it stays linked to the group it belonged to is bookkeeping, not something the user
            // can see.
            for w in model.world where w.tabs.count > 1 {
                let tracked = w.tabs.map { $0.wid }.filter { runner.state.window($0) != nil }
                guard tracked.count > 1 else { continue }
                let gids = Set(tracked.map { runner.state.groups.groupId(of: $0) })
                if gids.count > 1 || gids.first == .some(nil) {
                    failures.append("window #\(w.identity) (\(w.tabs.count) tab(s), fullscreen=\(w.isFullscreen)) has "
                        + "its tracked tabs \(tracked) in groups \(tracked.map { runner.state.groups.groupId(of: $0) }) "
                        + "— every tab of one window belongs in ONE group")
                }
            }
        }
        if !failures.isEmpty { failures.append(debugState()) }
        return failures
    }

    private func debugState() -> String {
        let groups = runner.state.groups.membersByGroup.map { gid, wids in
            "g\(gid)=\(wids.sorted())rep\(runner.state.groups.representativeByGroup[gid] ?? 0)"
        }.sorted().joined(separator: " ")
        let wins = runner.state.windows.sorted { ($0.wid ?? 0) < ($1.wid ?? 0) }.map { w -> String in
            let wid = w.wid ?? 0
            return "\(wid)\(runner.state.isTabbed(w) ? "t" : "")\(runner.state.isPhantom(w) ? "p" : "")\(w.isFullscreen ? "f" : "")sp\(w.spaceIds)"
        }.joined(separator: " ")
        let truth = model.world.map { "#\($0.identity):tabs\($0.tabs.map { $0.wid })act\($0.activeWid)fs\($0.isFullscreen)sp\($0.space)" }.joined(separator: " ")
        return "  MODEL groups[\(groups)] wins[\(wins)]\n  TRUTH [\(truth)]"
    }

    // MARK: - running a scenario under ALL orderings (the fuzz)

    /// Run `scenario` under every combination of the two axes — read-landing `Ordering` × `HandoverOrder` —
    /// and return the first that breaks, or nil if all stay correct. One written scenario → many event
    /// interleavings.
    static func fuzzFailure(_ scenario: TestScenario, duplicateTitles: Bool = false,
                            reusesTabWindows: Bool = true, tabBarResizesWindow: Bool = false,
                            composedWindowTitles: Bool = false,
                            preexisting: [TestInteractionModel.PreexistingWindow] = [],
                            requireCompleteGroups: Bool = false)
            -> (ordering: Ordering, handover: HandoverOrder, late: LateRead, failures: [String])? {
        for ordering in Ordering.allCases {
            for handover in HandoverOrder.allCases {
                for late in LateRead.allCases {
                    let sim = TestScenarioSimulator(ordering: ordering, handoverOrder: handover, lateRead: late,
                                                    duplicateTitles: duplicateTitles,
                                                    reusesTabWindows: reusesTabWindows,
                                                    tabBarResizesWindow: tabBarResizesWindow,
                                                    composedWindowTitles: composedWindowTitles,
                                                    preexisting: preexisting)
                    sim.run(scenario)
                    let failures = sim.groundTruthFailures(requireCompleteGroups: requireCompleteGroups)
                    if !failures.isEmpty { return (ordering, handover, late, failures) }
                }
            }
        }
        return nil
    }
}
