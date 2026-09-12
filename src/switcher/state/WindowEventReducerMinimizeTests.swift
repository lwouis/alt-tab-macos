import XCTest

/// Pins what a WindowServer order-in means for a window the model believes is MINIMIZED: the flag clears,
/// and the restore earns the MRU front the un-minimize gave it. See WindowEventReducerMinimizeSpecs.md.
final class WindowEventReducerMinimizeTests: XCTestCase {

    private static let chromePid: pid_t = 638
    private static let finderPid: pid_t = 653
    private static let restoredWid: CGWindowID = 30718  // the window the reporter unminimized
    private static let siblingWid: CGWindowID = 16      // Chrome's other window, focused while it was away
    private static let finderWid: CGWindowID = 30767

    private func window(_ wid: CGWindowID, _ pid: pid_t, order: Int, isMinimized: Bool = false,
                        spaceIds: [UInt64] = [1], size: CGSize = CGSize(width: 1470, height: 923),
                        position: CGPoint = CGPoint(x: 0, y: 33)) -> TrackedWindow {
        TrackedWindow(id: "wid-\(wid)", wid: wid, pid: pid, title: "w\(wid)",
            size: size, position: position,
            spaceIds: spaceIds, spaceIndexes: [1], isOnAllSpaces: false, spaceIsBorrowed: false,
            isFullscreen: false, isFullscreenMirrored: false, isMinimized: isMinimized, isMainWindow: false,
            isWindowlessApp: false, cgsPhantomLatch: false, lastFocusOrder: order,
            creationOrder: Int(wid), hasThumbnail: true)
    }

