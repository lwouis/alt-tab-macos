import XCTest

/// Documents the per-shortcut "which windows show in the switcher" matrix by pinning
/// `WindowFilterResolver.shouldShow` against canonical `WindowState` / `ApplicationState` snapshots.
/// Each test starts from a plain visible real window + an all-permissive config and flips exactly one
/// knob, so every filter dimension is isolated.
///
/// Groups: A always-excluded · B app scope · C hidden apps · D windowless · E fullscreen ·
/// F minimized · G spaces · H screens · I tabs · J combinations · K under the cursor.
final class WindowFilterResolverTests: XCTestCase {

    private func ws(isPhantom: Bool = false, isWindowlessApp: Bool = false, isFullscreen: Bool = false,
                    isMinimized: Bool = false, isTabbed: Bool = false, isHeldVisibleForTab: Bool = false,
                    isOnAllSpaces: Bool = false, spaceIds: [UInt64] = [], title: String = "Title") -> WindowState {
        WindowState(id: "w", isPhantom: isPhantom, isWindowlessApp: isWindowlessApp,
                    isFullscreen: isFullscreen, isMinimized: isMinimized, isTabbed: isTabbed,
                    isHeldVisibleForTab: isHeldVisibleForTab,
                    isOnAllSpaces: isOnAllSpaces, spaceIds: spaceIds, spaceIndexes: [],
                    lastFocusOrder: 0, creationOrder: 0, title: title)
    }

    private func appState(pid: pid_t = 0, bundleIdentifier: String? = nil, appIsHidden: Bool = false) -> ApplicationState {
        ApplicationState(pid: pid, bundleIdentifier: bundleIdentifier, localizedName: nil, isHidden: appIsHidden)
    }

    // MARK: - A. Defaults & always-excluded

