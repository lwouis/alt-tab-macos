import XCTest

/// Scenarios pinning the selection-state machine that drives which tile is highlighted while
/// the switcher is open. Each test builds a fully explicit `SelectionInputs` and asserts on the
/// `SelectionDecision` the kernel returns — no globals, no AppKit, no async. Future refactors
/// of selection must keep this suite green.
///
/// Test method names follow `test<Group><Scenario>`. Groups:
///   - InitialPick (A): first call after the switcher opens (`selectedTarget == nil`)
///   - PreserveTarget (B): list reorders but the user's chosen tile stays selected (#5665)
///   - TargetRemoved (C): user's window closed / filtered out
///   - SearchMode (D): search filter / clear interactions
///   - EdgeCases (E): corruption, single-window flips, multi-step sequences
final class SelectionResolverTests: XCTestCase {

    // MARK: - Builders

    /// Concise window builder. Defaults model the common case: visible, non-minimized, non-windowless.
    private func w(_ id: String, focusOrder: Int = 0, visible: Bool = true,
                   minimized: Bool = false, windowless: Bool = false) -> SelectionWindow {
        SelectionWindow(id: id, visible: visible, lastFocusOrder: focusOrder,
                        isMinimized: minimized, isWindowlessApp: windowless)
    }

    /// Mid-session refresh with most knobs in their default position. The test customizes only
    /// what its scenario cares about.
    private func inputs(list: [SelectionWindow],
                       selectedIndex: Int = 0,
                       selectedTarget: String? = nil,
                       useLastFocusedRule: Bool = false,
                       restoreDefaultOnSearchClear: Bool = false,
                       bestMatchOnSearchChange: Bool = false) -> SelectionInputs {
        SelectionInputs(list: list,
                        selectedIndex: selectedIndex,
                        selectedTarget: selectedTarget,
                        useLastFocusedRule: useLastFocusedRule,
                        restoreDefaultOnSearchClear: restoreDefaultOnSearchClear,
                        bestMatchOnSearchChange: bestMatchOnSearchChange)
    }

    // MARK: - A. Initial pick (`selectedTarget == nil`)

    /// A1. No windows at all — wrapper clears `selectedTarget` / `hoveredIndex`.
    func testInitialPickEmptyList() {
        let i = inputs(list: [])
        XCTAssertEqual(SelectionResolver.decide(i), .clearTargetAndHover)
    }

