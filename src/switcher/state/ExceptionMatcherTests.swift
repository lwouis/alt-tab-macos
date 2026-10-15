import XCTest

/// Pins the per-app exception matching: whether a window is hidden from the switcher (`hide` rule)
/// and whether AltTab's shortcuts are disabled while an app is frontmost (`ignore` rule). Operates
/// on canonical `WindowState` / `ApplicationState` records — no `Window`/`Application` references.
///
/// Groups: A per-exception hide rule · B hidesWindow (gate + hide) · C disablesShortcuts (gate + ignore) ·
/// D hidesWindow in `showOnlyListedApps` mode.
final class ExceptionMatcherTests: XCTestCase {

    private func entry(_ bundle: String, hide: ExceptionHidePreference = .none,
                       ignore: ExceptionIgnorePreference = .none, titles: [String]? = nil) -> ExceptionEntry {
        ExceptionEntry(bundleIdentifier: bundle, hide: hide, ignore: ignore, windowTitleContains: titles)
    }

    private func ws(title: String = "", isWindowlessApp: Bool = false) -> WindowState {
        WindowState(id: "w", isPhantom: false, isWindowlessApp: isWindowlessApp,
                    isFullscreen: false, isMinimized: false, isTabbed: false, isOnAllSpaces: false,
                    spaceIds: [], spaceIndexes: [], lastFocusOrder: 0, creationOrder: 0, title: title)
    }

    private func appState(bundleId: String? = nil) -> ApplicationState {
        ApplicationState(pid: 0, bundleIdentifier: bundleId, localizedName: nil, isHidden: false)
    }

    // MARK: - A. Per-exception hide rule (hideMatches)

    func testHideNoneNeverMatches() {
        XCTAssertFalse(ExceptionMatcher.hideMatches(entry("x", hide: .none), ws(title: "t")))
    }

    func testHideAlwaysMatches() {
        XCTAssertTrue(ExceptionMatcher.hideMatches(entry("x", hide: .always), ws(title: "t")))
    }

    func testHideWhenNoOpenWindowMatchesWindowlessOnly() {
        XCTAssertTrue(ExceptionMatcher.hideMatches(entry("x", hide: .whenNoOpenWindow), ws(isWindowlessApp: true)))
        XCTAssertFalse(ExceptionMatcher.hideMatches(entry("x", hide: .whenNoOpenWindow), ws(isWindowlessApp: false)))
    }

    func testHideWindowTitleContainsMatchesSubstring() {
        XCTAssertTrue(ExceptionMatcher.hideMatches(entry("x", hide: .windowTitleContains, titles: ["Inspector"]),
                                                   ws(title: "Web Inspector")))
    }

    func testHideWindowTitleContainsNoMatch() {
        XCTAssertFalse(ExceptionMatcher.hideMatches(entry("x", hide: .windowTitleContains, titles: ["Inspector"]),
                                                    ws(title: "Main Window")))
    }

    func testHideWindowTitleContainsNilOrEmptyPatternsNeverMatch() {
        XCTAssertFalse(ExceptionMatcher.hideMatches(entry("x", hide: .windowTitleContains, titles: nil), ws(title: "Main")))
        XCTAssertFalse(ExceptionMatcher.hideMatches(entry("x", hide: .windowTitleContains, titles: []), ws(title: "Main")))
        XCTAssertFalse(ExceptionMatcher.hideMatches(entry("x", hide: .windowTitleContains, titles: [""]), ws(title: "Main")))
    }

    func testHideAlwaysIgnoredWithActiveAppOverride() {
        XCTAssertFalse(ExceptionMatcher.hideMatches(entry("x", hide: .always), ws(title: "t"), activeAppOverride: true))
    }

    func testHideWhenNoOpenWindowIgnoredWithActiveAppOverride() {
        XCTAssertFalse(ExceptionMatcher.hideMatches(entry("x", hide: .whenNoOpenWindow), ws(isWindowlessApp: true), activeAppOverride: true))
    }