    func testDefaultsShowARealWindow() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(), appState(), isOnPreferredScreen: true))
    }

    func testPhantomIsHidden() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(isPhantom: true), appState(), isOnPreferredScreen: true))
    }

    func testHiddenByExceptionIsHidden() {
        let except = ExceptionEntry(bundleIdentifier: "com.x", hide: .always, ignore: .none)
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(), appState(bundleIdentifier: "com.x.app"),
                                                      exceptions: [except], isOnPreferredScreen: true))
    }

    // MARK: - B. App scope (appsToShow)

    func testOnlyFrontmostAppHidesNonFrontmost() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(), appState(pid: 100),
                                                       onlyFrontmostApp: true, frontmostPid: 200,
                                                       isOnPreferredScreen: true))
    }

    func testOnlyFrontmostAppShowsFrontmost() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(), appState(pid: 100),
                                                      onlyFrontmostApp: true, frontmostPid: 100,
                                                      isOnPreferredScreen: true))
    }

    func testExcludeFrontmostAppHidesFrontmost() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(), appState(pid: 100),
                                                       excludeFrontmostApp: true, frontmostPid: 100,
                                                       isOnPreferredScreen: true))
    }

    func testExcludeFrontmostAppShowsNonFrontmost() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(), appState(pid: 100),
                                                      excludeFrontmostApp: true, frontmostPid: 200,
                                                      isOnPreferredScreen: true))
    }

    // MARK: - C. Hidden apps (⌘H)

    func testHideHiddenHidesHiddenApp() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(), appState(appIsHidden: true),
                                                       hideHidden: true, isOnPreferredScreen: true))
    }

    func testHiddenAppShownWhenNotHiding() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(), appState(appIsHidden: true),
                                                      hideHidden: false, isOnPreferredScreen: true))
    }

    // MARK: - D. Windowless apps

    func testWindowlessShownByDefault() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(isWindowlessApp: true), appState(),
                                                      isOnPreferredScreen: true))
    }

    func testHideWindowlessHidesIt() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(isWindowlessApp: true), appState(),
                                                       hideWindowless: true, isOnPreferredScreen: true))
    }

    func testWindowlessBypassesWindowOnlyFilters() {
        // A windowless row shows even under filters that would hide a real window — space/screen/min/full/tab only apply to real windows.
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(isWindowlessApp: true, spaceIds: [99]), appState(),
                                                      onlyVisibleSpaces: true, onlyPreferredScreen: true,
                                                      visibleSpaceIds: [1], isOnPreferredScreen: false))
    }

    // MARK: - E. Fullscreen

    func testHideFullscreenHidesFullscreen() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(isFullscreen: true), appState(),
                                                       hideFullscreen: true, isOnPreferredScreen: true))
    }

    func testFullscreenShownWhenNotHiding() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(isFullscreen: true), appState(),
                                                      hideFullscreen: false, isOnPreferredScreen: true))
    }

    // MARK: - F. Minimized

    func testHideMinimizedHidesMinimized() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(isMinimized: true), appState(),
                                                       hideMinimized: true, isOnPreferredScreen: true))
    }

    func testMinimizedShownWhenNotHiding() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(isMinimized: true), appState(),
                                                      hideMinimized: false, isOnPreferredScreen: true))
    }

    // MARK: - G. Spaces

    func testOnlyVisibleSpacesHidesWindowNotInVisibleSpace() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(spaceIds: [99]), appState(),
                                                       onlyVisibleSpaces: true, visibleSpaceIds: [1],
                                                       isOnPreferredScreen: true))
    }

    func testOnlyVisibleSpacesShowsWindowInVisibleSpace() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(spaceIds: [1]), appState(),
                                                      onlyVisibleSpaces: true, visibleSpaceIds: [1],
                                                      isOnPreferredScreen: true))
    }

    func testOnlyNonVisibleSpacesHidesWindowInVisibleSpace() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(spaceIds: [1]), appState(),
                                                       onlyNonVisibleSpaces: true, visibleSpaceIds: [1],
                                                       isOnPreferredScreen: true))
    }

    /// The first-tab vanish (live TABDIAG 2026-07-24): a tab held through the new-tab discovery gap is
    /// Space-less (its 1326 landed) but just backgrounded on the CURRENT visible Space, so it must still
    /// show under `.visible` even though nothing puts it in a visible Space.
    func testOnlyVisibleSpacesShowsSpacelessHeldTab() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(isHeldVisibleForTab: true, spaceIds: []), appState(),
                                                      onlyVisibleSpaces: true, visibleSpaceIds: [1],
                                                      isOnPreferredScreen: false))
    }

    /// The mirror: a held tab is on the visible Space, so `.nonVisible` must hide it.
    func testOnlyNonVisibleSpacesHidesHeldTab() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(isHeldVisibleForTab: true, spaceIds: []), appState(),
                                                       onlyNonVisibleSpaces: true, visibleSpaceIds: [1],
                                                       isOnPreferredScreen: true))
    }

    // MARK: - H. Screens

    func testOnlyPreferredScreenHidesOffScreenWindow() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(), appState(),
                                                       onlyPreferredScreen: true, isOnPreferredScreen: false))
    }

    func testOnlyPreferredScreenShowsOnScreenWindow() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(), appState(),
                                                      onlyPreferredScreen: true, isOnPreferredScreen: true))
    }

    /// A held tab is on the preferred screen (the swap happened there), so the preferred-screen gate must
    /// not drop it even when the OS reports it off-screen (a Space-less window has no screen to be on).
    func testOnlyPreferredScreenShowsHeldTab() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(isHeldVisibleForTab: true), appState(),
                                                      onlyPreferredScreen: true, isOnPreferredScreen: false))
    }

    // MARK: - I. Tabs (macOS native tabs)

    func testNonFrontmostTabHiddenWhenGrouping() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(isTabbed: true), appState(),
                                                       separateTabs: false, isOnPreferredScreen: true))
    }

    func testTabbedShownWhenSeparateTabs() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(isTabbed: true), appState(),
                                                      separateTabs: true, isOnPreferredScreen: true))
    }

    // MARK: - J. Combinations

    func testAllFiltersOnAndWindowPassesEachShows() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(
            ws(spaceIds: [1]), appState(pid: 100),
            onlyFrontmostApp: true, hideHidden: true, hideWindowless: true, hideFullscreen: true,
            hideMinimized: true, onlyVisibleSpaces: true, onlyPreferredScreen: true, separateTabs: false,
            frontmostPid: 100, visibleSpaceIds: [1], isOnPreferredScreen: true))
    }

    // MARK: - K. Under the cursor (appsToShow == .underCursor)

    func testOnlyUnderCursorHidesWindowNotUnderCursor() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(spaceIds: [1]), appState(),
                                                       onlyUnderCursor: true, visibleSpaceIds: [1],
                                                       isOnPreferredScreen: true, isUnderCursor: false))
    }

    func testOnlyUnderCursorShowsWindowUnderCursor() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(spaceIds: [1]), appState(),
                                                      onlyUnderCursor: true, visibleSpaceIds: [1],
                                                      isOnPreferredScreen: true, isUnderCursor: true))
    }

    /// The frame under the cursor must be drawn there: a minimized window, a hidden app's window, or a window
    /// on another Space keeps a stored frame that can contain the point, yet the user sees something else.
    func testOnlyUnderCursorHidesMinimizedWindowUnderCursor() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(isMinimized: true, spaceIds: [1]), appState(),
                                                       onlyUnderCursor: true, visibleSpaceIds: [1],
                                                       isOnPreferredScreen: true, isUnderCursor: true))
    }

    func testOnlyUnderCursorHidesHiddenAppWindowUnderCursor() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(spaceIds: [1]), appState(appIsHidden: true),
                                                       onlyUnderCursor: true, visibleSpaceIds: [1],
                                                       isOnPreferredScreen: true, isUnderCursor: true))
    }

    func testOnlyUnderCursorHidesWindowOnNonVisibleSpace() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(spaceIds: [2]), appState(),
                                                       onlyUnderCursor: true, visibleSpaceIds: [1],
                                                       isOnPreferredScreen: true, isUnderCursor: true))
    }

    /// A windowless placeholder has no frame, so it is never under the cursor.
    func testOnlyUnderCursorHidesWindowlessApp() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(isWindowlessApp: true), appState(),
                                                       onlyUnderCursor: true, isOnPreferredScreen: true,
                                                       isUnderCursor: true))
    }

    /// A held tab is Space-less but on the visible Space (same exemption as the Space gates), so it shows
    /// when its frame is under the cursor.
    func testOnlyUnderCursorShowsHeldTabUnderCursor() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(isHeldVisibleForTab: true), appState(),
                                                      onlyUnderCursor: true, visibleSpaceIds: [1],
                                                      isOnPreferredScreen: true, isUnderCursor: true))
    }

    /// `isUnderCursor` is the frame test only; the other dropdowns still apply on top of it.
    func testOnlyUnderCursorStillHonoursOtherFilters() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(isFullscreen: true, spaceIds: [1]), appState(),
                                                       onlyUnderCursor: true, hideFullscreen: true,
                                                       visibleSpaceIds: [1],
                                                       isOnPreferredScreen: true, isUnderCursor: true))
    }

    func testPhantomBeatsWindowlessShow() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(isPhantom: true, isWindowlessApp: true), appState(),
                                                       hideWindowless: false, isOnPreferredScreen: true))
    }
}
