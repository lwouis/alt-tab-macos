import XCTest

/// Pins what may move the window order, and what may not. Sequence-shaped scenarios (a window being born)
/// are replayed through `TestReducerRunner` because the bug is a sequence rather than a single decision;
/// rule-level ones drive `WindowEventReducer.reduce` directly. See WindowEventReducerFocusSpecs.md.
final class WindowEventReducerFocusTests: XCTestCase {

    private static let reaperPid: pid_t = 15690
    private static let finderPid: pid_t = 681
    private static let reaperMainWid: CGWindowID = 4274   // "Country Dance - REAPER v7.78"
    private static let reaperDialogWid: CGWindowID = 4557 // "Insert Multiple Media Items"
    private static let finderWid: CGWindowID = 664        // "Liebesleid"

    private func window(_ wid: CGWindowID, _ pid: pid_t, _ title: String, order: Int,
                        isMinimized: Bool = false) -> TrackedWindow {
        TrackedWindow(id: "wid-\(wid)", wid: wid, pid: pid, title: title,
            size: CGSize(width: 800, height: 600), position: CGPoint(x: 10, y: 10),
            spaceIds: [4], spaceIndexes: [1], isOnAllSpaces: false, spaceIsBorrowed: false,
            isFullscreen: false, isFullscreenMirrored: false, isMinimized: isMinimized, isMainWindow: false,
            isWindowlessApp: false, cgsPhantomLatch: false, lastFocusOrder: order,
            creationOrder: Int(wid), hasThumbnail: true)
    }

    /// Finder frontmost with its window in front, REAPER's main window behind it — the state the capture
    /// starts from (the reporter had just alt-tabbed to Finder to drag the audio files).
    private func state(_ windows: [TrackedWindow], frontmost: pid_t) -> TrackedWindowState {
        var s = TrackedWindowState()
        s.windows = windows
        s.apps[Self.reaperPid] = TrackedApp(state: ApplicationState(pid: Self.reaperPid,
            bundleIdentifier: "com.cockos.reaper", localizedName: "REAPER", isHidden: false),
            isActive: frontmost == Self.reaperPid)
        s.apps[Self.finderPid] = TrackedApp(state: ApplicationState(pid: Self.finderPid,
            bundleIdentifier: "com.apple.finder", localizedName: "Finder", isHidden: false),
            isActive: frontmost == Self.finderPid)
        s.frontmostPid = frontmost
        s.visibleSpaces = [4]
        s.currentSpaceId = 4
        s.spaceIndexById = [4: 1]
        return s
    }

    private func order(_ state: TrackedWindowState, _ wid: CGWindowID) -> Int? {
        state.window(wid)?.lastFocusOrder
    }

    // MARK: the front of the MRU after a removal (#5346)

    /// Another app holds slot 1, but focus never crosses apps because a window closed: the frontmost app's
    /// own next window takes the front, and `.applyFocus` names it so the live model agrees.
    func testRemovingTheFocusedWindowPromotesTheFrontmostAppsNextWindow() {
        var s = state([
            window(Self.reaperDialogWid, Self.reaperPid, "Insert Multiple Media Items", order: 0),
            window(Self.finderWid, Self.finderPid, "Liebesleid", order: 1),
            window(Self.reaperMainWid, Self.reaperPid, "Country Dance - REAPER v7.78", order: 2),
        ], frontmost: Self.reaperPid)
        let effects = WindowEventReducer.reduce(&s, .windowDestroyed(wid: Self.reaperDialogWid))
        XCTAssertTrue(effects.contains(.applyFocus(Self.reaperMainWid)))
        XCTAssertEqual(order(s, Self.reaperMainWid), 0)
    }

    /// An ordinary close of a background window leaves slot 0 alone — nothing to repair, nothing bumped.
    func testRemovingANonFrontWindowPromotesNothing() {
        var s = state([
            window(Self.reaperMainWid, Self.reaperPid, "Country Dance - REAPER v7.78", order: 0),
            window(Self.finderWid, Self.finderPid, "Liebesleid", order: 1),
            window(Self.reaperDialogWid, Self.reaperPid, "Insert Multiple Media Items", order: 2),
        ], frontmost: Self.reaperPid)
        let effects = WindowEventReducer.reduce(&s, .windowDestroyed(wid: Self.reaperDialogWid))
        XCTAssertFalse(effects.contains { if case .applyFocus = $0 { return true } else { return false } })
        XCTAssertEqual(order(s, Self.reaperMainWid), 0)
    }

