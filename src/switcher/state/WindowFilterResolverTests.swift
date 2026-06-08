import XCTest

/// Documents the per-shortcut "which windows show in the switcher" matrix by pinning
/// `WindowFilterResolver.shouldShow` against canonical `WindowState` / `ApplicationState` snapshots.
/// Each test starts from a plain visible real window + an all-permissive config and flips exactly one
/// knob, so every filter dimension is isolated.
///
/// Groups: A always-excluded · B app scope · C hidden apps · D windowless · E fullscreen ·
/// F minimized · G spaces · H screens · I tabs · J combinations.
final class WindowFilterResolverTests: XCTestCase {

    private func ws(isPhantom: Bool = false, isWindowlessApp: Bool = false, isFullscreen: Bool = false,
                    isMinimized: Bool = false, isTabbed: Bool = false, isOnAllSpaces: Bool = false,
                    spaceIds: [UInt64] = [], title: String = "Title") -> WindowState {
        WindowState(id: "w", isPhantom: isPhantom, isWindowlessApp: isWindowlessApp,
                    isFullscreen: isFullscreen, isMinimized: isMinimized, isTabbed: isTabbed,
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

    // MARK: - H. Screens

    func testOnlyPreferredScreenHidesOffScreenWindow() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(), appState(),
                                                       onlyPreferredScreen: true, isOnPreferredScreen: false))
    }

    func testOnlyPreferredScreenShowsOnScreenWindow() {
        XCTAssertTrue(WindowFilterResolver.shouldShow(ws(), appState(),
                                                      onlyPreferredScreen: true, isOnPreferredScreen: true))
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

    func testPhantomBeatsWindowlessShow() {
        XCTAssertFalse(WindowFilterResolver.shouldShow(ws(isPhantom: true, isWindowlessApp: true), appState(),
                                                       hideWindowless: false, isOnPreferredScreen: true))
    }
}