    func testHideWindowTitleContainsStillFiresWithActiveAppOverride() {
        XCTAssertTrue(ExceptionMatcher.hideMatches(entry("x", hide: .windowTitleContains, titles: ["Inspector"]),
                                                   ws(title: "Web Inspector"), activeAppOverride: true))
    }

    // MARK: - B. hidesWindow (bundle-id prefix gate + hide rule)

    func testHidesWindowWhenPrefixMatchesAndRuleFires() {
        XCTAssertTrue(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: "com.foo.bar"),
                                                   exceptions: [entry("com.foo", hide: .always)]))
    }

    func testDoesNotHideWhenPrefixDiffers() {
        XCTAssertFalse(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: "com.bar"),
                                                    exceptions: [entry("com.foo", hide: .always)]))
    }

    func testDoesNotHideWhenBundleIdentifierEmpty() {
        XCTAssertFalse(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: "com.foo"),
                                                    exceptions: [entry("", hide: .always)]))
    }

    func testDoesNotHideWhenAppBundleIdNil() {
        XCTAssertFalse(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: nil),
                                                    exceptions: [entry("com.foo", hide: .always)]))
    }

    func testHidesWindowMatchesAnyExceptionInList() {
        XCTAssertTrue(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: "com.foo"),
                                                   exceptions: [entry("com.other", hide: .always), entry("com.foo", hide: .always)]))
    }

    func testDoesNotHideWhenRuleIsNoneEvenIfPrefixMatches() {
        XCTAssertFalse(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: "com.foo"),
                                                    exceptions: [entry("com.foo", hide: .none)]))
    }

    func testActiveAppOverrideIgnoresAlwaysHide() {
        XCTAssertFalse(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: "com.foo.bar"),
                                                    exceptions: [entry("com.foo", hide: .always)], activeAppOverride: true))
    }

    func testActiveAppOverrideStillHidesByWindowTitle() {
        XCTAssertTrue(ExceptionMatcher.hidesWindow(ws(title: "Web Inspector"), appState(bundleId: "com.foo.bar"),
                                                   exceptions: [entry("com.foo", hide: .windowTitleContains, titles: ["Inspector"])],
                                                   activeAppOverride: true))
    }

    // MARK: - C. disablesShortcuts (bundle-id prefix gate + ignore rule)

    func testDisablesShortcutsWhenIgnoreAlways() {
        XCTAssertTrue(ExceptionMatcher.disablesShortcuts(appState(bundleId: "com.foo.bar"), isFullscreen: false,
                                                         exceptions: [entry("com.foo", ignore: .always)]))
    }

    func testDisablesShortcutsWhenFullscreenAndFullscreen() {
        XCTAssertTrue(ExceptionMatcher.disablesShortcuts(appState(bundleId: "com.foo"), isFullscreen: true,
                                                         exceptions: [entry("com.foo", ignore: .whenFullscreen)]))
    }

    func testDoesNotDisableWhenFullscreenRuleButNotFullscreen() {
        XCTAssertFalse(ExceptionMatcher.disablesShortcuts(appState(bundleId: "com.foo"), isFullscreen: false,
                                                          exceptions: [entry("com.foo", ignore: .whenFullscreen)]))
    }

    func testDoesNotDisableWhenIgnoreNone() {
        XCTAssertFalse(ExceptionMatcher.disablesShortcuts(appState(bundleId: "com.foo"), isFullscreen: true,
                                                          exceptions: [entry("com.foo", ignore: .none)]))
    }

    func testDoesNotDisableWhenPrefixDiffers() {
        XCTAssertFalse(ExceptionMatcher.disablesShortcuts(appState(bundleId: "com.bar"), isFullscreen: true,
                                                          exceptions: [entry("com.foo", ignore: .always)]))
    }

    func testDoesNotDisableWhenAppBundleIdNil() {
        XCTAssertFalse(ExceptionMatcher.disablesShortcuts(appState(bundleId: nil), isFullscreen: true,
                                                          exceptions: [entry("com.foo", ignore: .always)]))
    }

    // MARK: - D. hidesWindow in `showOnlyListedApps` mode (onlyListed)

    func testOnlyListedHidesUnlistedApp() {
        XCTAssertTrue(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: "com.other"),
                                                   exceptions: [entry("com.foo")], onlyListed: true))
    }

    func testOnlyListedShowsListedApp() {
        XCTAssertFalse(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: "com.foo"),
                                                    exceptions: [entry("com.foo")], onlyListed: true))
    }

    func testOnlyListedMatchesByPrefix() {
        XCTAssertFalse(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: "com.foo.bar"),
                                                    exceptions: [entry("com.foo")], onlyListed: true))
    }

    func testOnlyListedStillAppliesTheListedHideRule() {
        let listed = [entry("com.foo", hide: .windowTitleContains, titles: ["Inspector"])]
        XCTAssertTrue(ExceptionMatcher.hidesWindow(ws(title: "Web Inspector"), appState(bundleId: "com.foo"),
                                                   exceptions: listed, onlyListed: true))
        XCTAssertFalse(ExceptionMatcher.hidesWindow(ws(title: "Main"), appState(bundleId: "com.foo"),
                                                    exceptions: listed, onlyListed: true))
    }

    func testOnlyListedHidesEverythingWhenListIsEmpty() {
        XCTAssertTrue(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: "com.foo"),
                                                   exceptions: [], onlyListed: true))
    }

    func testOnlyListedDoesNotListEveryAppThroughAnEmptyBundleIdentifier() {
        XCTAssertTrue(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: "com.foo"),
                                                   exceptions: [entry("")], onlyListed: true))
    }

    func testOnlyListedHidesAppWithoutBundleId() {
        XCTAssertTrue(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: nil),
                                                   exceptions: [entry("com.foo")], onlyListed: true))
    }

    func testOnlyListedActiveAppOverrideShowsUnlistedApp() {
        XCTAssertFalse(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: "com.other"),
                                                    exceptions: [entry("com.foo")], onlyListed: true, activeAppOverride: true))
        XCTAssertFalse(ExceptionMatcher.hidesWindow(ws(), appState(bundleId: nil),
                                                    exceptions: [], onlyListed: true, activeAppOverride: true))
    }
}

