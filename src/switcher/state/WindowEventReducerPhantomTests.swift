import XCTest

/// Pins the EFFECTS the reducer emits when the CGS phantom pass (`cgsWindowListsRead`) flips a window's
/// derived phantom. Drives `WindowEventReducer.reduce` directly and inspects the returned effects, because
/// `.removeWindowlessPlaceholder` is display-side: the replay harness deliberately swallows it, so a
/// scenario replay cannot observe it. See WindowEventReducerPhantomSpecs.md.
final class WindowEventReducerPhantomTests: XCTestCase {

    private static let slackPid: pid_t = 89789
    private static let slackWid: CGWindowID = 140743
    private static let otherPid: pid_t = 1471
    private static let otherWid: CGWindowID = 194

    /// Slack's real window, on the current Space, latched phantom by an earlier CGS pass.
    ///
    /// `isOrderedIn` is what the CGS "visible" list used to stand in for. The kernel reads the WindowServer
    /// bit now, so a test that means "this window is on screen" says so on the window rather than by putting
    /// its wid in a list argument.
    private func slackWindow(latchedPhantom: Bool = true, lastFocusOrder: Int = 0,
                             isOrderedIn: Bool = false) -> TrackedWindow {
        TrackedWindow(id: "wid-\(Self.slackWid)", wid: Self.slackWid, pid: Self.slackPid, title: "Slack",
            size: CGSize(width: 2056, height: 1204), position: CGPoint(x: 0, y: 40),
            spaceIds: [1], spaceIndexes: [1], isOnAllSpaces: false, spaceIsBorrowed: false,
            isFullscreen: false, isFullscreenMirrored: false, isMinimized: false, isMainWindow: false,
            isWindowlessApp: false, cgsPhantomLatch: latchedPhantom, isOrderedIn: isOrderedIn,
            lastFocusOrder: lastFocusOrder, creationOrder: 1, hasThumbnail: true)
    }

    /// Another app's window, so the MRU has somewhere to shift a bump to (`applyFocusAndBump` is a no-op on
    /// a one-window list) and so "not frontmost" has a plausible owner.
    private func otherAppWindow(order: Int) -> TrackedWindow {
        TrackedWindow(id: "wid-\(Self.otherWid)", wid: Self.otherWid, pid: Self.otherPid, title: "Chrome",
            size: CGSize(width: 2056, height: 1204), position: CGPoint(x: 0, y: 40),
            spaceIds: [1], spaceIndexes: [1], isOnAllSpaces: false, spaceIsBorrowed: false,
            isFullscreen: false, isFullscreenMirrored: false, isMinimized: false, isMainWindow: false,
            isWindowlessApp: false, cgsPhantomLatch: false, lastFocusOrder: order,
            creationOrder: 2, hasThumbnail: true)
    }

    private func state(_ windows: [TrackedWindow], appIsActive: Bool = false) -> TrackedWindowState {
        var s = TrackedWindowState()
        s.windows = windows
        s.apps[Self.slackPid] = TrackedApp(
            state: ApplicationState(pid: Self.slackPid, bundleIdentifier: "com.tinyspeck.slackmacgap",
                                    localizedName: "Slack", isHidden: false),
            isActive: appIsActive)
        s.apps[Self.otherPid] = TrackedApp(
            state: ApplicationState(pid: Self.otherPid, bundleIdentifier: "com.google.Chrome",
                                    localizedName: "Google Chrome", isHidden: false),
            isActive: false)
        s.visibleSpaces = [1]
        s.currentSpaceId = 1
        s.spaceIndexById = [1: 1]
        s.frontmostPid = appIsActive ? Self.slackPid : nil
        return s
    }

    private func dropsPlaceholder(_ effects: [ReducerEffect]) -> Bool {
        effects.contains(.removeWindowlessPlaceholder(pid: Self.slackPid))
    }

    func testSnapshotSilenceDoesNotJudgeAWindowCreatedAfterIssue() {
        var s = state([slackWindow(latchedPhantom: false)])
        let effects = WindowEventReducer.reduce(&s,
            .cgsWindowListsRead(visible: [], all: [], queried: []))
        XCTAssertFalse(s.windows[0].cgsPhantomLatch)
        XCTAssertTrue(effects.isEmpty)
    }

