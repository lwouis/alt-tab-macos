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

    func testVisiblePlusSpacelessIsAGroup() {
        let visible = tw(wid: 1, spaceIds: [1])
        let background = tw(wid: 2, spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, background]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2])])
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
        let visible = tw(wid: 1, spaceIds: [1])
        let bg1 = tw(wid: 2, spaceIds: [])
        let bg2 = tw(wid: 3, spaceIds: [])
        XCTAssertEqual(TabGroupResolver.geometryGroups([visible, bg1, bg2]),
            [GeometryGroup(visibleWid: 1, backgroundWids: [2, 3])])
    }

    // MARK: - B. matchSiblings

    func testMatchesInactiveSiblingByTitle() {
        let active = tw(wid: 1, title: "git")
        let sibling = tw(wid: 2, title: "lwouis")
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["git", "lwouis"],
            sameAppWindows: [active, sibling])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1, 2], matchedWids: [2], untrackedTitles: [], toUntabWids: []))
    }

    func testDuplicateTitleRemovedOnce() {
        let active = tw(wid: 1, title: "git")
        let other = tw(wid: 2, title: "git")
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["git", "git"],
            sameAppWindows: [active, other])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1, 2], matchedWids: [2], untrackedTitles: [], toUntabWids: []))
    }

    func testUntrackedTitleReported() {
        let active = tw(wid: 1, title: "git")
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["git", "lwouis"],
            sameAppWindows: [active])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: ["lwouis"], toUntabWids: []))
    }

    func testFormerSiblingFallsOutIsUntabbed() {
        let active = tw(wid: 1, title: "git")
        let former = tw(wid: 2, title: "old", isTabbed: true, tabbedSiblingWids: [1, 2])
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["git"],
            sameAppWindows: [active, former])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: [], toUntabWids: [2]))
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
        let far = tw(wid: 2, position: CGPoint(x: 900, y: 900), title: "lwouis")
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["git", "lwouis"],
            sameAppWindows: [active, far])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: ["lwouis"], toUntabWids: []))
    }

    func testDynamicTitleMismatchDropsSibling() {
        // cause-B flap: the AXTabGroup now reports the inactive tab as "B2" (Terminal renamed it) but the
        // tracked window still reads "B1". Title equality fails, so the sibling is dropped (→ toUntab,
        // shown as a separate window) and "B2" is reported untracked (→ re-discovery). Pins today's
        // behavior; the stability fix should flip this.
        let active = tw(wid: 1, title: "A", tabbedSiblingWids: [1, 2])
        let stale = tw(wid: 2, title: "B1", isTabbed: true, tabbedSiblingWids: [1, 2])
        let m = TabGroupResolver.matchSiblings(active: active, axTitles: ["A", "B2"],
            sameAppWindows: [active, stale])
        XCTAssertEqual(m, SiblingMatch(siblingWids: [1], matchedWids: [], untrackedTitles: ["B2"], toUntabWids: [2]))
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
}