final class ShortcutExceptionContextResolverTests: XCTestCase {
    private let process = ProcessGeneration(pid: 7, generation: 1)

    private func window(_ wid: UInt32, fullscreen: Bool, currentSpace: Bool = true)
        -> FullscreenWindowEvidence {
        FullscreenWindowEvidence(pid: process.pid, wid: wid, isFullscreen: fullscreen,
            isOnCurrentSpace: currentSpace)
    }

    func testExactAttentionUsesOnlyTheAttendedWindowsFullscreenState() {
        let context = CurrentUserContext.window(WindowIdentity(process: process, wid: 1))
        XCTAssertFalse(ShortcutExceptionContextResolver.isFullscreen(context, appPid: process.pid,
            activeWindowIsFullscreen: true,
            windows: [window(1, fullscreen: false), window(2, fullscreen: true)]))
    }

    func testExactAttentionRecognizesFullscreenOutsideCurrentSpaceCache() {
        let context = CurrentUserContext.window(WindowIdentity(process: process, wid: 1))
        XCTAssertTrue(ShortcutExceptionContextResolver.isFullscreen(context, appPid: process.pid,
            activeWindowIsFullscreen: false, windows: [window(1, fullscreen: true, currentSpace: false)]))
    }

    func testUnknownAndAppOnlyAttentionKeepConservativeFallback() {
        XCTAssertTrue(ShortcutExceptionContextResolver.isFullscreen(.unknown, appPid: process.pid,
            activeWindowIsFullscreen: false, windows: [window(2, fullscreen: true)]))
        XCTAssertTrue(ShortcutExceptionContextResolver.isFullscreen(.application(process), appPid: process.pid,
            activeWindowIsFullscreen: true, windows: []))
    }

    func testMissingExactWindowKeepsConservativeFallback() {
        let context = CurrentUserContext.window(WindowIdentity(process: process, wid: 99))
        XCTAssertTrue(ShortcutExceptionContextResolver.isFullscreen(context, appPid: process.pid,
            activeWindowIsFullscreen: false, windows: [window(2, fullscreen: true)]))
    }
}