    func testWindowServerDestroyRetiresTheSurfaceBeforeRemovingIt() {
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "Main", order: 0)],
            frontmost: Self.reaperPid)
        let effects = WindowEventReducer.reduce(&s, .windowDestroyed(wid: Self.reaperMainWid))
        XCTAssertEqual(s.window(Self.reaperMainWid)?.lifecycle, .surfaceEnded)
        let retirement = effects.firstIndex(of: .retireSurface(Self.reaperMainWid))
        let removal = effects.firstIndex(of: .removeWindow(Self.reaperMainWid))
        XCTAssertNotNil(retirement)
        XCTAssertNotNil(removal)
        XCTAssertLessThan(retirement!, removal!)
    }

    func testAxElementEndWaitsForCrossSourceReconciliation() {
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "Main", order: 0)],
            frontmost: Self.reaperPid)
        let effects = WindowEventReducer.reduce(&s, .axElementEnded(wid: Self.reaperMainWid))
        XCTAssertEqual(s.window(Self.reaperMainWid)?.lifecycle, .axElementEnded)
        XCTAssertTrue(effects.contains(.reconcileAxElementEnd(Self.reaperMainWid)))
        XCTAssertFalse(effects.contains(.removeWindow(Self.reaperMainWid)))
        _ = WindowEventReducer.reduce(&s, .axElementReconciled(
            wid: Self.reaperMainWid, verdict: .inconclusive))
        XCTAssertEqual(s.window(Self.reaperMainWid)?.lifecycle, .replacementPending)
    }

    func testAxReplacementHealsWhileConfirmedCloseRemoves() {
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "Main", order: 0)],
            frontmost: Self.reaperPid)
        _ = WindowEventReducer.reduce(&s, .axElementEnded(wid: Self.reaperMainWid))
        let healed = WindowEventReducer.reduce(&s, .axElementReconciled(
            wid: Self.reaperMainWid, verdict: .replacementFound))
        XCTAssertEqual(s.window(Self.reaperMainWid)?.lifecycle, .alive)
        XCTAssertFalse(healed.contains(.removeWindow(Self.reaperMainWid)))
        _ = WindowEventReducer.reduce(&s, .axElementEnded(wid: Self.reaperMainWid))
        let closed = WindowEventReducer.reduce(&s, .axElementReconciled(
            wid: Self.reaperMainWid, verdict: .confirmedClosed))
        XCTAssertEqual(s.window(Self.reaperMainWid)?.lifecycle, .confirmedClosed)
        XCTAssertTrue(closed.contains(.removeWindow(Self.reaperMainWid)))
    }

    /// The frontmost app's last window closes: there is nothing of its own left to promote, so the global
    /// shift stands (the app is on its way to windowless).
    func testRemovingTheFrontmostAppsOnlyWindowPromotesNothing() {
        var s = state([
            window(Self.reaperMainWid, Self.reaperPid, "Country Dance - REAPER v7.78", order: 0),
            window(Self.finderWid, Self.finderPid, "Liebesleid", order: 1),
        ], frontmost: Self.reaperPid)
        let effects = WindowEventReducer.reduce(&s, .windowDestroyed(wid: Self.reaperMainWid))
        XCTAssertFalse(effects.contains { if case .applyFocus = $0 { return true } else { return false } })
    }

    /// A minimized window is off screen and never received the focus the closing window gave up.
    func testMinimizedWindowsAreNotPromoted() {
        var s = state([
            window(Self.reaperDialogWid, Self.reaperPid, "Insert Multiple Media Items", order: 0),
            window(Self.reaperMainWid, Self.reaperPid, "Country Dance - REAPER v7.78", order: 1,
                isMinimized: true),
            window(Self.finderWid, Self.finderPid, "Liebesleid", order: 2),
        ], frontmost: Self.reaperPid)
        let effects = WindowEventReducer.reduce(&s, .windowDestroyed(wid: Self.reaperDialogWid))
        XCTAssertFalse(effects.contains(.applyFocus(Self.reaperMainWid)))
    }

    func testMinimizingTheFocusedWindowPromotesTheFrontmostAppsNextWindow() {
        var s = state([
            window(Self.reaperDialogWid, Self.reaperPid, "Dialog", order: 0),
            window(Self.finderWid, Self.finderPid, "Liebesleid", order: 1),
            window(Self.reaperMainWid, Self.reaperPid, "Main", order: 2),
        ], frontmost: Self.reaperPid)
        s.carried.offScreen.insert(Self.reaperDialogWid)
        let snapshot = WsWindowSnapshot(wid: Self.reaperDialogWid, position: CGPoint(x: 10, y: 10),
            size: CGSize(width: 800, height: 600), isFullscreen: false, isVisible: false, isMinimized: true)
        let effects = WindowEventReducer.reduce(&s, .windowServerStateRead([snapshot]))
        XCTAssertTrue(effects.contains(.applyFocus(Self.reaperMainWid)))
        XCTAssertEqual(s.mruFrontWid, Self.reaperMainWid)
    }

    /// An inactive tab is off screen too — what the user sees is its group's representative.
    func testInactiveTabsAreNotPromoted() {
        let backgroundTab: CGWindowID = 4600
        var s = state([
            window(Self.reaperDialogWid, Self.reaperPid, "Insert Multiple Media Items", order: 0),
            window(backgroundTab, Self.reaperPid, "background tab", order: 1),
            window(Self.reaperMainWid, Self.reaperPid, "Country Dance - REAPER v7.78", order: 2),
        ], frontmost: Self.reaperPid)
        s.formGroup([Self.reaperMainWid, backgroundTab], representative: Self.reaperMainWid, reason: "test")
        XCTAssertTrue(s.isTabbed(s.window(backgroundTab)!), "precondition: an inactive tab")
        let effects = WindowEventReducer.reduce(&s, .windowDestroyed(wid: Self.reaperDialogWid))
        XCTAssertTrue(effects.contains(.applyFocus(Self.reaperMainWid)))
        XCTAssertFalse(effects.contains(.applyFocus(backgroundTab)))
    }

    // MARK: nothing physical may move the order

    /// Finder in front with REAPER's window behind it: the state every rule below starts from.
    private func twoAppState() -> TrackedWindowState {
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "REAPER", order: 1),
                       window(Self.finderWid, Self.finderPid, "Finder", order: 0)],
                      frontmost: Self.finderPid)
        s.now = 100
        return s
    }

    /// **The whole point of the rework.** A raw focus event is the WindowServer saying a window came
    /// forward. That is not the user going there, and it may not say so.
    func testAFocusEventCannotMoveTheOrder() {
        var s = twoAppState()
        _ = WindowEventReducer.reduce(&s, .windowFocused(wid: Self.reaperMainWid, now: 100))
        XCTAssertEqual(s.mruFrontWid, Self.finderWid,
                       "an 808 moved the front; physical evidence is not attention")
    }

    func testAnOrderInCannotMoveTheOrder() {
        var s = twoAppState()
        _ = WindowEventReducer.reduce(&s, .windowOrderedIn(wid: Self.reaperMainWid, now: 100,
                                                           inSpaceTransition: false))
        XCTAssertEqual(s.mruFrontWid, Self.finderWid)
    }


    /// A committed decision is the one thing that may claim the user moved.
    func testCommittedAttentionMovesTheOrder() {
        var s = twoAppState()
        let effects = WindowEventReducer.reduce(&s, .attentionCommitted(wid: Self.reaperMainWid,
                                                                        observed: Self.reaperMainWid, at: 100))
        XCTAssertEqual(s.mruFrontWid, Self.reaperMainWid)
        XCTAssertTrue(effects.contains(.refreshUiImmediately(wids: [Self.reaperMainWid, Self.finderWid])))
    }

    /// A commit naming a window nobody tracks is ignored rather than fabricating one.
    func testCommittedAttentionForAnUnknownWindowIsIgnored() {
        var s = twoAppState()
        let effects = WindowEventReducer.reduce(&s, .attentionCommitted(wid: 999_999, observed: 999_999, at: 100))
        XCTAssertTrue(effects.isEmpty)
        XCTAssertEqual(s.mruFrontWid, Self.finderWid)
    }

    /// **Closing the front window is not a claim about the user.** Something has to take the slot, so this
    /// repair keeps writing where no attention decision exists. The successor stays inside the same app,
    /// which is the #5346 rule this test must not disturb.
    func testAStructuralRepairStillWrites() {
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "REAPER", order: 0),
                       window(Self.reaperDialogWid, Self.reaperPid, "Dialog", order: 1),
                       window(Self.finderWid, Self.finderPid, "Finder", order: 2)],
                      frontmost: Self.reaperPid)
        s.now = 100
        _ = WindowEventReducer.reduce(&s, .windowDestroyed(wid: Self.reaperMainWid))
        XCTAssertEqual(s.mruFrontWid, Self.reaperDialogWid,
                       "the front window closed and its app's next window did not take the slot")
    }

    // MARK: a window being born

    /// The birth sequence the WindowServer actually emits, from the live capture: a create, a join of the
    /// visible Space, then discovery once the OS has sized the window (it is published at 0×0 first).
    private func birthSteps(_ wid: CGWindowID, _ pid: pid_t, _ title: String) -> [TestReducerRunner.Step] {
        [.input(.windowCreated(wid: wid, now: 100, inSpaceTransition: false)),
         .input(.spaceMembershipChanged(wid: wid, spaceId: 4, added: true, now: 100,
                                        inSpaceTransition: false)),
         .track(window(wid, pid, title, order: 9)),
         .input(.discoveryLanded(wid: wid, accepted: true, newlyTracked: true, adoptedAsInactiveTab: false,
                                 queriedSpaceIds: [4], isOrderedIn: true, tabTitles: nil, tabGroupToken: nil))]
    }

    /// **A window being born is not the user going to it**, seen live. The user is in Finder while an app
    /// finishes launching behind them; its windows must be discovered without taking the front. The join of
    /// the visible Space is what used to front them: it asserts a promotion, which is right for a REUSED wid
    /// arriving with no create event (a tab switch mints no create) and wrong for every birth.
    func testAWindowBornInTheBackgroundDoesNotTakeTheFront() {
        var s = state([window(Self.finderWid, Self.finderPid, "Finder", order: 0)], frontmost: Self.finderPid)
        s.now = 100
        let harness = TestReducerRunner(initial: s)
        harness.run(birthSteps(Self.reaperDialogWid, Self.reaperPid, "Untitled"))
        XCTAssertEqual(harness.state.mruFrontWid, Self.finderWid,
                       "a window opening behind the user took the front from where they actually were")
        XCTAssertNotNil(harness.state.window(Self.reaperDialogWid), "and it must still be discovered")
    }

    /// The same rule when the born window belongs to the app the user is ALREADY in, seen live: twenty
    /// windows opening at once is not twenty visits, so the window they were on keeps the front. Being in
    /// the app is what makes this the harder half — the frontmost-app test the circumstantial promotion
    /// applies would pass here.
    func testABurstOfWindowsBornInTheFrontmostAppDoesNotMoveTheFront() {
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "REAPER", order: 0),
                       window(Self.finderWid, Self.finderPid, "Finder", order: 1)],
                      frontmost: Self.reaperPid)
        s.now = 100
        let harness = TestReducerRunner(initial: s)
        for (i, wid) in [CGWindowID(5001), 5002, 5003].enumerated() {
            harness.run(birthSteps(wid, Self.reaperPid, "Burst \(i)"))
        }
        XCTAssertEqual(harness.state.mruFrontWid, Self.reaperMainWid,
                       "windows being born in the frontmost app moved the front off the window the user was on")
    }

    // MARK: tabs — the app naming one of its own tabs

    /// **A tab switch is an app naming a background tab.** Attention lands on the tile that stands for the
    /// group, so the driver maps the named tab to the current representative; the fact that it named a
    /// DIFFERENT member is the switch itself. Without moving the representative first, the order gets bumped
    /// and the tile keeps showing the tab the user just left.
    func testNamingABackgroundTabMovesTheGroupRepresentative() {
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "Tab A", order: 0),
                       window(Self.reaperDialogWid, Self.reaperPid, "Tab B", order: 1)],
                      frontmost: Self.reaperPid)
        s.now = 100
        _ = s.formGroup([Self.reaperMainWid, Self.reaperDialogWid], representative: Self.reaperMainWid,
                        reason: "test")
        _ = WindowEventReducer.reduce(&s, .attentionCommitted(wid: Self.reaperMainWid,
                                                              observed: Self.reaperDialogWid, at: 100))
        let group = s.groups.groupId(of: Self.reaperDialogWid)
        XCTAssertEqual(group.flatMap { s.groups.representativeByGroup[$0] }, Self.reaperDialogWid,
                       "the app said this tab is active; the group still shows the other one")
        XCTAssertEqual(s.mruFrontWid, Self.reaperDialogWid)
    }

    func testSemanticFocusCarriesAHeldGroupPastAnAmbiguousPhysicalJoin() {
        let incomingWid: CGWindowID = 900
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "Tab A", order: 0),
                       window(Self.reaperDialogWid, Self.reaperPid, "Tab B", order: 1),
                       window(incomingWid, Self.reaperPid, "Tab C", order: 2)], frontmost: Self.reaperPid)
        s.now = 100
        s.windows[0].spaceIds = []
        s.windows[0].lastLeftSpaceId = 4
        s.held.insert(Self.reaperMainWid)
        _ = s.formGroup([Self.reaperMainWid, Self.reaperDialogWid], representative: Self.reaperMainWid,
                        reason: "test")
        _ = WindowEventReducer.reduce(&s, .attentionCommitted(wid: incomingWid, observed: incomingWid, at: 100))
        XCTAssertEqual(Set(s.groups.siblingWids(of: incomingWid) ?? []),
                       Set([Self.reaperMainWid, Self.reaperDialogWid, incomingWid]))
        XCTAssertFalse(s.groups.isTabbed(incomingWid))
    }

    func testSemanticFocusDoesNotCarryAHeldGroupFromAnotherSpace() {
        let incomingWid: CGWindowID = 900
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "Tab A", order: 0),
                       window(Self.reaperDialogWid, Self.reaperPid, "Tab B", order: 1),
                       window(incomingWid, Self.reaperPid, "Tab C", order: 2)], frontmost: Self.reaperPid)
        s.now = 100
        s.windows[0].spaceIds = []
        s.windows[0].lastLeftSpaceId = 99
        s.held.insert(Self.reaperMainWid)
        _ = s.formGroup([Self.reaperMainWid, Self.reaperDialogWid], representative: Self.reaperMainWid,
                        reason: "test")
        _ = WindowEventReducer.reduce(&s, .attentionCommitted(wid: incomingWid, observed: incomingWid, at: 100))
        XCTAssertNil(s.groups.groupId(of: incomingWid))
    }

    /// **A held window carrying NO group is not a handover.** Live capture (2026-09-09, macOS 26): two
    /// 620x472 windows of one app, the BACKGROUND one sent to fullscreen. Entering fullscreen takes that
    /// window Space-less while the transition mints its own surfaces, which arms the hold; 519ms later the
    /// app answers the activation with its other window, still on the windowed Space the held one just left.
    /// The merge made two separate windows one group, and nothing re-splits an established group, so the
    /// window that went fullscreen read `shown=false tabbed=true` for the rest of the session — the reported
    /// "a window disappears after leaving fullscreen".
    func testSemanticFocusDoesNotCarryAHeldWindowThatCarriesNoGroup() {
        let incomingWid: CGWindowID = 900
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "Window 1", order: 0),
                       window(incomingWid, Self.reaperPid, "Window 2", order: 1)], frontmost: Self.reaperPid)
        s.now = 100
        s.windows[0].spaceIds = []
        s.windows[0].lastLeftSpaceId = 4
        s.held.insert(Self.reaperMainWid)
        _ = WindowEventReducer.reduce(&s, .attentionCommitted(wid: incomingWid, observed: incomingWid, at: 100))
        XCTAssertNil(s.groups.groupId(of: incomingWid),
                     "two separate windows of one app were merged on the strength of a hold alone")
        XCTAssertNil(s.groups.groupId(of: Self.reaperMainWid))
    }

    func testUnrenderableNamedTabKeepsPresentableRepresentativeUntilSized() {
        var incoming = window(Self.reaperDialogWid, Self.reaperPid, "Tab B", order: 1)
        incoming.size = .zero
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "Tab A", order: 0), incoming],
                      frontmost: Self.reaperPid)
        s.now = 100
        _ = s.formGroup([Self.reaperMainWid, Self.reaperDialogWid], representative: Self.reaperMainWid,
                        reason: "test")
        _ = WindowEventReducer.reduce(&s, .attentionCommitted(wid: Self.reaperMainWid,
                                                              observed: Self.reaperDialogWid, at: 100))
        let group = s.groups.groupId(of: Self.reaperDialogWid)
        XCTAssertEqual(group.flatMap { s.groups.representativeByGroup[$0] }, Self.reaperMainWid)
        XCTAssertEqual(s.mruFrontWid, Self.reaperDialogWid)
    }

    /// **The minted chain is tab evidence even before the group exists.** Live capture (2026-09-10, macOS 26):
    /// a 5x cmd+T burst on Finder mints a wid per tab, each displacing the last before discovery reaches it,
    /// so `pendingGroupInheritance` carries the membership while no group is formed. An AX window-created
    /// answer landed 1.25s into the burst for a wid already handed on, attention admitted it, and with only
    /// the group check to go on it stood as a second tile for 250ms — the tab escaping its group that QA T-02
    /// asserts against.
    func testSemanticFocusCarriesAHeldWindowLinkedByTheMintedChain() {
        let incomingWid: CGWindowID = 900
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "Tab A", order: 0),
                       window(incomingWid, Self.reaperPid, "Tab B", order: 1)], frontmost: Self.reaperPid)
        s.now = 100
        s.windows[0].spaceIds = []
        s.windows[0].lastLeftSpaceId = 4
        s.held.insert(Self.reaperMainWid)
        s.carried.pendingGroupInheritance[901] = [Self.reaperMainWid, incomingWid]
        _ = WindowEventReducer.reduce(&s, .attentionCommitted(wid: incomingWid, observed: incomingWid, at: 100))
        XCTAssertEqual(Set(s.groups.siblingWids(of: incomingWid) ?? []), Set([Self.reaperMainWid, incomingWid]),
                       "a mid-burst adoption of a chain member was left standing as its own tile")
    }

    /// The chain must name BOTH sides: one that names only the held window is what a fullscreen transition
    /// arms, and the window the app answers with is not in it (#6017).
    func testSemanticFocusDoesNotCarryAHeldWindowOutsideTheChain() {
        let incomingWid: CGWindowID = 900
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "Window 1", order: 0),
                       window(incomingWid, Self.reaperPid, "Window 2", order: 1)], frontmost: Self.reaperPid)
        s.now = 100
        s.windows[0].spaceIds = []
        s.windows[0].lastLeftSpaceId = 4
        s.held.insert(Self.reaperMainWid)
        s.carried.pendingGroupInheritance[901] = [Self.reaperMainWid]
        _ = WindowEventReducer.reduce(&s, .attentionCommitted(wid: incomingWid, observed: incomingWid, at: 100))
        XCTAssertNil(s.groups.groupId(of: incomingWid))
        XCTAssertNil(s.groups.groupId(of: Self.reaperMainWid))
    }

    /// A window named outside any group is not a tab switch, and must not disturb membership.
    func testNamingAWindowInNoGroupJustMovesTheOrder() {
        var s = state([window(Self.reaperMainWid, Self.reaperPid, "REAPER", order: 1),
                       window(Self.finderWid, Self.finderPid, "Finder", order: 0)],
                      frontmost: Self.reaperPid)
        s.now = 100
        _ = WindowEventReducer.reduce(&s, .attentionCommitted(wid: Self.reaperMainWid,
                                                              observed: Self.reaperMainWid, at: 100))
        XCTAssertEqual(s.mruFrontWid, Self.reaperMainWid)
        XCTAssertTrue(s.groups.membersByGroup.isEmpty)
    }


    // MARK: App Exposé — the re-show around a pick

    /// A window of the front app the user had not opened in a long time — the one the reporter picked out of
    /// App Exposé, and the one their MRU came back claiming was the most recent.
    private static let reaperStaleWid: CGWindowID = 4601

    /// The wids in the order the switcher would draw them.
    private func mruWids(_ state: TrackedWindowState) -> [CGWindowID] {
        state.windows.sorted { $0.lastFocusOrder < $1.lastFocusOrder }.compactMap { $0.wid }
    }

    /// **Picking a window in App Exposé moves that window, and nothing else.**
    ///
    /// App Exposé shows every window of the front app, and the pick puts them all back at once: a burst of
    /// order-ins in the OS's layout order rather than the user's, with no order-out in front of them, either
    /// side of the click that named the window they chose. Read as in-app raises, those order-ins walk the
    /// app's OTHER windows to the top behind the pick, which is how a Chrome window untouched for hours came
    /// back sitting at the front of the switcher.
    ///
    /// The #5936 mute could never have covered this: it was armed when Exposé OPENED and sized to be over
    /// before a hand could reach the trackpad, while the pick comes seconds later. Nothing mutes anything
    /// here — an 815 is not entitled to the order in the first place — and this pins the whole gesture rather
    /// than that one rule.
    ///
    /// Another app's window sits BETWEEN the app's own windows in the order, because that is what makes the
    /// damage visible: with them already adjacent, a burst that re-fronts all three changes nothing anybody
    /// can see.
    func testAnAppExposePickMovesOnlyThePickedWindow() {
        var s = state([
            window(Self.reaperMainWid, Self.reaperPid, "where the user was", order: 0),
            window(Self.finderWid, Self.finderPid, "Finder", order: 1),
            window(Self.reaperDialogWid, Self.reaperPid, "another window of the app", order: 2),
            window(Self.reaperStaleWid, Self.reaperPid, "not opened in a long time", order: 3),
        ], frontmost: Self.reaperPid)
        s.now = 100
        let harness = TestReducerRunner(initial: s)
        let reshow = { (wid: CGWindowID, now: TimeInterval) -> TestReducerRunner.Step in
            .input(.windowOrderedIn(wid: wid, now: now, inSpaceTransition: false))
        }
        // the OS starts putting the desktop back before the click has been decided
        harness.run([reshow(Self.reaperDialogWid, 100.1), reshow(Self.reaperMainWid, 100.2)])
        XCTAssertEqual(mruWids(harness.state),
                       [Self.reaperMainWid, Self.finderWid, Self.reaperDialogWid, Self.reaperStaleWid],
                       "the re-show burst moved the order on its own; an 815 says a window is on screen, "
                       + "never that the user went to it")
        // the click on the thumbnail, which is the one thing here that names a window
        harness.run([.input(.attentionCommitted(wid: Self.reaperStaleWid, observed: Self.reaperStaleWid,
                                                at: 100.3))])
        // and the tail of the same burst, arriving after the pick
        harness.run([reshow(Self.reaperStaleWid, 100.4), reshow(Self.reaperDialogWid, 100.5),
                     .input(.windowFocused(wid: Self.reaperStaleWid, now: 100.5))])
        XCTAssertEqual(mruWids(harness.state),
                       [Self.reaperStaleWid, Self.reaperMainWid, Self.finderWid, Self.reaperDialogWid],
                       "App Exposé's pick moved more than the window it picked: the windows the user never "
                       + "chose came back at the front, ahead of the other app's window they had used since")
    }

}
