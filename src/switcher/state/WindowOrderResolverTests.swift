import XCTest

/// Pins the switcher's window display order: `WindowOrderResolver.isOrderedBefore`. Each test builds
/// two `OrderWindow`s (a `WindowState` snapshot + `ApplicationState` + the query-derived search
/// rank) differing in one fact and asserts the comparator's answer under the right knobs. Pure data
/// in, `Bool` out.
///
/// Groups: A search ranking · B show-at-the-end buckets · C recentlyFocused · D recentlyCreated ·
/// E alphabetical · F space · G tiebreak/symmetry.
final class WindowOrderResolverTests: XCTestCase {

    private func w(searchMatches: Bool = false, searchRelevance: Double = 0,
                   isWindowlessApp: Bool = false, isHidden: Bool = false, isMinimized: Bool = false,
                   isOnAllSpaces: Bool = false, spaceIndexes: [Int] = [],
                   lastFocusOrder: Int = 0, creationOrder: Int = 0,
                   appName: String = "App", windowTitle: String = "Title") -> OrderWindow {
        let state = WindowState(id: "w", isPhantom: false, isWindowlessApp: isWindowlessApp,
                                isFullscreen: false, isMinimized: isMinimized, isTabbed: false,
                                isOnAllSpaces: isOnAllSpaces, spaceIds: [], spaceIndexes: spaceIndexes,
                                lastFocusOrder: lastFocusOrder, creationOrder: creationOrder, title: windowTitle)
        let app = ApplicationState(pid: 0, bundleIdentifier: nil, localizedName: appName, isHidden: isHidden)
        return OrderWindow(state: state, app: app, searchMatches: searchMatches, searchRelevance: searchRelevance)
    }

    // MARK: - A. Search ranking

    func testSearchMatchedSortsBeforeUnmatched() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(searchMatches: true), w(searchMatches: false),
                                                          searchActive: true))
        XCTAssertFalse(WindowOrderResolver.isOrderedBefore(w(searchMatches: false), w(searchMatches: true),
                                                           searchActive: true))
    }

    func testSearchHigherRelevanceSortsFirst() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(searchMatches: true, searchRelevance: 2),
                                                          w(searchMatches: true, searchRelevance: 1),
                                                          searchActive: true))
    }

    func testSearchEqualRelevanceTiebreaksByLastFocusOrder() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(searchMatches: true, searchRelevance: 1, lastFocusOrder: 0),
                                                          w(searchMatches: true, searchRelevance: 1, lastFocusOrder: 1),
                                                          searchActive: true))
    }

    // MARK: - B. Show-at-the-end buckets

    func testWindowlessPushedToEndWhenConfigured() {
        XCTAssertFalse(WindowOrderResolver.isOrderedBefore(w(isWindowlessApp: true), w(isWindowlessApp: false),
                                                           windowlessAtEnd: true))
    }

    func testRealWindowBeforeWindowlessWhenConfigured() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(isWindowlessApp: false), w(isWindowlessApp: true),
                                                          windowlessAtEnd: true))
    }

    func testWindowlessNotSeparatedWhenFlagOff() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(isWindowlessApp: true, lastFocusOrder: 0),
                                                          w(isWindowlessApp: false, lastFocusOrder: 1),
                                                          windowlessAtEnd: false, sortType: .recentlyFocused))
    }

    func testHiddenPushedToEndWhenConfigured() {
        XCTAssertFalse(WindowOrderResolver.isOrderedBefore(w(isHidden: true), w(isHidden: false),
                                                           hiddenAtEnd: true))
    }

    func testMinimizedPushedToEndWhenConfigured() {
        XCTAssertFalse(WindowOrderResolver.isOrderedBefore(w(isMinimized: true), w(isMinimized: false),
                                                           minimizedAtEnd: true))
    }

    // MARK: - C. Recently focused

    func testRecentlyFocusedLowerOrderFirst() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(lastFocusOrder: 0), w(lastFocusOrder: 5),
                                                          sortType: .recentlyFocused))
    }

    // MARK: - D. Recently created

    func testRecentlyCreatedHigherCreationOrderFirst() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(creationOrder: 5), w(creationOrder: 2),
                                                          sortType: .recentlyCreated))
    }

    // MARK: - E. Alphabetical

    func testAlphabeticalByAppName() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(appName: "Aaa"), w(appName: "Bbb"),
                                                          sortType: .alphabetical))
    }

    func testAlphabeticalTitleBreaksTieWithinSameApp() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(appName: "Same", windowTitle: "Alpha"),
                                                          w(appName: "Same", windowTitle: "Beta"),
                                                          sortType: .alphabetical))
    }

    func testAlphabeticalTiebreaksByLastFocusOrder() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(lastFocusOrder: 0, appName: "Same", windowTitle: "Same"),
                                                          w(lastFocusOrder: 1, appName: "Same", windowTitle: "Same"),
                                                          sortType: .alphabetical))
    }

    // MARK: - F. Space

    func testSpaceAllSpacesWindowsFirst() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(isOnAllSpaces: true),
                                                          w(isOnAllSpaces: false, spaceIndexes: [0]),
                                                          sortType: .space))
    }

    func testSpaceLowerSpaceIndexFirst() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(spaceIndexes: [0]), w(spaceIndexes: [2]),
                                                          sortType: .space))
    }

    func testSpaceTiebreaksByAppName() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(spaceIndexes: [1], appName: "Aaa"),
                                                          w(spaceIndexes: [1], appName: "Bbb"),
                                                          sortType: .space))
    }

    /// Both windows on all spaces → no space-index ordering, fall through to alphabetical tiebreak.
    func testSpaceBothOnAllSpacesTiebreaksByAppName() {
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(w(isOnAllSpaces: true, appName: "Aaa"),
                                                          w(isOnAllSpaces: true, appName: "Bbb"),
                                                          sortType: .space))
        XCTAssertFalse(WindowOrderResolver.isOrderedBefore(w(isOnAllSpaces: true, appName: "Bbb"),
                                                           w(isOnAllSpaces: true, appName: "Aaa"),
                                                           sortType: .space))
    }

    /// Symmetric to `testSpaceAllSpacesWindowsFirst`: when only `b` is on all spaces, `a` sorts
    /// AFTER `b` (b first). The existing test covers only the "a on all spaces" side of the
    /// branch — this pins the mirrored case so the comparator can't silently regress to
    /// asymmetric behavior (which would break strict-weak-ordering and `Array.sort`).
    func testSpaceOnlyBOnAllSpacesSortsBFirst() {
        XCTAssertFalse(WindowOrderResolver.isOrderedBefore(w(isOnAllSpaces: false, spaceIndexes: [0]),
                                                           w(isOnAllSpaces: true),
                                                           sortType: .space))
    }

    func testSpaceWindowWithoutSpaceIndexSortsLast() {
        let indexed = w(spaceIndexes: [3], appName: "Bbb")
        let unindexed = w(spaceIndexes: [], appName: "Aaa")
        XCTAssertTrue(WindowOrderResolver.isOrderedBefore(indexed, unindexed, sortType: .space))
        XCTAssertFalse(WindowOrderResolver.isOrderedBefore(unindexed, indexed, sortType: .space))
    }

    // MARK: - G. Tiebreak / symmetry

    func testEqualWindowsAreNotOrderedBeforeEachOther() {
        let a = w(lastFocusOrder: 3)
        XCTAssertFalse(WindowOrderResolver.isOrderedBefore(a, a, sortType: .recentlyFocused))
    }
}

