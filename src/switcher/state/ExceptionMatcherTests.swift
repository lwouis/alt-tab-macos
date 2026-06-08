import XCTest

/// Pins the per-app exception matching: whether a window is hidden from the switcher (`hide` rule)
/// and whether AltTab's shortcuts are disabled while an app is frontmost (`ignore` rule). Operates
/// on canonical `WindowState` / `ApplicationState` records — no `Window`/`Application` references.
///
/// Groups: A per-exception hide rule · B hidesWindow (gate + hide) · C disablesShortcuts (gate + ignore).
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
}