    // MARK: - A. Un-phantoming drops the app's stale windowless placeholder (#5849)

    /// The captured bug: Slack's window is latched phantom, so its app also carries a windowless
    /// placeholder tile. The CGS pass then sees the window in both lists and clears the verdict. Without
    /// the effect the placeholder survives forever and the app shows TWO tiles ("appears twice in the list
    /// and won't change even if I wait or switch windows").
    func testUnphantomingEmitsRemoveWindowlessPlaceholder() {
        var s = state([slackWindow(latchedPhantom: true)])
        XCTAssertTrue(s.isPhantom(s.windows[0]), "precondition: latched and off screen")
        let effects = WindowEventReducer.reduce(&s, .cgsWindowListsRead(
            visible: [], all: [Self.slackWid], queried: [Self.slackWid]))
        XCTAssertTrue(s.isPhantom(s.windows[0]), "the CGS pass alone cannot clear an off-screen window")
        XCTAssertFalse(dropsPlaceholder(effects))
    }

    /// The same flip, on the input that now carries it. The window coming back on screen is a WindowServer
    /// order-in, which lands ~250ms before the CGS pass would have run — so the placeholder must be dropped
    /// from THERE, or Slack keeps a real tile and a windowless one at the same time (#5849).
    func testOrderInUnphantomsAndDropsThePlaceholder() {
        var s = state([slackWindow(latchedPhantom: true)])
        XCTAssertTrue(s.isPhantom(s.windows[0]), "precondition: latched and off screen")
        let effects = WindowEventReducer.reduce(&s, .windowOrderedIn(wid: Self.slackWid, now: 10,
            inSpaceTransition: false))
        XCTAssertFalse(s.isPhantom(s.windows[0]))
        XCTAssertTrue(dropsPlaceholder(effects))
    }

    /// The opposite edge is deliberately NOT symmetric, and this pins the asymmetry so nobody "fixes" it.
    /// Going off screen is not evidence of anything on its own — a minimize, a Space move and an app-hide
    /// all look like it — so the synchronous verdict keeps a window that still holds a Space, and only the
    /// authoritative CGS pass may latch it phantom. Un-phantoming is the direction that can be decided from
    /// one fact, which is why only that half rides the order event.
    func testOrderOutAloneDoesNotPhantomAWindowThatStillHoldsASpace() {
        var s = state([slackWindow(latchedPhantom: false, isOrderedIn: true)])
        XCTAssertFalse(s.isPhantom(s.windows[0]), "precondition: on screen, not phantom")
        let effects = WindowEventReducer.reduce(&s, .windowOrderedOut(wid: Self.slackWid,
            inSpaceTransition: false))
        XCTAssertFalse(s.isPhantom(s.windows[0]))
        XCTAssertFalse(effects.contains(.addWindowlessPlaceholder(pid: Self.slackPid)))
    }

    /// The reverse flip (real → phantom) must NOT drop a placeholder: the app is becoming windowless, which
    /// is exactly when the placeholder is legitimate.
    func testBecomingPhantomDoesNotEmitRemoveWindowlessPlaceholder() {
        var s = state([slackWindow(latchedPhantom: false)])
        let effects = WindowEventReducer.reduce(&s, .cgsWindowListsRead(
            visible: [], all: [Self.slackWid], queried: [Self.slackWid]))
        XCTAssertTrue(s.isPhantom(s.windows[0]), "precondition: the weak signal must have flagged it")
        XCTAssertFalse(dropsPlaceholder(effects))
    }

    /// No flip, no effect — a steady-state pass must stay silent, or every CGS read would churn the list.
    func testNoFlipEmitsNothing() {
        var s = state([slackWindow(latchedPhantom: false, isOrderedIn: true)])
        let effects = WindowEventReducer.reduce(&s, .cgsWindowListsRead(
            visible: [Self.slackWid], all: [Self.slackWid], queried: [Self.slackWid]))
        XCTAssertFalse(dropsPlaceholder(effects))
    }

