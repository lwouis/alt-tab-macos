import XCTest

/// Pins the OS-tab grouping decisions (`TabGroupResolver`) against canonical `TabWindow` snapshots, so the
/// geometry inference, the brittle AX-title sibling matching (the documented cause-B flap), the position
/// compatibility, and the group dissolution are regression-proof without the `Window` graph. See
/// TabGroupResolverSpecs.md.
final class TabGroupResolverTests: XCTestCase {

    private func tw(pid: pid_t = 1, wid: CGWindowID, size: CGSize? = CGSize(width: 800, height: 600),
                    position: CGPoint? = CGPoint(x: 100, y: 100), spaceIds: [UInt64] = [1],
                    title: String = "", isTabbed: Bool = false, isFullscreen: Bool = false,
                    isMinimized: Bool = false, tabbedSiblingWids: [CGWindowID]? = nil,
                    isOrderedIn: Bool = false, lastFocusOrder: Int = 0, tabCount: Int = 0,
                    tabGroupToken: TabGroupToken? = nil) -> TabWindow {
        TabWindow(pid: pid, wid: wid, size: size, position: position, spaceIds: spaceIds, title: title,
            isTabbed: isTabbed, isFullscreen: isFullscreen, isMinimized: isMinimized,
            tabbedSiblingWids: tabbedSiblingWids, isOrderedIn: isOrderedIn,
            lastFocusOrder: lastFocusOrder, tabCount: tabCount, tabGroupToken: tabGroupToken)
    }

    // MARK: - A. geometryGroups

