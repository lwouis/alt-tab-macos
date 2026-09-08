import XCTest

/// Pins the split between the two Space-switch reactions: the leading edge reads the topology and nothing
/// else, the trailing edge keeps the work that has to wait for the transition's storm to be over. Drives
/// `WindowEventReducer.reduce` directly — the replay harness buckets both branches' requests together and
/// swallows `.refreshUi`, so it cannot tell them apart. See WindowEventReducerSpaceSpecs.md.
final class WindowEventReducerSpaceTests: XCTestCase {

    private static let pid: pid_t = 4711
    private static let widA: CGWindowID = 5001
    private static let widB: CGWindowID = 5002

    private func window(_ wid: CGWindowID, spaceId: UInt64, order: Int) -> TrackedWindow {
        TrackedWindow(id: "wid-\(wid)", wid: wid, pid: Self.pid, title: "w\(wid)",
            size: CGSize(width: 1200, height: 800), position: CGPoint(x: 0, y: 40),
            spaceIds: [spaceId], spaceIndexes: [Int(spaceId)], isOnAllSpaces: false, spaceIsBorrowed: false,
            isFullscreen: false, isFullscreenMirrored: false, isMinimized: false, isMainWindow: false,
            isWindowlessApp: false, cgsPhantomLatch: false, lastFocusOrder: order,
            creationOrder: order, hasThumbnail: true)
    }

    /// One window on each of two Spaces, sitting on Space 1 — the shape a Space switch acts on.
    private func state() -> TrackedWindowState {
        var s = TrackedWindowState()
        s.windows = [window(Self.widA, spaceId: 1, order: 0), window(Self.widB, spaceId: 2, order: 1)]
        s.apps[Self.pid] = TrackedApp(
            state: ApplicationState(pid: Self.pid, bundleIdentifier: "com.apple.TextEdit",
                                    localizedName: "TextEdit", isHidden: false),
            isActive: true)
        s.visibleSpaces = [1]
        s.currentSpaceId = 1
        s.spaceIndexById = [1: 1, 2: 2]
        s.frontmostPid = Self.pid
        return s
    }

    // MARK: - A. The leading edge is the topology read, and nothing else

    /// The leading edge exists to make ONE cheap fact current before the summon that follows it. A repaint
    /// here is the trap: `refreshOpenUiAfterExternalEvent` is throttled at 200ms leading-edge, so repainting
    /// the instant the Space flips spends that edge and the semantic focus answer that follows then waits
    /// out the tail (live: 19ms became 220ms). Exact equality, so re-adding any of it
    /// fails here rather than in a QA run weeks later.
    func testSpaceTransitionStartedEmitsTheTopologyReadAlone() {
        var s = state()
        let effects = WindowEventReducer.reduce(&s, .spaceTransitionStarted)
        XCTAssertEqual(effects, [.refreshSpacesTopology])
    }

    /// It asks the shell to re-read `Spaces`; it is not a place to write the model. The per-window
    /// correction that follows a Space switch belongs to `.spacesSynced`, on real CGS answers.
    func testSpaceTransitionStartedTouchesNoWindowState() {
        var s = state()
        let before = s.windows
        _ = WindowEventReducer.reduce(&s, .spaceTransitionStarted)
        XCTAssertEqual(s.windows, before)
        XCTAssertEqual(s.currentSpaceId, 1)
        XCTAssertEqual(s.visibleSpaces, [1])
    }

    // MARK: - B. The trailing edge keeps the expensive half

    /// The half that has to wait for the transition's create/destroy storm to be over: an early answer here
    /// describes a state that stops being true a frame later, and would be written onto `spaceIds` as
    /// authoritative. Collapsing the two branches would either run this early or drop it.
    func testSpaceChangeSettledKeepsMembershipAndTheStateRequery() {
        var s = state()
        let effects = WindowEventReducer.reduce(&s, .spaceChangeSettled)
        XCTAssertTrue(effects.contains(.refreshSpacesTopologyAndSync))
        XCTAssertTrue(effects.contains(.queryWindowServerState(wids: [Self.widA, Self.widB], throttled: false)))
        XCTAssertTrue(effects.contains(.checkShortcutsForFocusedWindow))
        XCTAssertTrue(effects.contains(.refreshUi(wids: [Self.widA, Self.widB], onlyWhileSwitcherOpen: false)))
        XCTAssertFalse(effects.contains(.refreshSpacesTopology),
                       "the settled pass owns the full refresh; emitting the leading edge's cheap read too "
                       + "would re-read the topology twice for nothing")
    }

    // MARK: - B2. Leaving fullscreen