    // MARK: - B. An on-screen window is never a phantom (#5849)

    /// Slack reopened from the Dock: CGS still tags the window invisible and reports no Space for it, while
    /// the WindowServer has it ordered in. It must not be flagged phantom — otherwise it is hidden while
    /// still holding MRU slot 0, and the switcher's "previously-focused window" default skips a window and
    /// lands on the wrong app.
    ///
    /// This used to be a FOCUS exemption, which meant threading "front of the MRU and its app is frontmost"
    /// into a pure kernel and made the verdict depend on window order — the coupling that made three
    /// separate attempts at #5954 regress. The ordered-in bit answers it as a fact about the window.
    func testOnScreenWindowSurvivesTheOrderedOutSignal() {
        var s = state([slackWindow(latchedPhantom: false, lastFocusOrder: 0, isOrderedIn: true)],
                      appIsActive: true)
        _ = WindowEventReducer.reduce(&s, .cgsWindowListsRead(
            visible: [], all: [Self.slackWid], queried: [Self.slackWid]))
        XCTAssertFalse(s.isPhantom(s.windows[0]))
    }

    /// The same window while the WindowServer is NOT showing it: that is the `orderOut:` / `show:false`
    /// family, and it is a phantom whether or not its app happens to be frontmost.
    func testOrderedOutWindowIsFlaggedEvenWhenItsAppIsFrontmost() {
        var s = state([slackWindow(latchedPhantom: false, lastFocusOrder: 0)], appIsActive: true)
        _ = WindowEventReducer.reduce(&s, .cgsWindowListsRead(
            visible: [], all: [Self.slackWid], queried: [Self.slackWid]))
        XCTAssertTrue(s.isPhantom(s.windows[0]))
    }

    /// And with the app in the background, which is where the old focus exemption did not apply either —
    /// kept so the two halves of that former rule are both still pinned.
    func testOrderedOutWindowOfBackgroundAppIsFlagged() {
        var s = state([slackWindow(latchedPhantom: false, lastFocusOrder: 3)], appIsActive: false)
        _ = WindowEventReducer.reduce(&s, .cgsWindowListsRead(
            visible: [], all: [Self.slackWid], queried: [Self.slackWid]))
        XCTAssertTrue(s.isPhantom(s.windows[0]))
    }

    // MARK: - C. Attention clears a stale phantom immediately (#5849)

    /// The gap the CGS pass alone leaves: the verdict is only recomputed on a show, a beat AFTER the
    /// switcher appears. Opening Slack and tapping the shortcut straight away hit the switcher while the
    /// stale latch still hid the window the user had just focused. Attention is proof, so it clears the
    /// latch the moment it lands, without waiting for a pass.
    func testAttentionClearsAStalePhantomLatch() {
        var s = state([slackWindow(latchedPhantom: true, lastFocusOrder: 3)], appIsActive: true)
        XCTAssertTrue(s.isPhantom(s.windows[0]), "precondition: latched phantom")
        _ = WindowEventReducer.reduce(&s, .attentionCommitted(wid: Self.slackWid, observed: Self.slackWid,
            at: 10.0))
        XCTAssertFalse(s.isPhantom(s.windows[0]))
    }

    /// Un-phantoming must also drop the placeholder its app grew while it looked windowless — otherwise the
    /// fast path trades the wrong-window bug for the duplicate-tile one.
    func testAttentionUnphantomingEmitsRemoveWindowlessPlaceholder() {
        var s = state([slackWindow(latchedPhantom: true, lastFocusOrder: 3)], appIsActive: true)
        let effects = WindowEventReducer.reduce(&s, .attentionCommitted(wid: Self.slackWid,
            observed: Self.slackWid, at: 10.0))
        XCTAssertTrue(dropsPlaceholder(effects))
    }