    /// The reporter's desktop: two Chrome windows and a Finder window on one Space, Chrome frontmost.
    private func state(_ windows: [TrackedWindow], frontmost: pid_t) -> TrackedWindowState {
        var s = TrackedWindowState()
        s.windows = windows
        s.apps[Self.chromePid] = TrackedApp(state: ApplicationState(pid: Self.chromePid,
            bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome", isHidden: false),
            isActive: frontmost == Self.chromePid)
        s.apps[Self.finderPid] = TrackedApp(state: ApplicationState(pid: Self.finderPid,
            bundleIdentifier: "com.apple.finder", localizedName: "Finder", isHidden: false),
            isActive: frontmost == Self.finderPid)
        s.frontmostPid = frontmost
        s.visibleSpaces = [1]
        s.currentSpaceId = 1
        s.spaceIndexById = [1: 1]
        return s
    }

    private func order(_ state: TrackedWindowState, _ wid: CGWindowID) -> Int? {
        state.window(wid)?.lastFocusOrder
    }

    private func minimized(_ state: TrackedWindowState, _ wid: CGWindowID) -> Bool? {
        state.window(wid)?.isMinimized
    }

    /// What the batched WindowServer query reports for a window — the source of `isMinimized` since the
    /// `tags` bit-60 mapping replaced the AX `kAXMinimized` read.
    private func snapshot(_ wid: CGWindowID, isMinimized: Bool) -> WsWindowSnapshot {
        WsWindowSnapshot(wid: wid, position: CGPoint(x: 0, y: 33),
            size: CGSize(width: 1470, height: 923), isFullscreen: false,
            isVisible: !isMinimized, isMinimized: isMinimized)
    }

    /// The reporter's own sequence, transcribed from their capture (log 09:25:03.530 → 09:25:06.540): the
    /// window is minimized, Chrome focuses its other window, then the Dock restores the first one — emitting
    /// ONLY the order-in, because Chrome was already frontmost. The follow-up read that would clear
    /// `isMinimized` is deliberately NOT replayed, because on a Dock restore NOTHING clears it in time: AX
    /// answers ~530ms late and the WindowServer's own bit ~644ms late, both after the order-in. That is the
    /// whole defect, and why the un-minimize is derived from the event instead.
    private func dockRestoreSteps() -> [TestReducerRunner.Step] {
        [.input(.windowOrderedOut(wid: Self.restoredWid, inSpaceTransition: false)),
         .input(.windowServerStateRead([snapshot(Self.restoredWid, isMinimized: true)])),
         .input(.windowFocused(wid: Self.siblingWid, now: 3.0)),
         .input(.windowOrderedIn(wid: Self.restoredWid, now: 6.0, inSpaceTransition: false))]
    }

    private func desktop(frontmost: pid_t = WindowEventReducerMinimizeTests.chromePid) -> TrackedWindowState {
        state([
            window(Self.restoredWid, Self.chromePid, order: 0),
            window(Self.finderWid, Self.finderPid, order: 1, size: CGSize(width: 920, height: 436),
                position: CGPoint(x: 275, y: 155)),
            window(Self.siblingWid, Self.chromePid, order: 2),
        ], frontmost: frontmost)
    }

    // MARK: - A. The captured sequence

    /// The bug as reported, in the half the events own: after the Dock restore the window must no longer be
    /// flagged minimized. Without it the window ends `isMinimized=true`, and with
    /// `showMinimizedWindows == .showAtTheEnd` that renders it at the very back of the list, so the
    /// reporter's quick alt+tabs kept toggling between the two OTHER windows and never reached it.
    ///
    /// The ORDER is deliberately not asserted: an 815 is not a statement about what the user is looking at,
    /// so the restored window reaches the front when its app says it has focus, not because it was ordered
    /// in. Covered live, end to end.
    func testRestoringFromTheDockClearsTheFlag() {
        let runner = TestReducerRunner(initial: desktop())
        runner.run(dockRestoreSteps())
        XCTAssertEqual(minimized(runner.state, Self.restoredWid), false)
        XCTAssertTrue(runner.violations.isEmpty, runner.violations.joined(separator: "\n"))
    }

    /// The flag is cleared from the EVENT, not from the AX read — so it clears even when the read never
    /// lands at all. This is the half that no timing can rescue: the app's `kAXMinimized` stays `true` for
    /// ~530ms after a Dock restore, and nothing re-reads it until the next switcher show.
    func testTheOrderInAloneClearsTheMinimizedFlag() {
        let runner = TestReducerRunner(initial: desktop())
        runner.run(dockRestoreSteps())
        XCTAssertEqual(minimized(runner.state, Self.restoredWid), false)
        XCTAssertTrue(runner.trace.contains { $0.contains("unminimized #\(Self.restoredWid)") },
            "the un-minimize must be a named fact in the log, not a silent state change: \(runner.trace)")
    }

    // MARK: - B. Clearing the flag moves nothing

    /// A background app deminiaturizing one of its own windows: the flag clears, because the window IS on
    /// screen again, and the MRU does not move. Clearing a state bit is not a claim about where the user is,
    /// and the two have to stay separable — an app restoring a window behind your back must not take slot 0.
    func testABackgroundAppsRestoreClearsTheFlagWithoutStealingTheFront() {
        let runner = TestReducerRunner(initial: desktop(frontmost: Self.finderPid))
        runner.run([.input(.windowOrderedOut(wid: Self.restoredWid, inSpaceTransition: false)),
                    .input(.windowServerStateRead([snapshot(Self.restoredWid, isMinimized: true)])),
                    .input(.windowOrderedIn(wid: Self.restoredWid, now: 6.0, inSpaceTransition: false))])
        XCTAssertEqual(minimized(runner.state, Self.restoredWid), false)
        XCTAssertEqual(order(runner.state, Self.restoredWid), 0, "rank 0 was already its slot; nothing moved")
        XCTAssertEqual(order(runner.state, Self.finderWid), 1)
    }

    /// The counterfactual that keeps #5849 safe: a Space re-show orders in every window of the Space it is
    /// bringing back. Those windows were never minimized, so the un-minimize path must not touch them —
    /// it keys on the flag precisely so it cannot widen into this — and the order stands either way.
    func testASpaceReShowStillDoesNotFrontItsWindows() {
        let runner = TestReducerRunner(initial: desktop())
        runner.run([.input(.windowOrderedOut(wid: Self.siblingWid, inSpaceTransition: false)),
                    .input(.windowOrderedIn(wid: Self.siblingWid, now: 6.0, inSpaceTransition: false))])
        XCTAssertEqual(order(runner.state, Self.siblingWid), 2, "came back on screen, so it is not a raise")
        XCTAssertEqual(order(runner.state, Self.restoredWid), 0)
    }

    // MARK: - C. Repainting a switcher that is already open

    /// Reported 2026-08-06: minimize a window with the panel's "m" shortcut (the panel stays open),
    /// un-minimize it, and the tile keeps showing the minimized indicator until the panel is closed and
    /// reopened. The model is right — only the repaint is missing, and on this event nothing else asks for
    /// one: our panel holds the key window, so the restored window's app is NOT frontmost and the MRU bump
    /// below is skipped. The un-minimize has to request the repaint itself.
    func testUnMinimizingRepaintsASwitcherThatIsAlreadyOpen() {
        let runner = TestReducerRunner(initial: desktop(frontmost: Self.finderPid))
        runner.run([.input(.windowOrderedOut(wid: Self.restoredWid, inSpaceTransition: false)),
                    .input(.windowServerStateRead([snapshot(Self.restoredWid, isMinimized: true)]))])
        let repaintsBeforeTheRestore = runner.refreshes.count
        runner.perform(.input(.windowOrderedIn(wid: Self.restoredWid, now: 6.0, inSpaceTransition: false)))
        XCTAssertEqual(minimized(runner.state, Self.restoredWid), false)
        XCTAssertTrue(runner.refreshes.dropFirst(repaintsBeforeTheRestore).contains { $0.onlyWhileSwitcherOpen },
            "the un-minimize must repaint the open panel itself: \(runner.refreshes)")
    }

    /// The counterfactual that keeps that repaint narrow: a Space switch orders in every window of the
    /// Space it brings back, and repainting on each of those would be a burst of full re-layouts for a
    /// panel whose tiles did not change. The repaint keys on the un-minimize, like the front does.
    func testAnOrderInThatIsNotAnUnMinimizeRepaintsNothing() {
        let runner = TestReducerRunner(initial: desktop(frontmost: Self.finderPid))
        runner.run([.input(.windowOrderedOut(wid: Self.siblingWid, inSpaceTransition: false))])
        let repaintsBeforeTheReShow = runner.refreshes.count
        runner.perform(.input(.windowOrderedIn(wid: Self.siblingWid, now: 6.0, inSpaceTransition: false)))
        XCTAssertEqual(runner.refreshes.count, repaintsBeforeTheReShow,
            "nothing about the tile changed, so nothing repaints: \(runner.refreshes)")
    }

    /// Reported 2026-08-06, the other half of that same "m" press: the restored window's tile turned into a
    /// mini window floating in transparent pixels. The OS draws a window scaled down for the whole restore
    /// animation, and the un-minimize is precisely what sets off a re-capture, so the fresh screenshot is a
    /// partial frame that replaces a correct one. The reducer hands the shell the wid to hold back.
    func testUnMinimizingHoldsCapturesUntilTheRestoreAnimationEnds() {
        let runner = TestReducerRunner(initial: desktop(frontmost: Self.finderPid))
        runner.run([.input(.windowOrderedOut(wid: Self.restoredWid, inSpaceTransition: false)),
                    .input(.windowServerStateRead([snapshot(Self.restoredWid, isMinimized: true)]))])
        runner.perform(.input(.windowOrderedIn(wid: Self.restoredWid, now: 6.0, inSpaceTransition: false)))
        XCTAssertEqual(runner.deferredCaptures, [Self.restoredWid],
            "the restored window's captures must wait for its animation: \(runner.deferredCaptures)")
    }

    /// Same counterfactual as the repaint above: a window the OS merely brings back on screen was never
    /// scaled down, so holding its captures would only delay a correct screenshot.
    func testAnOrderInThatIsNotAnUnMinimizeHoldsNoCapture() {
        let runner = TestReducerRunner(initial: desktop(frontmost: Self.finderPid))
        runner.run([.input(.windowOrderedOut(wid: Self.siblingWid, inSpaceTransition: false)),
                    .input(.windowOrderedIn(wid: Self.siblingWid, now: 6.0, inSpaceTransition: false))])
        XCTAssertEqual(runner.deferredCaptures, [], "nothing was animating: \(runner.deferredCaptures)")
    }

    // MARK: - D. The group half

    /// Inactive tabs mirror their active tab's minimized state, so restoring a TABBED window has to re-derive
    /// the group or its background tabs stay flagged minimized behind a window that is plainly on screen.
    /// That mirroring is why the un-minimize runs `reconcile` rather than just writing the field.
    func testRestoringATabbedWindowClearsTheFlagOnItsInactiveTabs() {
        let backgroundTabWid: CGWindowID = 30719
        var initial = desktop()
        // a background tab: same frame as its active tab, on no Space (CGS lists no background tab anywhere)
        initial.windows.append(window(backgroundTabWid, Self.chromePid, order: 3, spaceIds: []))
        initial.formGroup([Self.restoredWid, backgroundTabWid], representative: Self.restoredWid,
            reason: "fixture")
        let runner = TestReducerRunner(initial: initial)
        runner.run([.input(.windowOrderedOut(wid: Self.restoredWid, inSpaceTransition: false)),
                    .input(.windowServerStateRead([snapshot(Self.restoredWid, isMinimized: true)])),
                    .input(.windowServerStateRead([snapshot(backgroundTabWid, isMinimized: true)])),
                    .input(.windowOrderedIn(wid: Self.restoredWid, now: 6.0, inSpaceTransition: false))])
        XCTAssertEqual(minimized(runner.state, Self.restoredWid), false)
        XCTAssertEqual(minimized(runner.state, backgroundTabWid), false,
            "the inactive tab must follow its active tab out of the minimized state")
    }

    // MARK: - E. The on-screen bit that tab-grouping reads (#5954)

    /// Every path that can move the bit, pinned: without these, each line carrying it from the OS to the
    /// kernel could be deleted with the whole suite still green, which is how it shipped the first time.
    /// The rule it feeds lives in `TabGroupResolver` (an on-screen window is nobody's background tab); here
    /// we only prove the fact reaches it.
    func testOrderInSetsTheOnScreenBitAndOrderOutClearsIt() {
        var s = state([window(1, Self.chromePid, order: 0)], frontmost: Self.chromePid)
        _ = WindowEventReducer.reduce(&s, .windowOrderedIn(wid: 1, now: 10, inSpaceTransition: false))
        XCTAssertTrue(s.windows[0].isOrderedIn)
        _ = WindowEventReducer.reduce(&s, .windowOrderedOut(wid: 1, inSpaceTransition: false))
        XCTAssertFalse(s.windows[0].isOrderedIn)
    }

    /// A move or resize is NOT an order-out. Both arrive through the same reducer branch, with `orderedIn`
    /// false meaning "this is not an order-in", so writing the bit from that parameter asserted that every
    /// window being dragged said it had left the screen — and entering fullscreen is a resize storm, i.e.
    /// exactly the moment the rule has to hold.
    func testAMoveOrResizeLeavesTheOnScreenBitAlone() {
        var s = state([window(1, Self.chromePid, order: 0)], frontmost: Self.chromePid)
        _ = WindowEventReducer.reduce(&s, .windowOrderedIn(wid: 1, now: 10, inSpaceTransition: false))
        _ = WindowEventReducer.reduce(&s, .windowMovedOrResized(wid: 1, inSpaceTransition: false))
        XCTAssertTrue(s.windows[0].isOrderedIn)
    }

    /// The batched WindowServer query re-syncs the bit, which is the only correction for a window whose
    /// order events we missed.
    func testTheWindowServerQueryResyncsTheOnScreenBit() {
        var s = state([window(1, Self.chromePid, order: 0)], frontmost: Self.chromePid)
        _ = WindowEventReducer.reduce(&s, .windowOrderedIn(wid: 1, now: 10, inSpaceTransition: false))
        _ = WindowEventReducer.reduce(&s, .windowServerStateRead([WsWindowSnapshot(wid: 1,
            position: CGPoint(x: 0, y: 33), size: CGSize(width: 1470, height: 923),
            isFullscreen: false, isVisible: false)]))
        XCTAssertFalse(s.windows[0].isOrderedIn)
    }

    /// Discovery seeds it from the same WindowServer row it discriminated the window on. At cold start no
    /// order event ever fires for a window that was already open, so without this seed the rule is unarmed
    /// exactly when a whole desktop of same-frame windows arrives at once.
    func testDiscoverySeedsTheOnScreenBit() {
        var s = state([window(1, Self.chromePid, order: 0)], frontmost: Self.chromePid)
        _ = WindowEventReducer.reduce(&s, .discoveryLanded(wid: 1, accepted: true, newlyTracked: true,
            adoptedAsInactiveTab: false, queriedSpaceIds: [1], isOrderedIn: true, tabTitles: nil, tabGroupToken: nil))
        XCTAssertTrue(s.windows[0].isOrderedIn)
    }

    /// ...except for a window discovery already knows is a background tab: its row is stale, and we know the
    /// answer. Same reasoning as the Space it is forced to give up.
    func testAnAdoptedInactiveTabIsNeverSeededOnScreen() {
        var s = state([window(1, Self.chromePid, order: 0)], frontmost: Self.chromePid)
        _ = WindowEventReducer.reduce(&s, .discoveryLanded(wid: 1, accepted: true, newlyTracked: true,
            adoptedAsInactiveTab: true, queriedSpaceIds: [1], isOrderedIn: true, tabTitles: nil, tabGroupToken: nil))
        XCTAssertFalse(s.windows[0].isOrderedIn)
    }

    /// The projection is the last link in the chain: the kernels see `TabWindow`, so a bit the projection
    /// drops is a bit the rule never reads, and no kernel test can tell.
    func testTheKernelProjectionCarriesTheOnScreenBit() {
        var s = state([window(1, Self.chromePid, order: 0)], frontmost: Self.chromePid)
        _ = WindowEventReducer.reduce(&s, .windowOrderedIn(wid: 1, now: 10, inSpaceTransition: false))
        XCTAssertTrue(s.tabWindow(s.windows[0]).isOrderedIn)
    }
}