    func testConfirmedVisiblePlusSpacelessIsAGroup() {
        // an AX-confirmed group (visible carries its `tabbedSiblingWids`) whose tab switch left a sibling
        // Space-less: geometry re-links it. This is the "pop-in" case geometry exists to catch.
        let visible = tw(wid: 1, spaceIds: [1], tabbedSiblingWids: [1, 2])
        let background = tw(wid: 2, spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, background]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2])])
    }

    func testFullscreenVisibleGroupsWithoutAxConfirmation() {
        // a tab added to an already-fullscreen window: AX exposes no readable AXTabGroup, so the visible tab
        // has no `tabbedSiblingWids`. The fullscreen exemption still groups its Space-less background tab.
        let visible = tw(wid: 1, spaceIds: [1], isFullscreen: true)
        let background = tw(wid: 2, spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, background]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2])])
    }

    func testOnScreenWindowsAreNotFoldedIntoAFullscreenNewcomer() {
        // #5954, from the reporter's `--detailed-list`: four Firefox windows at one frame (1147x719 @ 0,26),
        // one of them entering fullscreen, the other three reading Space-less. Geometry folded the three
        // behind the newcomer and the switcher showed ONE of the four — "a window is missing, and when it
        // comes back a different one goes missing". Firefox exposes no AXTabGroup (probed live), so the
        // fullscreen clause is the only confirmation available and nothing could ever dissolve the result.
        // The WindowServer's ordered-in bit is what the fold was missing: a real background tab is ordered
        // OUT, so an on-screen member is a real window whose Space membership we lost, not a tab.
        let size = CGSize(width: 1147, height: 719), pos = CGPoint(x: 0, y: 26)
        let goingFullscreen = tw(wid: 54689, size: size, position: pos, spaceIds: [9], isFullscreen: true,
            isOrderedIn: true, lastFocusOrder: 0)
        let verge = tw(wid: 34920, size: size, position: pos, spaceIds: [], isOrderedIn: true, lastFocusOrder: 1)
        let youtube = tw(wid: 34919, size: size, position: pos, spaceIds: [], isOrderedIn: true, lastFocusOrder: 2)
        let ipass = tw(wid: 34927, size: size, position: pos, spaceIds: [], isOrderedIn: true, lastFocusOrder: 3)
        XCTAssertEqual(TabGroupResolver.geometryGroups([goingFullscreen, verge, youtube, ipass]), [])
    }

    func testAnOrderedOutTabIsStillFoldedIntoItsFullscreenWindow() {
        // The other side, and the reason the bit is read rather than the Space alone: a genuine background
        // tab of a fullscreen window is ordered OUT and Space-less, and must still fold — this is
        // `testFullscreenVisibleGroupsWithoutAxConfirmation`'s shape with the bit spelled out.
        let visible = tw(wid: 1, spaceIds: [1], isFullscreen: true, isOrderedIn: true)
        let background = tw(wid: 2, spaceIds: [], isOrderedIn: false)
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, background]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2])])
    }

    func testTabCountConfirmsWhenTitlesCannot() {
        // #5785: stock Terminal composes its WINDOW title from components its TAB title has no setting for
        // ("~/Documents — -zsh ▸ -zsh — 80×23" vs "~/Documents"), so `matchSiblings` names nobody and
        // `tabbedSiblingWids` stays nil forever — the confirmation this gate normally waits for can never
        // arrive and the tabs churned as separate tiles. The AXTabGroup's COUNT is the half of that read
        // which is never in doubt, so it confirms the cluster on its own.
        let visible = tw(wid: 1, spaceIds: [1], title: "~/Documents — -zsh — 80×23", tabCount: 2)
        let background = tw(wid: 2, spaceIds: [], title: "~ — -zsh — 80×23")
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, background]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2])])
    }

    func testTabCountRefusesToFoldMoreCandidatesThanTabs() {
        // The bound on that new clause. AX says 2 tabs, so at most ONE background tab exists — a second
        // Space-less same-frame candidate means the cluster holds something that is NOT our tab (a separate
        // window gone transiently Space-less, or a second group of this app at the same frame). Which one is
        // the intruder is undecidable here and guessing would HIDE a real window, so refuse the whole fold.
        let visible = tw(wid: 1, spaceIds: [1], tabCount: 2)
        let background = tw(wid: 2, spaceIds: [])
        let intruder = tw(wid: 3, spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, background, intruder]), [])
    }

    func testTabCountBoundDoesNotApplyToAnAlreadyConfirmedCluster() {
        // The bound is scoped to the tab-count clause. Applied to the OTHER confirmations it breaks them: the
        // model legitimately holds more candidates than the window has tabs while a tab switch that mints new
        // wids is in flight, since the retired wids aren't swept yet (generator seed 163 — the incoming tile
        // lost its inherited thumbnail and flashed the app icon). AX-confirmed clusters fold as before.
        let visible = tw(wid: 1, spaceIds: [1], tabbedSiblingWids: [1, 2, 3], tabCount: 2)
        let background = tw(wid: 2, spaceIds: [])
        let retired = tw(wid: 3, spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, background, retired]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2, 3])])
    }

    func testTabCountKeepsACascadedMergedClusterWhole() {
        // Merge All Windows leaves every tab at its PRE-MERGE cascade position — the OS never converges their
        // frames — so the position split (`framePartitions`) put each tab in its own partition and no merged
        // group could form at all (measured live, 2026-07-30). Position is there to separate two WINDOWS
        // that merely share a size, and here AX has already answered that question: the visible declares 3
        // tabs and the cluster holds exactly 3 same-size members, so there is no room for a second window.
        let visible = tw(wid: 1, position: CGPoint(x: 158, y: 158), spaceIds: [1], tabCount: 3)
        let tabA = tw(wid: 2, position: CGPoint(x: 129, y: 129), spaceIds: [])
        let tabB = tw(wid: 3, position: CGPoint(x: 100, y: 100), spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, tabA, tabB]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2, 3])])
    }

    func testAnUnaccountedForMemberRestoresThePositionSplit() {
        // The waiver is EXACT, not a bound: one more same-size member than the visible declared tabs means the
        // cluster holds something that is NOT our tab, and across positions we can no longer tell which. This
        // is rec11's shape — two cascaded Finder windows, all tabs titled the same, AX reporting more titles
        // than there are tracked wids (Finder destroys a backgrounded tab's window) — where position is the
        // only fact separating the two windows.
        //
        // Shaped so exactness is the ONLY thing refusing it: the visible is AX-confirmed (it carries a link),
        // which is exactly the case that skips the tab-count BOUND — the other, independent refusal — because
        // a wid-minting switch in flight legitimately leaves more candidates than tabs (seed 163). So a `<=`
        // waiver would fold the unrelated window at a third position and hide it.
        let visible = tw(wid: 1, position: CGPoint(x: 158, y: 158), spaceIds: [1],
                         tabbedSiblingWids: [1, 2], tabCount: 2)
        let ownTab = tw(wid: 2, position: CGPoint(x: 129, y: 129), spaceIds: [], tabbedSiblingWids: [1, 2])
        let other = tw(wid: 3, position: CGPoint(x: 100, y: 100), spaceIds: [])
        for group in TabGroupResolver.geometryGroups([visible, ownTab, other]) {
            XCTAssertFalse(group.siblingWids.contains(3),
                           "#3 is a separate window at (100,100) — 2 declared tabs cannot account for 3 members")
        }
    }

    func testAMemberOfAnotherGroupRestoresThePositionSplit() {
        // The count matching the cluster size does NOT mean the cluster is one window: a tabbed window's
        // members drift apart in size as its tab bar resizes it, so a size cluster routinely holds a SUBSET of
        // each of two windows and totals the tab count of one by coincidence. Generator seed 27 — window A
        // (3 tabs) and window B (2 tabs), cluster = {A's active, B's held ex-active} against A's declared 2.
        // A's active was the most recently focused, so the "geometry never merges two groups" filter waived
        // itself as a sanctioned takeover, claimed B's member, and the union bridged the rest: ONE group over
        // both real windows, B showing ZERO tiles. A link reaching outside the cluster is a window we can't
        // see here, and across positions the takeover exception has nothing to stand on.
        let visibleA = tw(wid: 1, position: CGPoint(x: 158, y: 158), spaceIds: [1], lastFocusOrder: 0, tabCount: 2)
        var heldExActiveOfB = tw(wid: 2, position: CGPoint(x: 129, y: 129), spaceIds: [1],
                                 tabbedSiblingWids: [2, 3], lastFocusOrder: 1)
        heldExActiveOfB.isHeld = true
        heldExActiveOfB.spaceIsBorrowed = true
        for group in TabGroupResolver.geometryGroups([visibleA, heldExActiveOfB]) {
            XCTAssertFalse(group.siblingWids.contains(1) && group.siblingWids.contains(2),
                           "#2 belongs to window B's group [2, 3] — A at (158,158) must not annex it")
        }
    }

    func testMergedClusterStillNeedsTheSizeToMatch() {
        // The waiver is only about POSITION. Size is what survives a merge intact (measured: the tabs' frames
        // freeze at their pre-merge origins but the size is the parent's), so a same-app window of a DIFFERENT
        // size is not in the cluster at all and no tab count can pull it in.
        let visible = tw(wid: 1, position: CGPoint(x: 158, y: 158), spaceIds: [1], tabCount: 2)
        let other = tw(wid: 2, size: CGSize(width: 400, height: 300), position: CGPoint(x: 129, y: 129), spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, other]), [])
    }

    func testStaleTabCountAloneDoesNotConfirm() {
        // A window whose tabs are gone must not keep the gate open. `tabCount` is retired by the reducer when
        // a read returns no AXTabGroup for a window that is also in no group, so a lone window reads 0 here
        // and this stays the #5830 case below.
        let visible = tw(wid: 1, spaceIds: [1], tabCount: 0)
        let spaceless = tw(wid: 2, spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, spaceless]), [])
    }

    func testNormalUnconfirmedNotGrouped() {
        // #5830: separate normal windows of one app sharing a default size, one briefly Space-less (a flaky
        // CGS read or a mid-transition strip). Not fullscreen, never AX-confirmed as tabs → NOT grouped.
        let visible = tw(wid: 1, spaceIds: [1])
        let spaceless = tw(wid: 2, spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, spaceless]), [])
    }

    func testTwoVisibleSameSizeNotGrouped() {
        // two separate real windows of the same size: both hold a Space, so neither is a background tab.
        let a = tw(wid: 1, spaceIds: [1])
        let b = tw(wid: 2, spaceIds: [1])
        XCTAssertEqual(TabGroupResolver.geometryGroups([a, b]), [])
    }

    func testDifferentSizesNotGrouped() {
        let a = tw(wid: 1, size: CGSize(width: 800, height: 600), spaceIds: [1])
        let b = tw(wid: 2, size: CGSize(width: 400, height: 300), spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([a, b]), [])
    }

    func testDifferentAppsNotGrouped() {
        let a = tw(pid: 1, wid: 1, spaceIds: [1])
        let b = tw(pid: 2, wid: 2, spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([a, b]), [])
    }

    func testMinimizedSpacelessNotGrouped() {
        let visible = tw(wid: 1, spaceIds: [1])
        let minimized = tw(wid: 2, spaceIds: [], isMinimized: true)
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, minimized]), [])
    }

    func testSizelessExcluded() {
        let visible = tw(wid: 1, spaceIds: [1])
        let sizeless = tw(wid: 2, size: nil, spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, sizeless]), [])
    }

    func testSingleCandidateNoGroup() {
        XCTAssertEqual(TabGroupResolver.geometryGroups([tw(wid: 1, spaceIds: [1])]), [])
    }

    func testMultipleBackgroundTabsGroupUnderVisible() {
        let visible = tw(wid: 1, spaceIds: [1], tabbedSiblingWids: [1, 2, 3])
        let bg1 = tw(wid: 2, spaceIds: [])
        let bg2 = tw(wid: 3, spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, bg1, bg2]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2, 3])])
    }

    func testFullscreenFoldsNotYetBackgroundedOldTab() {
        // A new tab in a FULLSCREEN window takes over (new active, its own fullscreen flag not detected yet)
        // while the previous active still holds the fullscreen Space (its 1326 lags). Both on-screen on the
        // same Space → the old one is folded in as background so the group is one tile, not two.
        let newActive = tw(wid: 1, spaceIds: [10], isFullscreen: false)  // new tab, fullscreen not yet detected
        let oldActive = tw(wid: 2, spaceIds: [10], isFullscreen: true)   // was active, still on the fullscreen Space
        XCTAssertEqual(TabGroupResolver.geometryGroups([newActive, oldActive]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2])])
    }

    func testTwoSeparateFullscreenWindowsNotMerged() {
        // Two SEPARATE fullscreen windows of one app, same size: each holds its OWN fullscreen Space, so
        // neither the same-Space fold nor a Space-less background links them — they stay two tiles.
        let a = tw(wid: 1, spaceIds: [10], isFullscreen: true)
        let b = tw(wid: 2, spaceIds: [20], isFullscreen: true)
        XCTAssertEqual(TabGroupResolver.geometryGroups([a, b]), [])
    }

    func testJoinsExistingGroupWhenBackgroundAlreadyTabbed() {
        // A new active tab of a FULLSCREEN group: AX can't read its AXTabGroup and its own fullscreen flag
        // lags discovery, so the visible is unconfirmed — but a Space-less same-size background tab is ALREADY
        // grouped (tabbedSiblingWids), which confirms the cluster is a real tab group the new visible joins.
        // Without this the new tab stayed a separate 2nd tile on fullscreen tab switches.
        let visible = tw(wid: 1, spaceIds: [1])  // new active: not fullscreen, no link yet
        let bgTabbed = tw(wid: 2, spaceIds: [], isTabbed: true, tabbedSiblingWids: [3, 2])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, bgTabbed]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2])])
    }

    func testDoesNotAdoptATabWhoseGroupStillHasItsVisible() {
        // The counterpart of the test above: same shape, but wid 3 — a sibling of the background's OWN group —
        // is still on-screen holding a Space. That group is LIVE, so wid 2 backgrounded INSIDE it (a plain tab
        // switch) and is nobody else's to take. Geometry only ever guesses, and same-size same-app windows are
        // the norm (every Finder window is 920×436), so adopting here stole a real window's tab and hid it.
        let visible = tw(wid: 1, spaceIds: [1])
        let bgTabbed = tw(wid: 2, spaceIds: [], isTabbed: true, tabbedSiblingWids: [3, 2])
        let itsVisible = tw(wid: 3, spaceIds: [1], isTabbed: true, tabbedSiblingWids: [3, 2])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, bgTabbed, itsVisible]), [])
    }

    func testGeometryPrefersEstablishedVisibleOverBackgroundTab() {
        // Hysteresis: `updateState` backfills the active's Space onto every background tab, so several members
        // hold a Space. Geometry must keep the ESTABLISHED visible (`!isTabbed`) as the representative, not
        // reassign it to a background tab that merely also holds a (backfilled) Space — that flip changed
        // which wid is shown and flickered its thumbnail. Ordered so a tabbed member comes first.
        let tabbedBg = tw(wid: 1, spaceIds: [1], isTabbed: true, tabbedSiblingWids: [3, 1, 2])
        let realVisible = tw(wid: 3, spaceIds: [1], isTabbed: false, tabbedSiblingWids: [3, 1, 2])
        let spaceless = tw(wid: 2, spaceIds: [], isTabbed: true, tabbedSiblingWids: [3, 1, 2])
        XCTAssertEqual(TabGroupResolver.geometryGroups([tabbedBg, realVisible, spaceless]),
            [GeometryGroup(visibleWid: 3, backgroundWids: [2])])
    }

    // MARK: - B. matchSiblings

    func testMatchesInactiveSiblingByTitle() {
        let active = tw(wid: 1, title: "git")
        let sibling = tw(wid: 2, spaceIds: [], title: "lwouis")
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["git", "lwouis"],
            sameAppWindows: [active, sibling])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1, 2], matchedWids: [2], untrackedTitles: [], toUntabWids: []))
    }

    func testDuplicateTitleRemovedOnce() {
        let active = tw(wid: 1, title: "git")
        let other = tw(wid: 2, spaceIds: [], title: "git")
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["git", "git"],
            sameAppWindows: [active, other])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1, 2], matchedWids: [2], untrackedTitles: [], toUntabWids: []))
    }

    func testOnScreenWindowNeverClaimedAsTab() {
        // An on-Space, non-tabbed window is by definition NOT an inactive tab — even with a matching title
        // and close position (Finder cmd-N: new window, same name, cascaded ~28px). Without this, the new
        // window was claimed to fill a title whose real tab has no window and vanished from the switcher.
        let active = tw(wid: 1, title: "lwouis")
        let newWindow = tw(wid: 2, position: CGPoint(x: 128, y: 128), spaceIds: [1], title: "lwouis")
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["lwouis", "lwouis"],
            sameAppWindows: [active, newWindow])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: ["lwouis"], toUntabWids: []))
    }

    func testFullscreenWindowIsNeverClaimedAsAWindowedGroupsTab() {
        // rec24c: switching Spaces TO a fullscreen window made it transiently Space-less (transition
        // noise), its shared "lwouis" title matched a windowed group's active, and positionsCompatible's
        // fullscreen waiver would otherwise let the windowed group annex the fullscreen WINDOW. The
        // fullscreen Space invariant forbids it: a fullscreen window is its own window on its own Space,
        // never a windowed group's tab. Space-less BUT fullscreen ⇒ not claimable.
        let active = tw(wid: 1, position: CGPoint(x: 260, y: 392), spaceIds: [3628], title: "lwouis")
        let fullscreen = tw(wid: 2, position: CGPoint(x: 0, y: 0), spaceIds: [], title: "lwouis",
            isFullscreen: true)
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["lwouis", "lwouis"],
            sameAppWindows: [active, fullscreen])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: ["lwouis"], toUntabWids: []))
    }

    func testUntrackedTitleReported() {
        let active = tw(wid: 1, title: "git")
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["git", "lwouis"],
            sameAppWindows: [active])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: ["lwouis"], toUntabWids: []))
    }

    func testStillTabbedSiblingKeptDespiteNoTitle() {
        // #5830 stability: a window still tabbed into this group (isTabbed + tabbedSiblingWids ∋ active) is
        // kept even when no AX title names it — a renamed/duplicate title must not flap it out.
        let active = tw(wid: 1, title: "git")
        let sibling = tw(wid: 2, title: "old", isTabbed: true, tabbedSiblingWids: [1, 2])
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["git"],
            sameAppWindows: [active, sibling])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1, 2], matchedWids: [2], untrackedTitles: [], toUntabWids: []))
    }

    func testDuplicateTitlePrefersTheExistingGroupRepresentative() {
        let active = tw(wid: 1, title: "same", tabbedSiblingWids: [1, 3])
        let unattached = tw(wid: 2, spaceIds: [], title: "same")
        var representative = tw(wid: 3, spaceIds: [1], title: "same", tabbedSiblingWids: [1, 3])
        representative.isHeld = true
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["same", "same"],
                                                sameAppWindows: [active, unattached, representative])
        XCTAssertEqual(m.siblingWids, [1, 3])
        XCTAssertEqual(m.toUntabWids, [])
    }

    func testDepartedSiblingUntabbedOnceNoLongerTabbed() {
        // Once the departed tab's own AX read clears its `isTabbed` (it became a standalone window), the next
        // match of the old active un-tabs it (clears the stale link). This is how a real drag-out settles.
        let active = tw(wid: 1, title: "git")
        let departed = tw(wid: 2, title: "old", isTabbed: false, tabbedSiblingWids: [1, 2])
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["git"],
            sameAppWindows: [active, departed])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: [], toUntabWids: [2]))
    }

    func testOtherGroupTabsNotUntabbed() {
        // A same-app window belonging to a DIFFERENT tab group (its `tabbedSiblingWids` doesn't contain this
        // active) is neither kept nor un-tabbed here — the two groups don't churn each other (#5830).
        let active = tw(wid: 1, title: "git")
        let otherGroupTab = tw(wid: 9, title: "x", isTabbed: true, tabbedSiblingWids: [8, 9])
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["git"],
            sameAppWindows: [active, otherGroupTab])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: [], toUntabWids: []))
    }

    func testNonTabbedUnmatchedNotUntabbed() {
        let active = tw(wid: 1, title: "git")
        let other = tw(wid: 2, title: "other")
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["git"],
            sameAppWindows: [active, other])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: [], toUntabWids: []))
    }

    func testFarPositionNotMatched() {
        let active = tw(wid: 1, position: CGPoint(x: 100, y: 100), title: "git")
        let far = tw(wid: 2, position: CGPoint(x: 900, y: 900), spaceIds: [], title: "lwouis")
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["git", "lwouis"],
            sameAppWindows: [active, far])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: ["lwouis"], toUntabWids: []))
    }

    func testZeroSizedMergeUsesTheExactTabCountAcrossFrozenFrames() {
        let active = tw(wid: 1, size: .zero, position: .zero, title: "A", tabCount: 4)
        let absorbed = [tw(wid: 2, position: CGPoint(x: 129, y: 129), spaceIds: [], title: "B"),
                        tw(wid: 3, position: CGPoint(x: 158, y: 158), spaceIds: [], title: "C"),
                        tw(wid: 4, position: CGPoint(x: 187, y: 187), spaceIds: [], title: "D")]
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["A", "B", "C", "D"],
                                                sameAppWindows: [active] + absorbed)
        XCTAssertEqual(m.siblingWids, [1, 2, 3, 4])
        XCTAssertEqual(m.untrackedTitles, [])
    }

    func testZeroSizedMergeKeepsThePromotedRepresentative() {
        // Measured live 2026-08-29: after Merge All Windows the merged active is 0x0, so normalize promotes
        // one absorbed tab to presentable representative — un-tabbed, wearing the Space it was lent. The
        // strict size gate on the borrowed leg can never pass against a 0x0 active, so the very next AX read
        // ejected that representative from its own group and it stood as a second Finder tile. The exact tab
        // count already proves the fold, so it waives the size test here as it does the position test.
        let active = tw(wid: 1, size: .zero, position: .zero, title: "A", tabbedSiblingWids: [1, 2, 3, 4],
                        lastFocusOrder: 0, tabCount: 4)
        var rep = tw(wid: 2, position: CGPoint(x: 129, y: 129), spaceIds: [1], title: "B",
                     tabbedSiblingWids: [1, 2, 3, 4], lastFocusOrder: 1)
        rep.spaceIsBorrowed = true
        let tabs = [tw(wid: 3, position: CGPoint(x: 158, y: 158), spaceIds: [], title: "C", isTabbed: true,
                       tabbedSiblingWids: [1, 2, 3, 4]),
                    tw(wid: 4, position: CGPoint(x: 187, y: 187), spaceIds: [], title: "D", isTabbed: true,
                       tabbedSiblingWids: [1, 2, 3, 4])]
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["A", "B", "C", "D"],
                                                sameAppWindows: [active, rep] + tabs)
        XCTAssertEqual(m.siblingWids.sorted(), [1, 2, 3, 4])
        XCTAssertTrue(m.toUntabWids.isEmpty)
        XCTAssertTrue(m.untrackedTitles.isEmpty)
    }

    func testFramelessActiveKeepsThePromotedRepresentative() {
        // Measured live 2026-08-31: mid Cmd+T burst the incoming tab is 0x0, so normalize left the previous
        // tab as the group's presentable representative — un-tabbed and on screen, which no claim path can
        // re-take. The discovery read kept it; the plain `axMainWindow` read that landed in the same
        // millisecond had no `activeIsNewlyDiscovered` and untabbed it, and the burst drew 3 Finder tiles
        // instead of 2 until the geometry pass repaired it.
        let active = tw(wid: 3, size: .zero, position: .zero, title: "lwouis", tabbedSiblingWids: [1, 2, 3],
                        lastFocusOrder: 0, tabCount: 3)
        let rep = tw(wid: 2, title: "lwouis", tabbedSiblingWids: [1, 2, 3], isOrderedIn: true, lastFocusOrder: 1)
        let background = tw(wid: 1, spaceIds: [], title: "lwouis", isTabbed: true,
                            tabbedSiblingWids: [1, 2, 3], lastFocusOrder: 2)
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["lwouis", "lwouis", "lwouis"],
                                                sameAppWindows: [active, rep, background])
        XCTAssertEqual(m.siblingWids.sorted(), [1, 2, 3])
        XCTAssertEqual(m.toUntabWids, [], "ejecting the representative is what drew the third tile")
        XCTAssertEqual(m.untrackedTitles, [])
    }

    func testTitleMatchCannotTakeATabFromAnotherVisibleGroup() {
        let active = tw(wid: 1, title: "same", tabbedSiblingWids: [1, 2, 3], tabCount: 3)
        let own = tw(wid: 2, spaceIds: [], title: "same", isTabbed: true, tabbedSiblingWids: [1, 2, 3])
        let otherRep = tw(wid: 4, title: "same", tabbedSiblingWids: [4, 5, 6], isOrderedIn: true)
        let otherTab = tw(wid: 5, spaceIds: [], title: "same", isTabbed: true, tabbedSiblingWids: [4, 5, 6])
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["same", "same", "same"],
                                                sameAppWindows: [active, own, otherRep, otherTab])
        XCTAssertEqual(m.siblingWids, [1, 2])
        XCTAssertFalse(m.siblingWids.contains(5))
    }

    func testNewlyDiscoveredActiveClaimsOnScreenSameSizeSibling() {
        // The creation-race fix: a brand-new active tab (activeIsNewlyDiscovered) claims its previous active
        // tab even though that sibling still shows a stale Space (its 1326 hasn't landed) — same app, same
        // size, matching title — so the pair groups atomically and the old tab never flashes as a 2nd tile.
        let active = tw(wid: 1, title: "~")
        let oldActive = tw(wid: 2, spaceIds: [1], title: "~")  // still on-Space (stale), same size/pos
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["~", "~"],
            sameAppWindows: [active, oldActive], activeIsNewlyDiscovered: true)
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1, 2], matchedWids: [2], untrackedTitles: [], toUntabWids: []))
    }

    func testNewlyDiscoveredActiveKeepsTheInheritedPresentableRepresentative() {
        let active = tw(wid: 3, size: .zero, position: .zero, title: "~",
                        tabbedSiblingWids: [3, 2, 1], tabCount: 5)
        let oldRepresentative = tw(wid: 2, spaceIds: [1], title: "~", isTabbed: false,
                                   tabbedSiblingWids: [3, 2, 1], lastFocusOrder: 1)
        let inactive = tw(wid: 1, spaceIds: [], title: "~", isTabbed: true,
                          tabbedSiblingWids: [3, 2, 1], lastFocusOrder: 2)
        let m = TabGroupResolver.matchSiblings(active: active,
            axTitles: ["~", "~", "~", "~", "~"], sameAppWindows: [active, oldRepresentative, inactive],
            activeIsNewlyDiscovered: true)
        XCTAssertEqual(Set(m.siblingWids), Set([1, 2, 3]))
        XCTAssertFalse(m.toUntabWids.contains(2))
    }

    func testNewlyDiscoveredDoesNotClaimDifferentSizeWindow() {
        // Even a brand-new active tab only claims a SAME-size on-screen sibling: a different-size same-app
        // window is a separate window, not a backgrounded tab.
        let active = tw(wid: 1, size: CGSize(width: 800, height: 600), title: "~")
        let separate = tw(wid: 2, size: CGSize(width: 400, height: 300), spaceIds: [1], title: "~")
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["~", "~"],
            sameAppWindows: [active, separate], activeIsNewlyDiscovered: true)
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: ["~"], toUntabWids: []))
    }

    func testNewlyDiscoveredStillTitleGatedAcrossGroups() {
        // The on-screen claim stays title-gated so two coexisting same-app groups don't bleed: a same-size
        // on-screen window whose title isn't in this active's AXTabGroup is left alone.
        let active = tw(wid: 1, title: "A2")
        let otherGroup = tw(wid: 9, spaceIds: [1], title: "B1")  // same size, on-Space, different group's title
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["A1", "A2"],
            sameAppWindows: [active, otherGroup], activeIsNewlyDiscovered: true)
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: ["A1"], toUntabWids: []))
    }

    func testNotNewlyDiscoveredKeepsOnScreenProtection() {
        // The default path (a review / re-read, not a fresh discovery) keeps the strict rule: an on-screen
        // same-size same-title window is NOT claimed (the Finder cmd-N protection). Mirrors
        // testOnScreenWindowNeverClaimedAsTab but makes the flag-off contract explicit.
        let active = tw(wid: 1, title: "~")
        let onScreen = tw(wid: 2, spaceIds: [1], title: "~")
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["~", "~"],
            sameAppWindows: [active, onScreen], activeIsNewlyDiscovered: false)
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: ["~"], toUntabWids: []))
    }

    func testHeldWindowIsClaimableDespiteHoldingASpace() {
        // A held window is a backgrounding tab mid-swap; the Space it holds was borrowed onto it by the
        // adapter (anti-vanish), so it must not count as on-screen evidence against the claim (rec14).
        let active = tw(wid: 1, title: "~")
        var held = tw(wid: 2, spaceIds: [1], title: "~")  // holds a (borrowed) Space
        held.isHeld = true
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["~", "~"],
            sameAppWindows: [active, held])
        XCTAssertEqual(m.matchedWids, [2])
    }

    func testHeldWindowOfADifferentSizeIsNotClaimable() {
        // The held leg is size-gated: a held tab of a DIFFERENT same-position window (Terminal stacks all
        // its windows at one point) must not be claimable across groups.
        let active = tw(wid: 1, size: CGSize(width: 800, height: 600), title: "~")
        var held = tw(wid: 2, size: CGSize(width: 800, height: 604), spaceIds: [1], title: "~")
        held.isHeld = true
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["~", "~"],
            sameAppWindows: [active, held])
        XCTAssertEqual(m.matchedWids, [])
    }

    func testBorrowedSpaceWindowIsClaimable() {
        // A Space COPIED onto a window by the tab machinery (backfill / representative borrow) is our
        // annotation, not CGS evidence — it must not defeat the claim (rec20's orphaned ex-representative).
        let active = tw(wid: 1, title: "~")
        var exRep = tw(wid: 2, spaceIds: [1], title: "~")
        exRep.spaceIsBorrowed = true
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["~", "~"],
            sameAppWindows: [active, exRep])
        XCTAssertEqual(m.matchedWids, [2])
    }

    func testBorrowedSpaceMemberCountsAsGeometryBackground() {
        let visible = tw(wid: 1, spaceIds: [1], tabbedSiblingWids: [1, 3])
        var borrowed = tw(wid: 2, spaceIds: [1], title: "~")
        borrowed.spaceIsBorrowed = true
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, borrowed]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2])])
    }

    func testHeldBackgroundingTabGroupsByGeometryDespiteBorrowedSpace() {
        // Geometry path of the same fact: a held member counts as background even though it (still) holds a
        // borrowed Space — both claim paths must agree or the ghost tile survives on one of them.
        let visible = tw(wid: 1, spaceIds: [1], tabbedSiblingWids: [1, 3])
        var held = tw(wid: 2, spaceIds: [1], title: "~")
        held.isHeld = true
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, held]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2])])
    }

    func testDynamicTitleMismatchKeepsSibling() {
        // The cause-B flap, now FIXED: the AXTabGroup reports the inactive tab as "B2" (Terminal renamed it)
        // but the tracked window still reads "B1". Title equality fails, yet the sibling is still tabbed into
        // this group, so it's KEPT (not dropped, not shown as a separate window) and "B2" is NOT reported
        // untracked (we already hold that tab). This is the #5830 stability fix.
        let active = tw(wid: 1, title: "A", tabbedSiblingWids: [1, 2])
        let stale = tw(wid: 2, title: "B1", isTabbed: true, tabbedSiblingWids: [1, 2])
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["A", "B2"],
            sameAppWindows: [active, stale])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1, 2], matchedWids: [2], untrackedTitles: [], toUntabWids: []))
    }

    // MARK: - B2. matchSiblings — the group token

    func testTokenClaimsSiblingNoTitleCanName() {
        // #5785's shape: Terminal composes tab titles unlike window titles, so no title names the sibling and
        // the frames disagree (the tab bar resized the active). Both windows named the same AXTabGroup
        // element, which settles it without either.
        let active = tw(wid: 1, title: "1. bash", tabGroupToken: 77)
        let sibling = tw(wid: 2, spaceIds: [], title: "~/git — -zsh — 80×25", tabGroupToken: 77)
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["nothing", "matches"],
            sameAppWindows: [active, sibling])
        XCTAssertEqual(m.siblingWids, [1, 2])
        XCTAssertEqual(m.matchedWids, [2])
        XCTAssertEqual(m.toUntabWids, [])
        // one title is still reported untracked, and that is not the token's doing: when the app composes tab
        // titles unlike window titles the ACTIVE's own title is not among them either, so N titles are shared
        // by N-1 claimable siblings. The token pays for one of them, which is one fewer brute-force scan.
        XCTAssertEqual(m.untrackedTitles, ["matches"])
    }

    func testTokenClaimBringsTheSiblingsWholeGroup() {
        // generator seed 18: only the two most recent tabs had ever been read as active, so only they carry a
        // token. `form` is exact-set, so claiming just the one the token reached would EJECT the third tab
        // from the group it never left, splitting one window into two tiles.
        let active = tw(wid: 3, title: "c", tabGroupToken: 77)
        let tokenSibling = tw(wid: 2, spaceIds: [], title: "b", isTabbed: true,
                              tabbedSiblingWids: [1, 2], tabGroupToken: 77)
        let older = tw(wid: 1, spaceIds: [], title: "a", tabbedSiblingWids: [1, 2])
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["nothing", "matches", "either"],
            sameAppWindows: [active, tokenSibling, older])
        XCTAssertEqual(m.siblingWids.sorted(), [1, 2, 3])
        XCTAssertEqual(m.toUntabWids, [], "no member of the group being joined is un-tabbed by joining it")
    }

    func testTokenDoesNotClaimAnOnScreenWindow() {
        // A token is recorded when a window is read as the selected tab and OUTLIVES that instant, so it can
        // name a window that has since been torn out. Outside a creation the on-screen protection stands:
        // claiming this would hide a real window, which is worse than failing to group a tab.
        let active = tw(wid: 1, title: "a", tabGroupToken: 77)
        let torn = tw(wid: 2, spaceIds: [1], title: "b", isOrderedIn: true, tabGroupToken: 77)
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["a", "b"],
            sameAppWindows: [active, torn])
        XCTAssertEqual(m.matchedWids, [], "an on-screen window is nobody's background tab, token or not")
    }

    func testNewlyDiscoveredTokenClaimsTheOutgoingTabStillOnItsSpace() {
        // Cmd+T: the new tab is announced with the group's element already readable, while the tab it
        // replaced still shows its stale Space. Same sanctioned atomic claim the size-matched second pass
        // makes, on better evidence — here the frames disagree, so only the token can do it.
        let active = tw(wid: 2, size: CGSize(width: 800, height: 560), title: "new", tabGroupToken: 77)
        let outgoing = tw(wid: 1, size: CGSize(width: 800, height: 600), spaceIds: [1], title: "old",
                          isOrderedIn: true, tabGroupToken: 77)
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["new", "old"],
            sameAppWindows: [active, outgoing], activeIsNewlyDiscovered: true)
        XCTAssertEqual(m.matchedWids, [1])
    }

    func testAbsentTokensAreNotAMatch() {
        // the trap in `a == b` when both are nil: two windows nobody has ever read as a selected tab must not
        // become siblings by both being unknown.
        let active = tw(wid: 1, title: "a")
        let stranger = tw(wid: 2, spaceIds: [], title: "b")
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["a", "zzz"],
            sameAppWindows: [active, stranger])
        XCTAssertEqual(m.matchedWids, [])
    }

    func testTokenDoesNotClaimAFullscreenWindow() {
        // entering fullscreen REPLACES the element, so a fullscreen window never really shares a windowed
        // group's token. The fullscreen Space invariant is stated here too rather than assumed.
        let active = tw(wid: 1, title: "a", tabGroupToken: 77)
        let full = tw(wid: 2, spaceIds: [], title: "b", isFullscreen: true, tabGroupToken: 77)
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["a", "b"],
            sameAppWindows: [active, full])
        XCTAssertEqual(m.matchedWids, [])
    }

    // MARK: - C. positionsCompatible

    func testExistingLinkBeatsFarPosition() {
        let a = tw(wid: 1, position: CGPoint(x: 0, y: 0))
        let b = tw(wid: 2, position: CGPoint(x: 999, y: 999), tabbedSiblingWids: [1])
        XCTAssertTrue(TabGroupResolver.positionsCompatible(a, b))
    }

    func testFullscreenFallsBackToTitle() {
        let a = tw(wid: 1, position: CGPoint(x: 0, y: 0), isFullscreen: true)
        let b = tw(wid: 2, position: CGPoint(x: 999, y: 999))
        XCTAssertTrue(TabGroupResolver.positionsCompatible(a, b))
    }

    func testUnknownPositionFallsBack() {
        let a = tw(wid: 1, position: nil)
        let b = tw(wid: 2, position: CGPoint(x: 999, y: 999))
        XCTAssertTrue(TabGroupResolver.positionsCompatible(a, b))
    }

    func testNearbyButNotIdenticalPositionsIncompatible() {
        // This used to assert the opposite, on the assumption that "close enough" meant "same window". macOS
        // CASCADES new windows by 29px, so "close" is precisely where a SECOND window lives — real-world rec11
        // (`testCascadedWindowTabsAreNotClaimedAcrossWindows`) had two same-size Finder windows one cascade
        // step apart swallow each other. A tab IS its parent's frame: same window ⇒ same position, exactly.
        let a = tw(wid: 1, position: CGPoint(x: 100, y: 100))
        let b = tw(wid: 2, position: CGPoint(x: 120, y: 130))
        XCTAssertFalse(TabGroupResolver.positionsCompatible(a, b))
    }

    func testIdenticalPositionsCompatible() {
        let a = tw(wid: 1, position: CGPoint(x: 100, y: 100))
        let b = tw(wid: 2, position: CGPoint(x: 100, y: 100))
        XCTAssertTrue(TabGroupResolver.positionsCompatible(a, b))
    }

    func testStalePositionNeverSplitsAnAlreadyLinkedPair() {
        // The link bypass is what makes the exact test above affordable: once AX has grouped a pair, a stale
        // position (parent moved while the tab was ordered out; Merge All Windows) must not split them.
        let a = tw(wid: 1, position: CGPoint(x: 100, y: 100))
        let b = tw(wid: 2, position: CGPoint(x: 683, y: 101), tabbedSiblingWids: [1, 2])
        XCTAssertTrue(TabGroupResolver.positionsCompatible(a, b))
    }

    func testFarPositionsIncompatible() {
        let a = tw(wid: 1, position: CGPoint(x: 100, y: 100))
        let b = tw(wid: 2, position: CGPoint(x: 200, y: 100))
        XCTAssertFalse(TabGroupResolver.positionsCompatible(a, b))
    }

    // MARK: - D. groupRepresentative

    func testRepresentativeIsTheOnScreenActiveTab() {
        // The active tab is the most recently focused member (each background tab was focused further back).
        let active = tw(wid: 1, spaceIds: [1], tabbedSiblingWids: [1, 2], lastFocusOrder: 0)
        let tab = tw(wid: 2, spaceIds: [1], isTabbed: true, tabbedSiblingWids: [1, 2], lastFocusOrder: 1)
        XCTAssertEqual(TabGroupResolver.groupRepresentative([tab, active]), 1)
    }

    func testRepresentativeKeepsTheJustBackgroundedVisible() {
        // Mid-swap the visible has gone Space-less (its 1326 landed, the new tab isn't discovered yet). It is
        // still the most recently focused member — keep it, so the group holds a tile through the gap.
        let goingBackground = tw(wid: 1, spaceIds: [], tabbedSiblingWids: [1, 2], lastFocusOrder: 0)
        let tab = tw(wid: 2, spaceIds: [1], isTabbed: true, tabbedSiblingWids: [1, 2], lastFocusOrder: 1)
        XCTAssertEqual(TabGroupResolver.groupRepresentative([goingBackground, tab]), 1)
    }

    // MARK: - Split View (two real windows sharing ONE fullscreen Space)

    /// The measured case, live on macOS 26: two TextEdit windows tiled via Window ▸ Full-Screen Tile, both
    /// `fullscreen=true`, both genuinely on Space 2267, at different origins. These particular frames differ
    /// in SIZE too (one had a toolbar showing), so they never even reach the same cluster — recorded because
    /// it is what the OS actually produced, and it documents that the halves are not required to match.
    func testSplitViewCapturedGeometryFormsNoGroup() {
        let left = tw(wid: 12542, size: CGSize(width: 1022, height: 1116), position: CGPoint(x: 0, y: 36),
                      spaceIds: [2267], title: "Untitled", isFullscreen: true)
        let right = tw(wid: 36133, size: CGSize(width: 1014, height: 1152), position: CGPoint(x: 1034, y: 0),
                       spaceIds: [2267], title: "Untitled 4", isFullscreen: true)
        XCTAssertEqual(TabGroupResolver.geometryGroups([left, right]), [])
    }

    /// The HAZARD, and what the gate is for: the same split, with the two halves at the same SIZE (two Finder
    /// windows, or any pair whose toolbars agree). Now they share a cluster, they share one fullscreen Space,
    /// and the fullscreen fold absorbs a member settled on the fold Space — a rule that exists to catch the
    /// visible's outgoing tab whose 1326 has not landed. Without the gate one real window is folded in as a
    /// "tab" of the other and disappears from the switcher.
    ///
    /// The ORIGIN is what separates them: a lagging outgoing tab wears the visible's own frame, while split
    /// halves sit side by side and cannot share an origin.
    func testSplitViewHalvesOfEqualSizeAreNotFoldedTogether() {
        let half = CGSize(width: 1024, height: 1152)
        let left = tw(wid: 1, size: half, position: .zero, spaceIds: [2267], isFullscreen: true)
        let right = tw(wid: 2, size: half, position: CGPoint(x: 1024, y: 0), spaceIds: [2267],
                       isFullscreen: true)
        XCTAssertEqual(TabGroupResolver.geometryGroups([left, right]), [])
    }

    /// ...while the case the fold exists for still works: a member settled on the fold Space AT THE VISIBLE'S
    /// OWN ORIGIN is the outgoing tab whose 1326 is late, and is still folded in.
    func testFullscreenStillFoldsALaggingTabAtTheSameOrigin() {
        let fs = CGSize(width: 2048, height: 1152)
        let visible = tw(wid: 1, size: fs, position: .zero, spaceIds: [2267], isFullscreen: true)
        let lagging = tw(wid: 2, size: fs, position: .zero, spaceIds: [2267], isFullscreen: true)
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, lagging]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2])])
    }

    // MARK: - what the handover pair decides and geometry cannot
    //
    // Both were written RED, before the change, so "the rework worked" had a definition that predated it.
    // Each states a case where two candidate windows are identical on every fact the kernel has EXCEPT who
    // handed over to whom — so neither is closable by tightening geometry.

    /// **The stacked-windows theft.** Terminal opens each new window at the SAME position and size, so two
    /// windows of one app can be identical in every geometric fact. Tab X backgrounds inside window A; before
    /// A's AXTabGroup read lands to link it, the user clicks window B. Now B is the cluster's most recently
    /// focused member, so it is elected visible, and X — Space-less, same app, same frame — is folded in as
    /// B's tab. A real tab of A is hidden under B's tile, and the tab count of both windows is wrong.
    ///
    /// `lastLeftSpaceId` cannot answer this, and that is the point. It names the SPACE the tab left, which
    /// separates two FULLSCREEN windows (each owns a Space) and says nothing at all here: A and B share
    /// Space 1, so "X left Space 1" is true of both. The handover names the WID that took X's place — A's
    /// incoming tab — which is the fact that distinguishes them, and the only place it exists is the pairing
    /// of X's 1326 with that wid's 1325.
    func testBackgroundedTabIsNotStolenByAStackedWindowOfTheSameApp() {
        let bActive = tw(wid: 2, spaceIds: [1], tabbedSiblingWids: [2, 4], lastFocusOrder: 0, tabCount: 2)
        let aActive = tw(wid: 1, spaceIds: [1], tabbedSiblingWids: [1, 3], lastFocusOrder: 1, tabCount: 2)
        var backgrounded = tw(wid: 3, spaceIds: [], lastFocusOrder: 2)   // A's outgoing tab, not yet re-linked
        backgrounded.lastLeftSpaceId = 1                                 // ...which is ALSO B's Space
        backgrounded.replacedByWid = 1                                   // ...but A's tab is what took its place
        let groups = TabGroupResolver.geometryGroups([bActive, aActive, backgrounded])
        XCTAssertFalse(groups.contains { $0.visibleWid == 2 && $0.backgroundWids.contains(3) },
                       "window B claimed a tab that backgrounded inside window A")
    }

    /// **The drag-out that lands on the parent's frame.** `dragOutVerdict` compares FRAMES, and its own
    /// comment concedes the two cases are indistinguishable that way — a dragged-out tab starts at its
    /// parent's frame. So a tab torn out and dropped back over its parent reads as a tab switch, and the
    /// verdict is final ("same frame ⇒ stop checking"): the new window stays in the group and is hidden as a
    /// tab of it.
    ///
    /// The pair separates them without looking at frames at all. A tab SWITCH is a join matched by the
    /// outgoing tab's leave on that Space. A drag-OUT is a join with no leave — the parent's active tab
    /// never went anywhere, which is exactly the state below (`prevRep` still holds Space 1, un-tabbed).
    /// Note the fix is not only this kernel: "no leave arrived" is only true once the pairing window has
    /// elapsed, so the caller's re-check (`armDragOutCheck`, which already carries an attempt count) is what
    /// has to feed that fact in. This pins the decision the kernel would then make.
    func testDragOutIsDecidedByTheMissingLeaveNotTheFrame() {
        let joiner = tw(wid: 1, spaceIds: [1])                       // torn out, dropped at the parent's frame
        let prevRep = tw(wid: 2, spaceIds: [1])                      // never left: no 1326 ever paired with it
        XCTAssertEqual(TabGroupResolver.dragOutVerdict(joiner: joiner, previousRepresentative: prevRep,
                                                       pairingWindowElapsed: true), true)
    }

    /// The other leg, and the one that makes the first safe: a join that DID replace the previous
    /// representative is a tab switch, said from the pair alone — no frame, no waiting, no re-check.
    func testAPairedJoinIsATabSwitchWithoutLookingAtFrames() {
        var joiner = tw(wid: 1, size: nil, position: nil, spaceIds: [1])   // frame not known yet
        joiner.replacedWid = 2
        let prevRep = tw(wid: 2, spaceIds: [])
        XCTAssertEqual(TabGroupResolver.dragOutVerdict(joiner: joiner, previousRepresentative: prevRep), false)
    }

    /// ...and a join that replaced SOMEONE ELSE still means this tab left the group it is being judged
    /// against. The edge is about identity, so it answers both directions of the question.
    func testAJoinThatReplacedAnotherWindowsTabIsADragOutFromThisGroup() {
        var joiner = tw(wid: 1, spaceIds: [1])
        joiner.replacedWid = 9
        let prevRep = tw(wid: 2, spaceIds: [])
        XCTAssertEqual(TabGroupResolver.dragOutVerdict(joiner: joiner, previousRepresentative: prevRep), true)
    }

    // MARK: - dragOutVerdict

    func testJoinerAtThePreviousRepresentativesFrameIsATabSwitch() {
        let joiner = tw(wid: 1, spaceIds: [1])
        let prevRep = tw(wid: 2, spaceIds: [], isTabbed: true, tabbedSiblingWids: [1, 2])
        XCTAssertEqual(TabGroupResolver.dragOutVerdict(joiner: joiner, previousRepresentative: prevRep), false)
    }

    func testJoinerSettledAtAnotherFrameIsADragOut() {
        let joiner = tw(wid: 1, position: CGPoint(x: 500, y: 500), spaceIds: [1])
        let prevRep = tw(wid: 2, spaceIds: [], isTabbed: true, tabbedSiblingWids: [1, 2])
        XCTAssertEqual(TabGroupResolver.dragOutVerdict(joiner: joiner, previousRepresentative: prevRep), true)
    }

    func testUnsettledJoinerFrameIsUndecided() {
        // A new window is 0×0 for a beat — no verdict until it can be judged; the caller re-checks.
        let joiner = tw(wid: 1, size: .zero, spaceIds: [1])
        let prevRep = tw(wid: 2, spaceIds: [], isTabbed: true, tabbedSiblingWids: [1, 2])
        XCTAssertNil(TabGroupResolver.dragOutVerdict(joiner: joiner, previousRepresentative: prevRep))
    }

    func testFullscreenJoinIsNeverADragOutHere() {
        // Frames are unreliable in fullscreen; the fullscreen Space rule (`membersThatLeftGroup`) owns those.
        let joiner = tw(wid: 1, position: CGPoint(x: 500, y: 500), spaceIds: [1], isFullscreen: true)
        let prevRep = tw(wid: 2, spaceIds: [], isTabbed: true, tabbedSiblingWids: [1, 2])
        XCTAssertEqual(TabGroupResolver.dragOutVerdict(joiner: joiner, previousRepresentative: prevRep), false)
    }

    func testRepresentativePrefersTheMostRecentlyFocusedOnScreenMember() {
        // Mid-switch interleaving: TWO members are on-screen un-tabbed (the outgoing tab's 1326 hasn't
        // landed). Focus decides — the most recently focused member is the active tab by definition,
        // whichever order the AX reads landed in (rec18).
        let older = tw(wid: 1, spaceIds: [1], tabbedSiblingWids: [1, 2], lastFocusOrder: 1)
        let fresher = tw(wid: 2, spaceIds: [1], tabbedSiblingWids: [1, 2], lastFocusOrder: 0)
        XCTAssertEqual(TabGroupResolver.groupRepresentative([older, fresher]), 2)
    }

    func testNoRepresentativeForAnIncoherentStaleGroup() {
        // STALE = the members disagree on their link: geometry re-homed wid 2 into a new group while wid 1
        // still lists it. Forcing one of those visible spuriously un-hid a background tab as a 2nd tile.
        let a = tw(wid: 1, spaceIds: [1], isTabbed: true, tabbedSiblingWids: [1, 2])
        let b = tw(wid: 2, spaceIds: [1], isTabbed: true, tabbedSiblingWids: [2, 9])  // re-homed elsewhere
        XCTAssertNil(TabGroupResolver.groupRepresentative([a, b]))
    }

    func testCoherentGroupThatLostItsVisibleRecoversViaTheFocusedMember() {
        // Captured (`finderFocusedWindowWronglyTabbed`): every member tabbed, but they AGREE on their link —
        // so this is not stale, it's a group whose visible got wrongly tabbed. It must recover, and the
        // FOCUSED member is its active tab by definition. Treating "all tabbed" as stale stranded it hidden.
        let focused = tw(wid: 74626, spaceIds: [3628], isTabbed: true, tabbedSiblingWids: [74626, 74820], lastFocusOrder: 0)
        let other = tw(wid: 74820, spaceIds: [3628], isTabbed: true, tabbedSiblingWids: [74626, 74820], lastFocusOrder: 3)
        XCTAssertEqual(TabGroupResolver.groupRepresentative([other, focused]), 74626,
                       "the window the user just focused is the group's active tab")
    }

    // MARK: - E. hold-visible through the discovery gap

    func testHoldsBackgroundingTabWhenATabWasJustCreated() {
        // The creation race: a visible tab going Space-less right after a create is being replaced by an
        // incoming tab that isn't discovered yet → hold it so the group never shows zero tiles.
        XCTAssertTrue(TabGroupResolver.shouldHoldVisibleThroughDiscovery(
            isTabbed: false, becomesSpaceless: true, hadRecentWindowCreate: true))
    }

    func testDoesNotHoldOnATrackedTabSwitchOrPlainBackground() {
        // NO replacement signal (no create, no untracked Space-join) ⇒ nothing is coming to replace it (a
        // switch between TRACKED tabs — the rep swap covers those — or it simply backgrounded) ⇒ it must
        // hide normally.
        XCTAssertFalse(TabGroupResolver.shouldHoldVisibleThroughDiscovery(
            isTabbed: false, becomesSpaceless: true, hadRecentWindowCreate: false))
    }

    func testHoldsWhenAMintedTabSwitchAnnouncedItselfViaAnUntrackedSpaceJoin() {
        // rec24: Finder mints a brand-new wid per tab switch and emits NO create for it — only a 1325 onto
        // the visible Space, one beat before the outgoing tab's 1326. That join is as much a replacement
        // signal as an 811; without this leg the outgoing rep went phantom and the tile vanished ~800ms
        // until the minted wid's discovery re-claimed the group.
        XCTAssertTrue(TabGroupResolver.shouldHoldVisibleThroughDiscovery(
            isTabbed: false, becomesSpaceless: true, hadRecentWindowCreate: false,
            hadRecentUntrackedSpaceJoin: true))
    }

    func testDoesNotHoldAWindowThatKeepsASpaceOrIsAlreadyATab() {
        // Still on another Space ⇒ not backgrounding. Already a background tab ⇒ hidden by the tab filter.
        XCTAssertFalse(TabGroupResolver.shouldHoldVisibleThroughDiscovery(
            isTabbed: false, becomesSpaceless: false, hadRecentWindowCreate: true))
        XCTAssertFalse(TabGroupResolver.shouldHoldVisibleThroughDiscovery(
            isTabbed: true, becomesSpaceless: true, hadRecentWindowCreate: true))
    }

    func testHoldReleasesOnceTheIncomingTabClaimedIt() {
        XCTAssertTrue(TabGroupResolver.shouldReleaseHold(
            isTabbed: true, hasPresentableReplacement: false, attemptsExhausted: false))
    }

    func testHoldPersistsWhileNothingCanReplaceTheTile() {
        // The point of re-checking instead of a fixed delay: however long the OS takes, keep the tile.
        XCTAssertFalse(TabGroupResolver.shouldReleaseHold(
            isTabbed: false, hasPresentableReplacement: false, attemptsExhausted: false))
    }

    func testHoldReleasesOnceAReplacementCanBeShown() {
        // The hold's whole job is "never zero tiles". Something else can be drawn ⇒ the job is done.
        XCTAssertTrue(TabGroupResolver.shouldReleaseHold(
            isTabbed: false, hasPresentableReplacement: true, attemptsExhausted: false))
    }

    func testHoldReleasesAtTheSafetyCap() {
        // A wedged discovery must not hold a window visible forever.
        XCTAssertTrue(TabGroupResolver.shouldReleaseHold(
            isTabbed: false, hasPresentableReplacement: false, attemptsExhausted: true))
    }

    func testReplacementMustBeTheSameWindowsNextTab() {
        // rec13's lesson, as a rule: the held tab (133,89) must NOT be released because a DIFFERENT window of
        // the same app has a tile. Same app, same size, on-screen, drawable — but its own frame, so it can't
        // show this window's content, and releasing would leave this group with nothing.
        let held = tw(wid: 1, size: CGSize(width: 920, height: 436), position: CGPoint(x: 133, y: 89),
                      spaceIds: [])
        let otherWindow = tw(wid: 2, size: CGSize(width: 920, height: 436), position: CGPoint(x: 162, y: 118),
                             spaceIds: [3628])
        XCTAssertFalse(TabGroupResolver.hasPresentableReplacement(for: held, among: [held, otherWindow]))
    }

    func testReplacementAtTheHeldTabsFrameReleasesIt() {
        let held = tw(wid: 1, size: CGSize(width: 920, height: 436), position: CGPoint(x: 133, y: 89),
                      spaceIds: [])
        let incoming = tw(wid: 2, size: CGSize(width: 920, height: 436), position: CGPoint(x: 133, y: 89),
                          spaceIds: [3628])
        XCTAssertTrue(TabGroupResolver.hasPresentableReplacement(for: held, among: [held, incoming]))
    }

    func testAnotherFullscreenWindowIsNotAReplacement() {
        // rec27 (live): bursting ⌘T inside a FULLSCREEN Finder window while a second fullscreen Finder window
        // sat on another Space made the first window's tile go out and come back. Every fullscreen window is
        // screen-sized at 0,0, so `sameFrame` — which normally proves "same window", since separate windows
        // of one app are cascaded 29px apart — matched the unrelated window on Space 4594 and released the
        // hold early, leaving the group with nothing to show. A window SETTLED on a Space the held tab is not
        // on is a different window, whatever its frame says.
        let held = tw(wid: 1, size: CGSize(width: 1440, height: 900), position: .zero, spaceIds: [5335])
        let otherFullscreen = tw(wid: 2, size: CGSize(width: 1440, height: 900), position: .zero,
                                 spaceIds: [4594])
        XCTAssertFalse(TabGroupResolver.hasPresentableReplacement(for: held, among: [held, otherFullscreen]))
        // ...while this window's OWN next tab, on its Space, still releases it
        let ownNextTab = tw(wid: 3, size: CGSize(width: 1440, height: 900), position: .zero, spaceIds: [5335])
        XCTAssertTrue(TabGroupResolver.hasPresentableReplacement(for: held, among: [held, ownNextTab]))
    }

    /// rec27, the transcribed live flicker: the held tab is Space-LESS — that is what being held MEANS, its
    /// 1326 just landed — so "is the candidate settled somewhere else?" cannot be answered against the held
    /// window's current Space. It has to be answered against the Space it just LEFT (`lastLeftSpaceId`).
    /// Getting this wrong is not academic: the first version of this guard compared against
    /// `held.spaceIds`, which is empty in exactly the case that matters, so it never fired and the tile went
    /// on vanishing.
    func testReplacementIsJudgedAgainstTheSpaceTheHeldTabJustLeft() {
        var held = tw(wid: 91409, size: CGSize(width: 1440, height: 900), position: .zero, spaceIds: [])
        held.lastLeftSpaceId = 5335
        let otherFullscreen = tw(wid: 75934, size: CGSize(width: 1440, height: 900), position: .zero,
                                 spaceIds: [4594])
        XCTAssertFalse(TabGroupResolver.hasPresentableReplacement(for: held, among: [held, otherFullscreen]))
        // its OWN next tab — on the Space it just left — still releases the hold
        let ownNextTab = tw(wid: 91491, size: CGSize(width: 1440, height: 900), position: .zero,
                            spaceIds: [5335])
        XCTAssertTrue(TabGroupResolver.hasPresentableReplacement(for: held, among: [held, ownNextTab]))
    }

    func testUnsizedIncomingTabIsNotYetAReplacement() {
        // The OS publishes a new tab at 0×0 and sizes it ~640ms later; until then it can't be drawn, so the
        // held tab keeps the tile. This is what makes the hold self-timing.
        let held = tw(wid: 1, size: CGSize(width: 920, height: 436), position: CGPoint(x: 133, y: 89),
                      spaceIds: [])
        let unsized = tw(wid: 2, size: .zero, position: .zero, spaceIds: [3628])
        XCTAssertFalse(TabGroupResolver.hasPresentableReplacement(for: held, among: [held, unsized]))
    }

    // MARK: - F. dissolution (owned by `TabGroupsTable`, not the resolver)

    /// Dissolution is not a resolver decision: membership IS the table, so a function taking a sibling array
    /// and a set of still-present wids would take two redundant inputs. These pin `TabGroupsTable.remove`,
    /// which is what the app actually calls.
    private func table(_ wids: [CGWindowID]) -> TabGroupsTable {
        var t = TabGroupsTable()
        _ = t.form(wids, representative: wids[0], reason: "test", repPicker: { r, _ in r.first })
        return t
    }

    // MARK: - F2. the token store (`TabGroupsTable.recordToken`)

    func testNilTokenReadNeverClearsTheStoredOne() {
        // only the SELECTED tab exposes a tab bar, and Terminal's and TextEdit's fullscreen bars are in a
        // window no downward walk reaches — so "no token now" is routine for a window that is still a tab.
        var t = table([1, 2])
        t.recordToken(77, for: 1)
        t.recordToken(nil, for: 1)
        XCTAssertEqual(t.tokenByWid[1], 77)
    }

    func testADifferentTokenOverwrites() {
        // a tab dragged into another window's bar keeps its element and its wid and reports the DESTINATION's
        // group from then on; overwriting is what stops the old group still claiming it.
        var t = table([1, 2])
        t.recordToken(77, for: 1)
        t.recordToken(88, for: 1)
        XCTAssertEqual(t.tokenByWid[1], 88)
    }

    func testLeavingAGroupClearsTheToken() {
        // a token must never name a window that is no longer in the group, or the next read would drag it
        // back in.
        var t = table([1, 2, 3])
        t.recordToken(77, for: 2)
        _ = t.remove(2, reason: "test", repPicker: { r, _ in r.first })
        XCTAssertNil(t.tokenByWid[2])
    }

    func testDissolvingAGroupClearsEveryToken() {
        var t = table([1, 2])
        t.recordToken(77, for: 1)
        t.recordToken(77, for: 2)
        _ = t.remove(2, reason: "test", repPicker: { r, _ in r.first })   // 2 leaves, so the group dissolves
        XCTAssertNil(t.tokenByWid[1])
        XCTAssertNil(t.tokenByWid[2])
    }

    func testDissolveWhenOneSurvivor() {
        var t = table([1, 2])
        let m = t.remove(1, reason: "test", repPicker: { r, _ in r.first })
        XCTAssertTrue(m.changed)
        XCTAssertEqual(m.ungroupedWids.sorted(), [1, 2])   // a lone survivor is ungrouped too
        XCTAssertTrue(t.membersByGroup.isEmpty)
        XCTAssertNil(t.groupId(of: 2))
    }

    func testShrinkWhenManySurvive() {
        var t = table([1, 2, 3])
        let m = t.remove(1, reason: "test", repPicker: { r, _ in r.first })
        XCTAssertTrue(m.changed)
        XCTAssertEqual(m.ungroupedWids, [1])
        XCTAssertEqual(t.siblingWids(of: 2), [2, 3])
        // the representative left with the removed member, so the group re-picked one
        XCTAssertEqual(t.representativeByGroup.values.first, 2)
    }

    func testAbsentSurvivorsNotCounted() {
        // 3 already gone: removing 1 leaves only 2, so the group dissolves rather than shrinking to a group
        // of one (which every `isTabbed` read would then get wrong).
        var t = table([1, 2, 3])
        _ = t.remove(3, reason: "test", repPicker: { r, _ in r.first })
        let m = t.remove(1, reason: "test", repPicker: { r, _ in r.first })
        XCTAssertEqual(m.ungroupedWids.sorted(), [1, 2])
        XCTAssertTrue(t.membersByGroup.isEmpty)
    }
    // Real captured Terminal/Finder scenarios live in RealWorldScenariosTests (the shared corpus), not here.
}