    /// A2. Single visible window — cycle from 0 wraps back to 0; that's the only choice.
    func testInitialPickSingleVisible() {
        let i = inputs(list: [w("a")])
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(0))
    }

    /// A3. Default Cmd-Tab behavior: cycle off slot 0 to slot 1 ("previous app").
    func testInitialPickTwoVisibleDefaultRules() {
        let i = inputs(list: [w("a"), w("b")])
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(1))
    }

    /// A4. Edge case at Windows.swift:204 — both top windows minimized, pick index 0 instead
    /// of cycling. Behavior preserved from original (#5665 doesn't touch this).
    func testInitialPickTopTwoMinimized() {
        let i = inputs(list: [w("a", minimized: true), w("b", minimized: true), w("c")])
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(0))
    }

    /// A5. Alpha/space ordering with frontmost set — pick the lowest-`lastFocusOrder` visible
    /// non-windowless window, regardless of its slot position in the alpha-sorted list.
    func testInitialPickUseLastFocusedRule() {
        let list = [w("a", focusOrder: 5), w("b", focusOrder: 0), w("c", focusOrder: 3)]
        let i = inputs(list: list, useLastFocusedRule: true)
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(1))
    }

    /// A6. All windows filtered out (e.g. by search). Same as A1 — empty visible list.
    func testInitialPickAllInvisible() {
        let list = [w("a", visible: false), w("b", visible: false), w("c", visible: false)]
        let i = inputs(list: list)
        XCTAssertEqual(SelectionResolver.decide(i), .clearTargetAndHover)
    }

    /// A5 corollary (was E4 in the plan): windowless app entries are skipped when scanning for
    /// the lowest `lastFocusOrder` — they're not real windows the user can pick.
    func testInitialPickSkipsWindowlessInLastFocusedRule() {
        let list = [
            w("dock", focusOrder: 0, windowless: true),
            w("real", focusOrder: 1),
            w("other", focusOrder: 2),
        ]
        let i = inputs(list: list, useLastFocusedRule: true)
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(1))
    }

    // MARK: - B. Preserve target across reorders — the #5665 regression cluster

    /// B1. Trivial preservation — target's still at its index after a benign refresh.
    func testPreserveTargetSameIndex() {
        let list = [w("a", focusOrder: 0), w("b", focusOrder: 1)]
        let i = inputs(list: list, selectedIndex: 1, selectedTarget: "b")
        XCTAssertEqual(SelectionResolver.decide(i), .selectAt(1))
    }

    /// B2. #5665 regression — user picked "b" at slot 1, then Photoshop ("p") finished launching
    /// and stole focus. List reorders so p=0, a=1, b=2. The user's selection must follow "b" to
    /// slot 2. Pre-fix, the kernel re-picked from scratch instead, jumping the highlight.
    func testPreserveTargetMovedToHigherIndexAfterPhotoshopLaunch() {
        let listAfterReorder = [
            w("p", focusOrder: 0), // Photoshop just launched, top of MRU
            w("a", focusOrder: 1), // was the front app
            w("b", focusOrder: 2), // user's pick, slid down
        ]
        let i = inputs(list: listAfterReorder, selectedIndex: 1, selectedTarget: "b")
        XCTAssertEqual(SelectionResolver.decide(i), .selectAt(2),
                       "regression for #5665 — the user picked 'b'; the highlight must follow 'b' " +
                       "to its new slot, not jump back to a 'previous app' re-pick.")
    }

    /// B3. Same as B2 but the target moved DOWN the list — e.g. an app's window closed,
    /// shifting indices up.
    func testPreserveTargetMovedToLowerIndex() {
        // Before refresh: list was [x, a, b, c, target]. Mid-session: "x" closed.
        // Now: [a, b, target, c]. Target was at index 4, is now at index 2.
        let list = [w("a", focusOrder: 0), w("b", focusOrder: 1),
                    w("target", focusOrder: 2), w("c", focusOrder: 3)]
        let i = inputs(list: list, selectedIndex: 4, selectedTarget: "target")
        XCTAssertEqual(SelectionResolver.decide(i), .selectAt(2),
                       "regression for #5665 — target moved to a different slot; highlight must follow.")
    }

    /// B4. The list churns but the target happens to land at the same index.
    /// (Defensive — kernel shouldn't notice or care.)
    func testPreserveTargetIndexUnchangedByCoincidence() {
        let list = [w("x", focusOrder: 0), w("target", focusOrder: 1), w("y", focusOrder: 2)]
        let i = inputs(list: list, selectedIndex: 1, selectedTarget: "target")
        XCTAssertEqual(SelectionResolver.decide(i), .selectAt(1))
    }

    /// B5. New window appears at the END of the list — target slot is unchanged.
    func testPreserveTargetNewWindowAppended() {
        let list = [
            w("a", focusOrder: 0),
            w("b", focusOrder: 1),
            w("newly-launched", focusOrder: 99), // appended via Windows.appendWindow
        ]
        let i = inputs(list: list, selectedIndex: 1, selectedTarget: "b")
        XCTAssertEqual(SelectionResolver.decide(i), .selectAt(1))
    }

    /// B6. Multiple sequential reorders during one session — the target tracks correctly across
    /// every refresh. Simulates a chatty Electron app firing focus events repeatedly.
    func testPreserveTargetAcrossMultipleReorders() {
        // Step 1: user picks "b" at slot 1.
        let step1 = inputs(
            list: [w("a", focusOrder: 0), w("b", focusOrder: 1), w("c", focusOrder: 2)],
            selectedIndex: 1, selectedTarget: "b")
        XCTAssertEqual(SelectionResolver.decide(step1), .selectAt(1))
        // Step 2: c steals focus. List reorders: c=0, a=1, b=2. Target now at index 2.
        let step2 = inputs(
            list: [w("c", focusOrder: 0), w("a", focusOrder: 1), w("b", focusOrder: 2)],
            selectedIndex: 1, selectedTarget: "b")
        XCTAssertEqual(SelectionResolver.decide(step2), .selectAt(2))
        // Step 3: a steals focus back. List reorders: a=0, c=1, b=2. Target stays at index 2.
        let step3 = inputs(
            list: [w("a", focusOrder: 0), w("c", focusOrder: 1), w("b", focusOrder: 2)],
            selectedIndex: 2, selectedTarget: "b")
        XCTAssertEqual(SelectionResolver.decide(step3), .selectAt(2))
    }

    // MARK: - C. Target removed / no longer visible

    /// C1. User's picked window closed externally. The id is no longer in the list. Fall through
    /// to `adapt` and end on the previous `selectedIndex` (target backfill).
    func testTargetRemovedAdaptToClosestBelow() {
        // Originally: [a, b, c, d]; user picked "c" at index 2. Then "c" closed:
        let list = [w("a", focusOrder: 0), w("b", focusOrder: 1), w("d", focusOrder: 3)]
        let i = inputs(list: list, selectedIndex: 2, selectedTarget: "c")
        // visibleIndexes = [0, 1, 2]. selectedIndex (2) is in range and equals lastVisible,
        // selectedTarget != nil but lookup fails. Tail branch: ensureTargetSet(2) — list[2] is "d"
        // and the wrapper backfills the target to "d".
        XCTAssertEqual(SelectionResolver.decide(i), .ensureTargetSet(2))
    }

    /// C1 variant: original `selectedIndex` is now out of bounds for the smaller list.
    func testTargetRemovedSelectedIndexOutOfBounds() {
        // Originally 4 windows, selectedIndex=3. Then targets+others closed: only [a, b] left.
        let list = [w("a", focusOrder: 0), w("b", focusOrder: 1)]
        let i = inputs(list: list, selectedIndex: 3, selectedTarget: "d")
        // adapt: visibleIndexes=[0,1] doesn't contain 3 → closest visible < 3 is 1 → selectAt(1).
        XCTAssertEqual(SelectionResolver.decide(i), .selectAt(1))
    }

    /// C2. Target still in `list` but filtered out by `visible == false` (e.g. search match miss
    /// or app went to a non-visible space). Same flow as C1 — target lookup excludes invisible.
    func testTargetBecameInvisible() {
        let list = [w("a"), w("b", visible: false), w("c")]
        let i = inputs(list: list, selectedIndex: 1, selectedTarget: "b")
        // visibleIndexes = [0, 2]. selectedIndex (1) not in [0,2] → closest visible < 1 is 0.
        XCTAssertEqual(SelectionResolver.decide(i), .selectAt(0))
    }

    /// C3. Target removed AND list emptied — `clearTargetAndHover` path takes over.
    func testTargetRemovedAndListEmptied() {
        let i = inputs(list: [], selectedIndex: 0, selectedTarget: "gone")
        XCTAssertEqual(SelectionResolver.decide(i), .clearTargetAndHover)
    }

    /// C4. Target was at slot 0, closed; only one visible window remains.
    func testTargetRemovedOnlyOneLeft() {
        // Originally [other, target]; target closed. Now: [other].
        let list = [w("other")]
        let i = inputs(list: list, selectedIndex: 0, selectedTarget: "target")
        // visibleIndexes=[0]. selectedIndex=0 in range. selectedTarget != nil but lookup fails.
        // Tail returns ensureTargetSet(0); wrapper backfills target to "other".
        XCTAssertEqual(SelectionResolver.decide(i), .ensureTargetSet(0))
    }

    // MARK: - D. Search-mode interactions

    /// D1. User types a search query that produces a new best match — jump to firstVisible.
    func testSearchBestMatchOnSearchChange() {
        let list = [w("a", visible: false), w("b"), w("c")]
        let i = inputs(list: list, selectedIndex: 0, selectedTarget: "a",
                       bestMatchOnSearchChange: true)
        XCTAssertEqual(SelectionResolver.decide(i), .selectAt(1))
    }

    /// D2. User cleared a non-empty search query — restore the default initial pick.
    func testSearchRestoreDefaultOnClear() {
        let list = [w("a"), w("b"), w("c")]
        let i = inputs(list: list, selectedIndex: 0, selectedTarget: "a",
                       restoreDefaultOnSearchClear: true)
        // Same flow as A3 — default rules, picks index 1.
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(1))
    }

    /// D3. Target preservation works the same whether or not search is active. (Pre-fix this
    /// scenario was specifically interesting because `focusedWindowChangedWhileShowing` had a
    /// search-empty guard; with the fix the guard is irrelevant.)
    func testTargetPreservedInSearchMode() {
        let list = [w("p", focusOrder: 0), w("a", focusOrder: 1), w("b", focusOrder: 2)]
        let i = inputs(list: list, selectedIndex: 2, selectedTarget: "b")
        XCTAssertEqual(SelectionResolver.decide(i), .selectAt(2))
    }

    /// D4. Search filters out the user's pick, but other matches remain — adapt to closest.
    func testSearchTargetFilteredOutWithOthersMatching() {
        let list = [w("a"), w("b", visible: false), w("c")]
        let i = inputs(list: list, selectedIndex: 1, selectedTarget: "b")
        // visibleIndexes = [0, 2]. selectedIndex=1 not in [0,2] → closest below is 0.
        XCTAssertEqual(SelectionResolver.decide(i), .selectAt(0))
    }

    // MARK: - E. Edge cases

    /// E1. Single window in the list that becomes invisible mid-session — clear selection.
    func testEdgeSingleWindowBecomesInvisible() {
        let list = [w("only", visible: false)]
        let i = inputs(list: list, selectedIndex: 0, selectedTarget: "only")
        XCTAssertEqual(SelectionResolver.decide(i), .clearTargetAndHover)
    }

    /// E2. Target was at index 0; a new window inserts ahead, pushing it to 1. Highlight follows.
    func testEdgeNewWindowPushesTargetDown() {
        // Before: [target]. Now: [new, target].
        let list = [w("new", focusOrder: 0), w("target", focusOrder: 1)]
        let i = inputs(list: list, selectedIndex: 0, selectedTarget: "target")
        XCTAssertEqual(SelectionResolver.decide(i), .selectAt(1))
    }

    /// E3. `selectedTarget` points to an id that was never in the list (corrupt state from a
    /// stale session, or a window destroyed before refresh ran).
    func testEdgeStaleSelectedTarget() {
        let list = [w("a"), w("b"), w("c")]
        let i = inputs(list: list, selectedIndex: 1, selectedTarget: "missing")
        // target lookup fails → adapt → selectedIndex=1 in [0,1,2], in range, target was non-nil
        // so the no-target-set branch doesn't trigger; tail returns ensureTargetSet(1).
        XCTAssertEqual(SelectionResolver.decide(i), .ensureTargetSet(1))
    }

    // MARK: - Helper kernel functions

    /// `getLastFocusedOrderWindowIndex` ignores windowless apps and invisible windows.
    func testGetLastFocusedOrderWindowIndexIgnoresWindowlessAndInvisible() {
        let list = [
            w("dock", focusOrder: 0, windowless: true), // windowless: skip
            w("a", focusOrder: 1, visible: false),      // invisible: skip
            w("b", focusOrder: 2),                       // candidate
            w("c", focusOrder: 3),                       // candidate (loses on order)
        ]
        XCTAssertEqual(SelectionResolver.getLastFocusedOrderWindowIndex(list), 2)
    }

    /// `cycleFromZero` empty / single / multi-visible behavior.
    func testCycleFromZeroBehavior() {
        XCTAssertNil(SelectionResolver.cycleFromZero([]))
        XCTAssertNil(SelectionResolver.cycleFromZero([w("a", visible: false)]))
        // Single visible — wraps back to 0.
        XCTAssertEqual(SelectionResolver.cycleFromZero([w("a")]), 0)
        // Two visible — advances to 1.
        XCTAssertEqual(SelectionResolver.cycleFromZero([w("a"), w("b")]), 1)
        // First invisible — skips to next visible.
        XCTAssertEqual(SelectionResolver.cycleFromZero([w("a", visible: false), w("b")]), 1)
    }

    /// `findTarget` excludes invisible matches even when the id is present.
    func testFindTargetSkipsInvisibleMatches() {
        let list = [w("a"), w("b", visible: false), w("c")]
        XCTAssertEqual(SelectionResolver.findTarget(list, "a"), 0)
        XCTAssertNil(SelectionResolver.findTarget(list, "b"))
        XCTAssertEqual(SelectionResolver.findTarget(list, "c"), 2)
        XCTAssertNil(SelectionResolver.findTarget(list, nil))
        XCTAssertNil(SelectionResolver.findTarget(list, "missing"))
    }
}