    /// An already-real window changes nothing: no spurious placeholder removal on every decision.
    func testAttentionOnARealWindowEmitsNoPlaceholderRemoval() {
        var s = state([slackWindow(latchedPhantom: false, lastFocusOrder: 3)], appIsActive: true)
        let effects = WindowEventReducer.reduce(&s, .attentionCommitted(wid: Self.slackWid,
            observed: Self.slackWid, at: 10.0))
        XCTAssertFalse(dropsPlaceholder(effects))
    }

    // MARK: - D. The same, for the window a reopened app comes back to (#5849, second report)

    /// Reopening Slack from the Dock reaches the front through an activation that names only the process.
    /// The attention model uses Slack's cached answer or requests one bounded focused-window read. That answer
    /// used to bump the MRU straight from the shell, so the latch survived: summoning the switcher 130 ms
    /// later hid the window the user was looking at while it held slot 0, and the default pick skipped past
    /// the previous window onto a third
    /// app (System Settings, in the capture).
    func testTheReopenedWindowsLatchIsCleared() {
        var s = state([slackWindow(latchedPhantom: true, lastFocusOrder: 1), otherAppWindow(order: 0)],
            appIsActive: true)
        XCTAssertTrue(s.isPhantom(s.windows[0]), "precondition: latched phantom")
        let effects = WindowEventReducer.reduce(&s, .attentionCommitted(wid: Self.slackWid,
            observed: Self.slackWid, at: 10.0))
        XCTAssertFalse(s.isPhantom(s.windows[0]))
        XCTAssertEqual(s.window(Self.slackWid)?.lastFocusOrder, 0)
        XCTAssertTrue(dropsPlaceholder(effects))
    }

    // MARK: - E. An app whose last window turns phantom gets its placeholder in the SAME pass (#5849)

    /// The other half of the placeholder's lifecycle, which had no owner: the app is now windowless, so the
    /// icon tile must appear with this verdict. It used to come from the shell's per-app sweep, which runs
    /// BEFORE the verdicts are applied and therefore judged the previous latch — so closing Slack's window
    /// gave three different switchers in three consecutive summons (open window / nothing at all / closed-app
    /// icon).
    func testLastWindowTurningPhantomEmitsAddWindowlessPlaceholder() {
        var s = state([slackWindow(latchedPhantom: false)])
        let effects = WindowEventReducer.reduce(&s, .cgsWindowListsRead(
            visible: [], all: [Self.slackWid], queried: [Self.slackWid]))
        XCTAssertTrue(s.isPhantom(s.windows[0]), "precondition: the weak signal must have flagged it")
        XCTAssertTrue(effects.contains(.addWindowlessPlaceholder(pid: Self.slackPid)))
    }

    /// One window of several turning phantom leaves the app with something to show, so no placeholder: that
    /// is the duplicate-tile bug in the other direction.
    func testPhantomWithAnotherRealWindowLeftEmitsNoAdd() {
        let secondWid: CGWindowID = Self.slackWid + 1
        var second = slackWindow(latchedPhantom: false, lastFocusOrder: 1, isOrderedIn: true)
        second.wid = secondWid
        second.id = "wid-\(secondWid)"
        var s = state([slackWindow(latchedPhantom: false), second])
        let effects = WindowEventReducer.reduce(&s, .cgsWindowListsRead(
            visible: [secondWid], all: [Self.slackWid, secondWid], queried: [Self.slackWid, secondWid]))
        XCTAssertTrue(s.isPhantom(s.windows[0]), "precondition: only the first window flipped")
        XCTAssertFalse(s.isPhantom(s.windows[1]))
        XCTAssertFalse(effects.contains(.addWindowlessPlaceholder(pid: Self.slackPid)))
    }

    /// Un-phantoming is the opposite edge and must never ADD one.
    func testUnphantomingEmitsNoAdd() {
        var s = state([slackWindow(latchedPhantom: true, isOrderedIn: true)])
        let effects = WindowEventReducer.reduce(&s, .cgsWindowListsRead(
            visible: [Self.slackWid], all: [Self.slackWid], queried: [Self.slackWid]))
        XCTAssertFalse(effects.contains(.addWindowlessPlaceholder(pid: Self.slackPid)))
    }
}