final class ApplicationRepresentativeResolverTests: XCTestCase {
    private func c(_ id: String, current: Bool = false, attended: Bool = false,
                   main: Bool = false, focus: Int = 0, creation: Int = 0)
        -> ApplicationRepresentativeCandidate {
        ApplicationRepresentativeCandidate(id: id, isCurrentAttention: current,
            isLastAttention: attended, isMainWindow: main, lastFocusOrder: focus,
            creationOrder: creation)
    }

    func testCurrentAttentionWinsEveryFallback() {
        let candidates = [c("main", main: true, focus: 0), c("current", current: true, focus: 9)]
        XCTAssertEqual(ApplicationRepresentativeResolver.pick(candidates, stableId: "main"), "current")
    }

    func testStableRepresentativeWinsWhileStillEligible() {
        let candidates = [c("stable", focus: 8), c("attended", attended: true, focus: 0)]
        XCTAssertEqual(ApplicationRepresentativeResolver.pick(candidates, stableId: "stable"), "stable")
    }

    func testLastConfirmedAttentionWinsBeforeAxMain() {
        let candidates = [c("main", main: true, focus: 0), c("attended", attended: true, focus: 7)]
        XCTAssertEqual(ApplicationRepresentativeResolver.pick(candidates, stableId: nil), "attended")
    }

    func testAxMainIsColdStartFallback() {
        let candidates = [c("mru", focus: 0), c("main", main: true, focus: 5)]
        XCTAssertEqual(ApplicationRepresentativeResolver.pick(candidates, stableId: nil), "main")
    }

    func testMruAndCreationBreakFallbackTiesDeterministically() {
        XCTAssertEqual(ApplicationRepresentativeResolver.pick([
            c("old", focus: 2, creation: 1), c("new", focus: 1, creation: 1),
        ], stableId: nil), "new")
        XCTAssertEqual(ApplicationRepresentativeResolver.pick([
            c("old", focus: 1, creation: 1), c("new", focus: 1, creation: 2),
        ], stableId: nil), "new")
    }

    func testIneligibleStableRepresentativeDoesNotBlockReplacement() {
        XCTAssertEqual(ApplicationRepresentativeResolver.pick([c("available")], stableId: "filtered"),
            "available")
    }
}
