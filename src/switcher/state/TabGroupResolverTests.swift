import XCTest

/// Pins the OS-tab grouping decisions (`TabGroupResolver`) against canonical `TabWindow` snapshots, so the
/// geometry inference, the brittle AX-title sibling matching (the documented cause-B flap), the position
/// compatibility, and the group dissolution are regression-proof without the `Window` graph. See
/// TabGroupResolverSpecs.md.
final class TabGroupResolverTests: XCTestCase {

    private func tw(pid: pid_t = 1, wid: CGWindowID, size: CGSize? = CGSize(width: 800, height: 600),
                    position: CGPoint? = CGPoint(x: 100, y: 100), spaceIds: [UInt64] = [1],
                    title: String = "", isTabbed: Bool = false, isFullscreen: Bool = false,
                    isMinimized: Bool = false, tabbedSiblingWids: [CGWindowID]? = nil) -> TabWindow {
        TabWindow(pid: pid, wid: wid, size: size, position: position, spaceIds: spaceIds, title: title,
            isTabbed: isTabbed, isFullscreen: isFullscreen, isMinimized: isMinimized,
            tabbedSiblingWids: tabbedSiblingWids)
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

    func testClosePositionsCompatible() {
        let a = tw(wid: 1, position: CGPoint(x: 100, y: 100))
        let b = tw(wid: 2, position: CGPoint(x: 120, y: 130))
        XCTAssertTrue(TabGroupResolver.positionsCompatible(a, b))
    }

    func testFarPositionsIncompatible() {
        let a = tw(wid: 1, position: CGPoint(x: 100, y: 100))
        let b = tw(wid: 2, position: CGPoint(x: 200, y: 100))
        XCTAssertFalse(TabGroupResolver.positionsCompatible(a, b))
    }

    // MARK: - D. dissolution

    func testDissolveWhenOneSurvivor() {
        let d = TabGroupResolver.dissolution(siblingWids: [1, 2], leaving: 1, presentWids: [2])
        XCTAssertEqual(d, GroupDissolution(remainingSiblingWids: [2], applyToWids: [2], dissolve: true))
    }

    func testShrinkWhenManySurvive() {
        let d = TabGroupResolver.dissolution(siblingWids: [1, 2, 3], leaving: 1, presentWids: [2, 3])
        XCTAssertEqual(d, GroupDissolution(remainingSiblingWids: [2, 3], applyToWids: [2, 3], dissolve: false))
    }

    func testAbsentSurvivorsNotCounted() {
        // 3 already gone: only 2 survives → one survivor → dissolve.
        let d = TabGroupResolver.dissolution(siblingWids: [1, 2, 3], leaving: 1, presentWids: [2])
        XCTAssertEqual(d, GroupDissolution(remainingSiblingWids: [2, 3], applyToWids: [2], dissolve: true))
    }
    // Real captured Terminal/Finder scenarios live in RealWorldScenariosTests (the shared corpus), not here.
}
