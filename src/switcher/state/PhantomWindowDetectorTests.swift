import XCTest

/// Pins the phantom-window decision (`PhantomWindowDetector`) against canonical `WindowState` /
/// `ApplicationState` snapshots, so the per-app real-user scenarios and the #5714 "never clears a
/// phantom" invariant are regression-proof. Group A covers the synchronous assert-only path
/// (`Window.recomputeIsPhantom`); group B covers the authoritative CGS path
/// (`Applications.refreshIsPhantom`). See PhantomWindowDetectorSpecs.md.
final class PhantomWindowDetectorTests: XCTestCase {

    private func ws(isPhantom: Bool = false, isMinimized: Bool = false, isTabbed: Bool = false,
                    spaceIds: [UInt64] = []) -> WindowState {
        WindowState(id: "w", isPhantom: isPhantom, isWindowlessApp: false,
                    isFullscreen: false, isMinimized: isMinimized, isTabbed: isTabbed,
                    isOnAllSpaces: false, spaceIds: spaceIds, spaceIndexes: [],
                    lastFocusOrder: 0, creationOrder: 0, title: "Title")
    }

    private func appState(appIsHidden: Bool = false) -> ApplicationState {
        ApplicationState(pid: 0, bundleIdentifier: nil, localizedName: nil, isHidden: appIsHidden)
    }

    // MARK: - A. syncVerdict (synchronous, assert-only)

    func testEmptySpacesIsPhantom() {
        XCTAssertTrue(PhantomWindowDetector.syncVerdict(ws(spaceIds: []), appState()))
    }

    func testNonEmptySpacesAloneNotRaised() {
        XCTAssertFalse(PhantomWindowDetector.syncVerdict(ws(spaceIds: [1]), appState()))
    }

    func testNeverClearsAPhantom() {
        // #5714 invariant: a weak-signal phantom set by cgsVerdict keeps a Space, but syncVerdict must
        // not clear it on the next show.
        XCTAssertTrue(PhantomWindowDetector.syncVerdict(ws(isPhantom: true, spaceIds: [4]), appState()))
    }

    func testTabbedWithEmptySpacesNotRaised() {
        XCTAssertFalse(PhantomWindowDetector.syncVerdict(ws(isTabbed: true, spaceIds: []), appState()))
    }

    func testTabbedClearsAStalePhantom() {
        // Regression: an inactive tab is transiently flagged phantom (empty spaceIds, before AX tab
        // detection runs). Once AX confirms it's tabbed, the synchronous path must CLEAR that stale
        // verdict — the monotonic-only version left it stuck, so "separate window per tab" dropped every
        // inactive tab and showed only the active one (one window per app).
        XCTAssertFalse(PhantomWindowDetector.syncVerdict(ws(isPhantom: true, isTabbed: true, spaceIds: []), appState()))
    }

    func testMinimizedWithEmptySpacesNotRaised() {
        XCTAssertFalse(PhantomWindowDetector.syncVerdict(ws(isMinimized: true, spaceIds: []), appState()))
    }

    func testHiddenAppWithEmptySpacesNotRaised() {
        XCTAssertFalse(PhantomWindowDetector.syncVerdict(ws(spaceIds: []), appState(appIsHidden: true)))
    }

    // MARK: - B. cgsVerdict (authoritative, per-app table)

    func testMissingFromAllListsIsPhantom() {
        // Joplin / Sprig: CGS dropped the WID from every Space.
        XCTAssertTrue(PhantomWindowDetector.cgsVerdict(ws(spaceIds: []), appState(),
            inVisibleList: false, inAllList: false, visibleSpaceIds: []))
    }

    func testInVisibleListIsNotPhantom() {
        XCTAssertFalse(PhantomWindowDetector.cgsVerdict(ws(spaceIds: [1]), appState(),
            inVisibleList: true, inAllList: true, visibleSpaceIds: [1]))
    }

    func testWeakSignalOnVisibleSpaceIsPhantom() {
        // Codex / Slack / Outlook: in-all but not-visible, on the current visible Space, alive otherwise.
        XCTAssertTrue(PhantomWindowDetector.cgsVerdict(ws(spaceIds: [1]), appState(),
            inVisibleList: false, inAllList: true, visibleSpaceIds: [1]))
    }

    func testOtherSpaceWindowIsNotPhantom() {
        XCTAssertFalse(PhantomWindowDetector.cgsVerdict(ws(spaceIds: [2]), appState(),
            inVisibleList: false, inAllList: true, visibleSpaceIds: [1]))
    }

    func testMinimizedIsNotPhantom() {
        XCTAssertFalse(PhantomWindowDetector.cgsVerdict(ws(isMinimized: true, spaceIds: [1]), appState(),
            inVisibleList: false, inAllList: true, visibleSpaceIds: [1]))
    }

    func testHiddenAppIsNotPhantom() {
        XCTAssertFalse(PhantomWindowDetector.cgsVerdict(ws(spaceIds: [1]), appState(appIsHidden: true),
            inVisibleList: false, inAllList: true, visibleSpaceIds: [1]))
    }

    func testTabbedIsNotPhantom() {
        XCTAssertFalse(PhantomWindowDetector.cgsVerdict(ws(isTabbed: true, spaceIds: [1]), appState(),
            inVisibleList: false, inAllList: true, visibleSpaceIds: [1]))
    }

    func testTabbedMissingFromAllListsIsNotPhantom() {
        // The real inactive background tab: CGS lists no tab in any Space, so it's absent from BOTH lists
        // even though its spaceIds are backfilled from the active sibling. The legitimate-window exemption
        // must beat the strong signal, or the tab disappears (fullscreen-tab / "separate window per tab").
        XCTAssertFalse(PhantomWindowDetector.cgsVerdict(ws(isTabbed: true, spaceIds: [4]), appState(),
            inVisibleList: false, inAllList: false, visibleSpaceIds: [4]))
    }

    func testMinimizedMissingFromAllListsIsNotPhantom() {
        // Same exemption for a minimized window CGS dropped from its per-Space lists.
        XCTAssertFalse(PhantomWindowDetector.cgsVerdict(ws(isMinimized: true, spaceIds: []), appState(),
            inVisibleList: false, inAllList: false, visibleSpaceIds: []))
    }
}