    /// **Leaving fullscreen must not hand the window to a same-sized sibling.** Live trace (2026-09-08,
    /// Chrome, two windows at one frame): the window drops its fullscreen Space, joins the windowed one, and
    /// a Spaces re-query lands in the tail of the animation still naming NO Space for it — CGS lags the
    /// rejoin. The 1326 recorded `lastLeftSpaceId`, but the 1325 that followed cleared it, so by the time the
    /// re-query empties `spaceIds` again the one fact that says "this window came off its OWN Space" is gone.
    /// What is left is same-app, same-size, Space-less, ordered-out and still flagged fullscreen: every fact
    /// a background tab of the other window has, and the fullscreen clause waives the confirmation gate the
    /// windowed path would have required. Geometry folds it in, `isTabbed` hides its tile, and nothing
    /// re-splits an established group — the window is unreachable for the rest of the session.
    func testLeavingFullscreenIsNotFoldedIntoASameSizedSibling() {
        var s = state()
        // a third window, of another app, sitting on the windowed Space — what makes that Space demonstrably
        // SHARED, and so proves the returning window is not on a fullscreen Space any more
        var other = window(5003, spaceId: 1, order: 2)
        other.pid = 4712
        other.size = CGSize(width: 700, height: 500)
        other.isOrderedIn = true
        s.windows.append(other)
        s.apps[4712] = TrackedApp(
            state: ApplicationState(pid: 4712, bundleIdentifier: "com.apple.Safari",
                                    localizedName: "Safari", isHidden: false),
            isActive: false)
        s.windows[1].spaceIds = [764]
        s.windows[1].spaceIndexes = [2]
        s.windows[1].isFullscreen = true
        s.windows[0].isOrderedIn = true
        s.spaceIndexById[764] = 2
        _ = WindowEventReducer.reduce(&s, .spaceMembershipChanged(wid: Self.widB, spaceId: 764, added: false,
            now: 1, inSpaceTransition: false))
        _ = WindowEventReducer.reduce(&s, .spaceMembershipChanged(wid: Self.widB, spaceId: 1, added: true,
            now: 2, inSpaceTransition: false))
        _ = WindowEventReducer.reduce(&s, .spacesSynced(windowToSpaces: [Self.widA: [1], Self.widB: []],
            queried: [Self.widA, Self.widB], answered: [Self.widA, Self.widB],
            placedByWindowServer: [], topologyChanged: false))
        XCTAssertFalse(s.isTabbed(s.windows[1]),
                       "a window coming out of fullscreen is not a tab of the window it happens to match in size")
        XCTAssertNil(s.groups.groupId(of: Self.widB), "members=\(s.groups.membersByGroup) tabbedA=\(s.isTabbed(s.windows[0])) tabbedB=\(s.isTabbed(s.windows[1])) spA=\(s.windows[0].spaceIds) spB=\(s.windows[1].spaceIds)")
    }

    // MARK: - C. The Spaces answer applies only to the windows it was asked about

    /// The pass captures its wid list on main, queries off-main, and lands later. A window discovered in that
    /// gap is in the model but was never asked about, so the map cannot place it — and applying the map to it
    /// anyway asserted "CGS places this window nowhere", the strong phantom signal, on a window whose own
    /// discovery had just read its Space. It went hidden until the next pass happened to cover it.
    func testAnAnswerDoesNotWipeAWindowItNeverAskedAbout() {
        var s = state()
        _ = WindowEventReducer.reduce(&s, .spacesSynced(windowToSpaces: [Self.widA: [1]],
            queried: [Self.widA], answered: [Self.widA], placedByWindowServer: [], topologyChanged: false))
        XCTAssertEqual(s.window(Self.widB)?.spaceIds, [2], "widB was never queried, so nothing was learnt")
        XCTAssertFalse(s.isPhantom(s.windows[1]))
    }

    /// Skipping is for SILENCE only. `Spaces.query` enumerates every Space and keeps whatever CGS lists, so
    /// the map is not limited to the wids the pass asked about — a window appended mid-flight is usually in
    /// it, and that answer beats the current-Space GUESS its discovery fell back on when its own per-window
    /// query came back empty. Dropping it would leave the window drawn under the wrong Space.
    func testAnAnswerIsAppliedEvenToAWindowItNeverAskedAbout() {
        var s = state()
        _ = WindowEventReducer.reduce(&s, .spacesSynced(windowToSpaces: [Self.widB: [1]],
            queried: [Self.widA], answered: [Self.widA, Self.widB],
            placedByWindowServer: [], topologyChanged: false))
        XCTAssertEqual(s.window(Self.widB)?.spaceIds, [1])
    }

    /// The other half, which must keep working: a wid the pass DID ask about, the map does not place, and the
    /// WindowServer does not place either. THAT is CGS answering "no Space", and it is what retires a group's
    /// dead members and hands a closed window to the sweep, so neither skip above may swallow it.
    func testAQueriedWindowWhoseDirectQueryFailedKeepsItsLastMembership() {
        var s = state()
        _ = WindowEventReducer.reduce(&s, .spacesSynced(windowToSpaces: [Self.widA: [1]],
            queried: [Self.widA, Self.widB], answered: [Self.widA],
            placedByWindowServer: [], topologyChanged: false))
        XCTAssertEqual(s.window(Self.widB)?.spaceIds, [2])
        XCTAssertFalse(s.isPhantom(s.windows[1]))
    }

