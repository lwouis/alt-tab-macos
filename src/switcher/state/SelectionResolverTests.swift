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
                   minimized: Bool = false, windowless: Bool = false,
                   appearedAfterSummon: Bool = false) -> SelectionWindow {
        SelectionWindow(id: id, visible: visible, lastFocusOrder: focusOrder,
                        isMinimized: minimized, isWindowlessApp: windowless,
                        appearedAfterSummon: appearedAfterSummon)
    }

    /// Mid-session refresh with most knobs in their default position. The test customizes only
    /// what its scenario cares about.
    private func inputs(list: [SelectionWindow],
                       selectedIndex: Int = 0,
                       selectedTarget: String? = nil,
                       useLastFocusedRule: Bool = false,
                       // defaults to true so the existing target-preservation cases read as what they model:
                       // a target the USER picked. The default-selection cases pass false explicitly.
                       userPickedSelection: Bool = true,
                       restoreDefaultOnSearchClear: Bool = false,
                       bestMatchOnSearchChange: Bool = false,
                       // defaults to "the list is the length it was at the summon", i.e. nothing arrived —
                       // the cases about a window appearing behind the switcher pass the shorter count.
                       visibleCountAtSummon: Int? = nil,
                       // defaults to the ordinary case: the window the user is on is tile 0. The `Non-active
                       // apps` cases (F) pass false — there the current window is filtered out of the list.
                       currentWindowIsDrawn: Bool = true) -> SelectionInputs {
        SelectionInputs(list: list,
                        selectedIndex: selectedIndex,
                        selectedTarget: selectedTarget,
                        useLastFocusedRule: useLastFocusedRule,
                        visibleCountAtSummon: visibleCountAtSummon ?? list.filter { $0.visible }.count,
                        userPickedSelection: userPickedSelection,
                        restoreDefaultOnSearchClear: restoreDefaultOnSearchClear,
                        bestMatchOnSearchChange: bestMatchOnSearchChange,
                        currentWindowIsDrawn: currentWindowIsDrawn)
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

    /// A7. The DEFAULT selection keeps tracking the model until the user touches it. Captured live: the
    /// switcher opens while the window set is still settling (tabs grouping, Spaces settling), so the "second
    /// visible" of that instant isn't the one that ends up there. The default must be re-derived, NOT locked
    /// onto whatever occupied the slot mid-churn.
    func testDefaultSelectionRetracksModelUntilUserPicks() {
        // Mid-churn the real 2nd window was hidden, so the default landed on "other" at slot 2 and became the
        // target. Now the model has settled and "prev" is the 2nd visible — the default must move to it.
        let settled = [w("current"), w("prev"), w("other")]
        let i = inputs(list: settled, selectedIndex: 2, selectedTarget: "other", userPickedSelection: false)
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(1),
                       "an untouched default must re-derive, not follow the window it happened to land on")
    }

    /// A8. The same target, but the USER chose it — now it is a commitment and must be followed (#5665).
    func testUserPickedTargetIsFollowedNotRederived() {
        let settled = [w("current"), w("prev"), w("other")]
        let i = inputs(list: settled, selectedIndex: 2, selectedTarget: "other", userPickedSelection: true)
        XCTAssertEqual(SelectionResolver.decide(i), .selectAt(2))
    }

    /// A9. The captured failure end-to-end: the default locked onto a window that then slid down the list as
    /// the model settled, dragging the highlight to a nonsense slot. Re-deriving keeps it on the 2nd visible.
    func testDefaultDoesNotTrailAWindowThatSlidDownTheList() {
        // "textedit" was the 2nd visible mid-churn (slot 2, since slot 1 was hidden); once the Finder windows
        // resolved it sits at slot 5 — following it there is exactly the bug.
        let settled = [w("finderA"), w("finderB"), w("chrome"), w("slack"), w("claude"), w("textedit")]
        let i = inputs(list: settled, selectedIndex: 2, selectedTarget: "textedit", userPickedSelection: false)
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

    // MARK: - F. The current window is not in the drawn list (#5941)

    /// F1. `Apps to show: Non-active apps`, the user is on VS Code window V1 and the list draws Chrome's two
    /// windows. The front tile is ALREADY the window they were on before, so that is where the default
    /// belongs — stepping over it hands them C2, a window they never asked for.
    func testInitialPickCurrentWindowFilteredOutLandsOnTheFrontTile() {
        let list = [w("C1"), w("C2")]
        let i = inputs(list: list, currentWindowIsDrawn: false)
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(0))
    }

    /// F2. The other half of #5941: having landed on C1, the same shortcut must come BACK to V1. Chrome is
    /// the active app now, so the list draws VS Code's windows and the front one is V1. Without the fix each
    /// press walks one window further away and the two-window toggle never returns.
    func testInitialPickCurrentWindowFilteredOutTogglesBackToWhereItCameFrom() {
        let list = [w("V1"), w("V2")]
        let i = inputs(list: list, currentWindowIsDrawn: false)
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(0))
    }

    /// F3. The control for F1, same list shape: while the current window IS drawn (every filter but
    /// `Non-active apps`), the default still steps over tile 0. This pairing is what pins the fix to the
    /// flag rather than to the list.
    func testInitialPickCurrentWindowDrawnStillStepsOverTheFrontTile() {
        let list = [w("C1"), w("C2")]
        XCTAssertEqual(SelectionResolver.decide(inputs(list: list)), .resetThenSelect(1))
    }

    /// F4. One other-app window, current window filtered out — land on it rather than wrapping onto nothing.
    func testInitialPickCurrentWindowFilteredOutWithASingleTile() {
        let i = inputs(list: [w("only")], currentWindowIsDrawn: false)
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(0))
    }

    /// F5. Newcomers are still stepped over when the current window is filtered out: a window created and
    /// focused behind the switcher takes tile 0 and pushes the window the user summoned for to tile 1. The
    /// two rules compose — one steps over what ARRIVED, the other over the window you are ON.
    func testInitialPickStepsOverANewcomerEvenWhenTheCurrentWindowIsFilteredOut() {
        let list = [w("new", appearedAfterSummon: true), w("previous"), w("other")]
        let i = inputs(list: list, visibleCountAtSummon: 2, currentWindowIsDrawn: false)
        XCTAssertEqual(SelectionResolver.initialPickIndex(i), 1)
    }

    /// F6. …and a newcomer that REPLACED a window that left keeps the pick on the front tile, since the list
    /// never grew. Same replacement rule as with the current window drawn, one tile earlier.
    func testInitialPickDoesNotStepOverAReplacementWhenTheCurrentWindowIsFilteredOut() {
        let list = [w("incoming", appearedAfterSummon: true), w("previous"), w("other")]
        let i = inputs(list: list, visibleCountAtSummon: 3, currentWindowIsDrawn: false)
        XCTAssertEqual(SelectionResolver.initialPickIndex(i), 0)
    }

    /// F7. Every drawn window arrived after the summon, so there is no as-of-the-summon list to answer from.
    /// The fallback must still respect the flag: land on the front tile, never on nothing.
    func testInitialPickFallsBackToTheFrontTileWhenSteppingOverLeavesNothing() {
        let list = [w("a", appearedAfterSummon: true), w("b", appearedAfterSummon: true)]
        let i = inputs(list: list, visibleCountAtSummon: 0, currentWindowIsDrawn: false)
        XCTAssertEqual(SelectionResolver.initialPickIndex(i), 0)
    }

    /// F8. Hidden rows sit in the MRU ahead of the first DRAWN tile (a grouped background tab). The pick
    /// counts drawn tiles, so it lands on the first drawn one, not on raw index 0.
    func testInitialPickCurrentWindowFilteredOutCountsDrawnTilesNotIndexes() {
        let list = [w("groupedTab", visible: false), w("C1"), w("C2")]
        let i = inputs(list: list, currentWindowIsDrawn: false)
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(1))
    }

    /// F9. `Window order: Alphabetical` never counted tiles in the first place — it picks the most recently
    /// focused drawn window, which is already the right answer when the current window is filtered out. The
    /// flag must leave that path alone.
    func testInitialPickLastFocusedRuleIsUnaffectedByTheFlag() {
        let list = [w("a", focusOrder: 5), w("b", focusOrder: 0), w("c", focusOrder: 3)]
        let drawn = inputs(list: list, useLastFocusedRule: true)
        let filtered = inputs(list: list, useLastFocusedRule: true, currentWindowIsDrawn: false)
        XCTAssertEqual(SelectionResolver.decide(drawn), .resetThenSelect(1))
        XCTAssertEqual(SelectionResolver.decide(filtered), .resetThenSelect(1))
    }

    /// F10. Clearing a search query restores the default pick, and the restored default is the #5941 one.
    func testSearchRestoreDefaultOnClearHonorsTheFilteredOutCurrentWindow() {
        let list = [w("C1"), w("C2"), w("C3")]
        let i = inputs(list: list, selectedIndex: 2, selectedTarget: "C3",
                       restoreDefaultOnSearchClear: true, currentWindowIsDrawn: false)
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(0))
    }

    /// F11. Once the USER has moved the selection it is a commitment, followed by id however the list
    /// reorders (#5665). The flag only ever answers where the DEFAULT starts.
    func testUserPickedTargetIsFollowedWhenTheCurrentWindowIsFilteredOut() {
        let list = [w("C1"), w("C2"), w("C3")]
        let i = inputs(list: list, selectedIndex: 2, selectedTarget: "C3", currentWindowIsDrawn: false)
        XCTAssertEqual(SelectionResolver.decide(i), .selectAt(2))
    }

    /// F12. The both-top-minimized edge lands on tile 0 either way — it never stepped over anything.
    func testInitialPickTopTwoMinimizedIsUnaffectedByTheFlag() {
        let list = [w("a", minimized: true), w("b", minimized: true), w("c")]
        let i = inputs(list: list, currentWindowIsDrawn: false)
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(0))
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

    /// `secondVisibleIndex` empty / single / multi-visible behavior.
    /// A window created and focused behind the open switcher takes tile 0 — the list shows the truth — but
    /// the user pressed the shortcut to get back to the window they were on, and that must not change under
    /// them. Without this, `[new, current, previous]` re-derived the default to slot 1 and committed to
    /// `current`, i.e. alt-tab landed on the window you were already on.
    func testInitialPickStepsOverWindowThatAppearedAfterSummon() {
        let list = [w("new", appearedAfterSummon: true), w("current"), w("previous")]
        XCTAssertEqual(SelectionResolver.initialPickIndex(inputs(list: list, visibleCountAtSummon: 2)), 2)
    }

    /// A newcomer that REPLACED a window instead of joining the list — the live Finder case: switching a tab
    /// brings in a window the model had never tracked (it takes tile 0 and is focused) while the tab it
    /// replaced leaves the drawn list. Nothing moved down, so nothing is stepped over: tile 1 is still the
    /// other Finder window, and stepping over aimed one tile past it at an unrelated app.
    func testInitialPickDoesNotStepOverANewcomerThatReplacedADrawnWindow() {
        let list = [w("incomingTab", appearedAfterSummon: true), w("previous"), w("other")]
        XCTAssertEqual(SelectionResolver.initialPickIndex(inputs(list: list, visibleCountAtSummon: 3)), 1)
    }

    /// Same shape one beat earlier: the model still had the old tab in front when the shortcut was pressed,
    /// and both the tab switch AND the focus change land while the switcher is open. The list length is
    /// unchanged, so the pick lands on the window behind the newly-focused one rather than past it.
    func testInitialPickDoesNotStepOverANewcomerThatTookFocusFromAWindowThatLeft() {
        let list = [w("incomingTabOfOtherWindow", appearedAfterSummon: true), w("previous"), w("other")]
        XCTAssertEqual(SelectionResolver.initialPickIndex(inputs(list: list, visibleCountAtSummon: 3)), 1)
    }

    /// Two newcomers, one of them a replacement: only the arrival is stepped over, and only from the front.
    func testInitialPickStepsOverOnlyAsManyNewcomersAsTheListGained() {
        let list = [w("new", appearedAfterSummon: true), w("incomingTab", appearedAfterSummon: true),
                    w("previous"), w("other")]
        XCTAssertEqual(SelectionResolver.initialPickIndex(inputs(list: list, visibleCountAtSummon: 3)), 2)
    }

    /// A newcomer appended at the BACK (created but never focused) lengthens the list without disturbing the
    /// front of it, so the pick must not step over the current window to pay for it.
    func testInitialPickDoesNotStepOverAWindowAppendedBehindTheCurrentOne() {
        let list = [w("current"), w("previous"), w("new", appearedAfterSummon: true)]
        XCTAssertEqual(SelectionResolver.initialPickIndex(inputs(list: list, visibleCountAtSummon: 2)), 1)
    }

    /// The same shape, but the newcomer is not flagged: this is a late read telling us who was ALREADY
    /// frontmost when the shortcut was pressed. That is news about the past, so the pick re-derives over the
    /// corrected order rather than stepping over it.
    func testInitialPickFollowsALateCorrection() {
        let list = [w("trueFrontmost"), w("current"), w("previous")]
        XCTAssertEqual(SelectionResolver.initialPickIndex(inputs(list: list)), 1)
    }

    /// Stepping over must never leave the switcher with nothing selected.
    func testInitialPickFallsBackWhenSteppingOverLeavesNothing() {
        let list = [w("a", appearedAfterSummon: true), w("b", appearedAfterSummon: true)]
        XCTAssertEqual(SelectionResolver.initialPickIndex(inputs(list: list, visibleCountAtSummon: 0)), 1)
    }

    func testCycleFromZeroBehavior() {
        XCTAssertNil(SelectionResolver.secondVisibleIndex([]))
        XCTAssertNil(SelectionResolver.secondVisibleIndex([w("a", visible: false)]))
        // Single visible — wraps back to 0.
        XCTAssertEqual(SelectionResolver.secondVisibleIndex([w("a")]), 0)
        // Two visible — advances to 1.
        XCTAssertEqual(SelectionResolver.secondVisibleIndex([w("a"), w("b")]), 1)
        // First invisible and only one window visible — wraps back to that one.
        XCTAssertEqual(SelectionResolver.secondVisibleIndex([w("a", visible: false), w("b")]), 1)
        // A HIDDEN window at index 0 must not shift the pick onto the CURRENT window. Captured live: a
        // background tab is fronted in the MRU the moment it's discovered, then hidden once grouped, so
        // index 0 is hidden and index 1 is the current window — selection belongs on the one behind it.
        XCTAssertEqual(SelectionResolver.secondVisibleIndex(
            [w("hiddenTab", visible: false), w("current"), w("previous")]), 2)
        // Several hidden tabs ahead of the current window (a tab burst) — still the window behind it.
        XCTAssertEqual(SelectionResolver.secondVisibleIndex(
            [w("t1", visible: false), w("t2", visible: false), w("current"), w("previous")]), 3)
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

    // MARK: - G. Frontmost app owns no drawn tile — filtered out vs has no windows (#5960)

    private func fw(windowless: Bool = false, drawn: Bool) -> FrontmostAppWindow {
        FrontmostAppWindow(isWindowlessApp: windowless, isDrawn: drawn)
    }

    /// #5941, unchanged: the frontmost app's windows exist but a filter dropped them, so the user IS on one
    /// of them and the front tile is already the previous window.
    func testCurrentWindowIsDrawnFalseWhenTheAppsWindowsAreFilteredOut() {
        XCTAssertFalse(SelectionResolver.currentWindowIsDrawn([fw(drawn: false), fw(drawn: false)]))
    }

    /// #5960: the user closed the frontmost app's last window, so it has nothing to draw. Nothing was
    /// filtered — the window they are looking at belongs to another app, at the front of the MRU — so the
    /// ordinary rule applies and the front tile gets stepped over.
    func testCurrentWindowIsDrawnTrueWhenTheAppHasNoWindows() {
        XCTAssertTrue(SelectionResolver.currentWindowIsDrawn([]))
    }

    /// Same, when the app still occupies a windowless placeholder tile: a placeholder is never a window the
    /// user is looking at, so it can't stand in for one the filters dropped.
    func testCurrentWindowIsDrawnTrueWhenTheAppOnlyHasAWindowlessTile() {
        XCTAssertTrue(SelectionResolver.currentWindowIsDrawn([fw(windowless: true, drawn: true)]))
        XCTAssertTrue(SelectionResolver.currentWindowIsDrawn([fw(windowless: true, drawn: false)]))
    }

    /// The ordinary case: at least one of the app's real windows is drawn.
    func testCurrentWindowIsDrawnTrueWhenOneOfTheAppsWindowsIsDrawn() {
        XCTAssertTrue(SelectionResolver.currentWindowIsDrawn([fw(drawn: false), fw(drawn: true)]))
    }

    /// A windowless placeholder alongside real filtered-out windows must not flip the answer: the real
    /// windows are what the filters dropped, so this is still the #5941 case.
    func testCurrentWindowIsDrawnFalseWhenRealWindowsAreFilteredOutBesideAPlaceholder() {
        XCTAssertFalse(SelectionResolver.currentWindowIsDrawn([fw(windowless: true, drawn: true), fw(drawn: false)]))
    }

    /// #5960 end to end. Terminal frontmost over Chrome/Google and Chrome/YouTube; close Terminal's last
    /// window and summon. Terminal contributes no window, so the shell now answers `true` and the pick steps
    /// over the front tile to Chrome/YouTube. Answering `false` selected Chrome/Google — the window already
    /// on screen — so the shortcut appeared to do nothing.
    func testInitialPickStepsOverFrontTileAfterTheFrontmostAppLostItsLastWindow() {
        let list = [w("chromeGoogle"), w("chromeYouTube")]
        let drawn = SelectionResolver.currentWindowIsDrawn([])
        let i = inputs(list: list, currentWindowIsDrawn: drawn)
        XCTAssertEqual(SelectionResolver.decide(i), .resetThenSelect(1))
    }
}