    func testAnExplicitEmptyAnswerWipesAQueriedWindow() {
        var s = state()
        _ = WindowEventReducer.reduce(&s, .spacesSynced(
            windowToSpaces: [Self.widA: [1], Self.widB: []], queried: [Self.widA, Self.widB],
            answered: [Self.widA, Self.widB], placedByWindowServer: [], topologyChanged: false))
        XCTAssertEqual(s.window(Self.widB)?.spaceIds, [])
        XCTAssertTrue(s.isPhantom(s.windows[1]))
    }

    // MARK: - D. An empty Space answer is not evidence on its own (#5954)

    /// CGS answers a non-NULL EMPTY array for a wid it has no record of at all — measured on macOS 26 for
    /// wid 0, 1, 999999 and UINT32_MAX — so "this window is on no Space" and "there is no such window" reach
    /// the reducer as the same value, and the strong phantom signal used to hide the window on both. When the
    /// WindowServer contradicts the emptiness (it knows the wid and places it on a Space), the window keeps
    /// the last membership CGS itself reported instead of being wiped and hidden with no way back.
    func testAContradictedEmptyKeepsTheLastKnownMembership() {
        var s = state()
        _ = WindowEventReducer.reduce(&s, .spacesSynced(
            windowToSpaces: [Self.widA: [1], Self.widB: []], queried: [Self.widA, Self.widB],
            answered: [Self.widA, Self.widB], placedByWindowServer: [Self.widB], topologyChanged: false))
        XCTAssertEqual(s.window(Self.widB)?.spaceIds, [2], "the last CGS-reported membership, not a guess")
        XCTAssertFalse(s.isPhantom(s.windows[1]))
    }

    /// The contradiction must not resurrect a window CGS places somewhere new: a real answer always wins over
    /// the keep, or a window that genuinely moved Space would be frozen at its old one.
    func testAPlacedWindowStillTakesItsNewSpace() {
        var s = state()
        _ = WindowEventReducer.reduce(&s, .spacesSynced(windowToSpaces: [Self.widA: [1], Self.widB: [1]],
            queried: [Self.widA, Self.widB], answered: [Self.widA, Self.widB],
            placedByWindowServer: [Self.widB], topologyChanged: false))
        XCTAssertEqual(s.window(Self.widB)?.spaceIds, [1])
    }

    // MARK: - E. A transition that never commits, and transitions that overlap

    /// **A swipe the user abandons.** Three fingers travel a little and lift below the Dock's commit
    /// threshold: the WindowServer really does begin moving windows, so the transition's leading edge fires,
    /// and then the Space it settles on is the one it started on. Nothing changed, and the reducer must
    /// agree that nothing changed — a model that took the START of a transition as its answer would be left
    /// filtering and sorting for a Space the user never reached, with no second event coming to correct it.
    ///
    /// Only reachable live since the QA harness learned to synthesize a dock swipe; a
    /// commanded `SLSManagedDisplaySetCurrentSpace` always commits, so this shape could not be produced.
    func testATransitionThatNeverCommitsLeavesTheModelWhereItWas() {
        var s = state()
        let before = s.windows
        _ = WindowEventReducer.reduce(&s, .spaceTransitionStarted)
        _ = WindowEventReducer.reduce(&s, .spaceChangeSettled)
        XCTAssertEqual(s.currentSpaceId, 1)
        XCTAssertEqual(s.visibleSpaces, [1])
        XCTAssertEqual(s.windows, before, "an abandoned transition is not evidence about any window")
    }

    /// The settled pass still asks, even when nothing moved. The reducer cannot know the swipe was abandoned
    /// — only the answer can say so — so the requery is what makes the two cases converge rather than the
    /// reducer guessing between them.
    func testAnAbandonedTransitionStillRequeries() {
        var s = state()
        _ = WindowEventReducer.reduce(&s, .spaceTransitionStarted)
        let effects = WindowEventReducer.reduce(&s, .spaceChangeSettled)
        XCTAssertTrue(effects.contains(.refreshSpacesTopologyAndSync))
        XCTAssertTrue(effects.contains(.queryWindowServerState(wids: [Self.widA, Self.widB], throttled: false)))
    }

    /// **Swipes faster than the animation.** Each one starts a transition while the last is still running, so
    /// the leading edges arrive back to back with no settle between them. The edge carries no per-transition
    /// state, so a second one must be exactly the first — anything accumulated here would be a leak that
    /// grows with how fast the user swipes.
    func testOverlappingTransitionsAreIdempotent() {
        var s = state()
        let first = WindowEventReducer.reduce(&s, .spaceTransitionStarted)
        let snapshot = s.windows
        let second = WindowEventReducer.reduce(&s, .spaceTransitionStarted)
        XCTAssertEqual(first, second)
        XCTAssertEqual(s.windows, snapshot)
        XCTAssertEqual(s.currentSpaceId, 1)
    }
}
