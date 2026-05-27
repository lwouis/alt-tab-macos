import Cocoa
import ShortcutRecorder
import XCTest

/// Pins the `UserDefaults` transforms in `PreferencesMigrations`. These run on every app upgrade,
/// so a regression here silently corrupts real users' settings — the highest-value safety net in
/// the suite. Each test seeds the "old" keys in an isolated `UserDefaults` suite (injected via
/// `PreferencesMigrations.defaults`), runs ONE migration, and asserts the resulting keys + removals.
///
/// `migrateShortcutPreferencesToSecureCoding` and `migrateLoginItem` are intentionally NOT covered:
/// the former needs the real NSKeyedArchiver/ShortcutRecorder codec (stubbed compile-only here), the
/// latter mutates real Login Items via deprecated LaunchServices APIs.
///
/// Groups: A version gating · B grouping→per-shortcut · C language remap · D/E/F exceptions ·
/// G/H show-windows dropdowns · I gestures · J cursor · K menubar · L/M sizes · N shortcuts · P dropdowns.
final class PreferencesMigrationsTests: XCTestCase {
    var defaults: UserDefaults!
    var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test-migrations-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        PreferencesMigrations.defaults = defaults
    }

    override func tearDown() {
        PreferencesMigrations.defaults = .standard
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - A. Version gating (shouldRun)

    func testVersionGatingRunsForOlderStoredVersion() {
        XCTAssertTrue(PreferencesMigrations.shouldRun("6.0.0", "10.13.0"))
    }

    func testVersionGatingRunsForEqualVersion() {
        XCTAssertTrue(PreferencesMigrations.shouldRun("10.13.0", "10.13.0"))
    }

    func testVersionGatingSkipsForNewerStoredVersion() {
        XCTAssertFalse(PreferencesMigrations.shouldRun("11.0.0", "10.13.0"))
    }

    func testVersionGatingUsesNumericCompareNotLexical() {
        // Lexical would say "9" > "10"; numeric must say 9 < 10 so the migration still runs.
        XCTAssertTrue(PreferencesMigrations.shouldRun("9.0.0", "10.0.0"))
    }

    // MARK: - B. Grouping moved global -> per-shortcut

    func testGroupingCopiesGlobalShowAppsOrWindowsToPerShortcutKeysAndRemovesGlobal() {
        defaults.set("1", forKey: "showAppsOrWindows")
        PreferencesMigrations.migrateGroupingToPerShortcut()
        // index 0's key IS the global key, which is removed at the end — so it ends up nil.
        XCTAssertNil(defaults.string(forKey: "showAppsOrWindows"))
        XCTAssertEqual(defaults.string(forKey: "showAppsOrWindows2"), "1")
        XCTAssertEqual(defaults.string(forKey: "showAppsOrWindows10"), "1")
    }

    func testGroupingDoesNotOverwriteExistingPerShortcutValue() {
        defaults.set("1", forKey: "showAppsOrWindows")
        defaults.set("2", forKey: "showAppsOrWindows2")
        PreferencesMigrations.migrateGroupingToPerShortcut()
        XCTAssertEqual(defaults.string(forKey: "showAppsOrWindows2"), "2")
    }

    func testGroupingConvertsShowTabsAsWindowsBoolGlobalToEnumIndex() {
        defaults.set("false", forKey: "showTabsAsWindows")
        PreferencesMigrations.migrateGroupingToPerShortcut()
        XCTAssertNil(defaults.string(forKey: "showTabsAsWindows"))
        XCTAssertEqual(defaults.string(forKey: "showTabsAsWindows2"), "0")
        XCTAssertEqual(defaults.string(forKey: "showTabsAsWindows10"), "0")
    }

    func testGroupingConvertsPreExistingPerShortcutBoolString() {
        defaults.set("true", forKey: "showTabsAsWindows3")
        PreferencesMigrations.migrateGroupingToPerShortcut()
        XCTAssertEqual(defaults.string(forKey: "showTabsAsWindows3"), "1")
    }

    // MARK: - C. Language index remap (59 cases -> 21)

    func testLanguageRemapsKnownIndex() {
        defaults.set("5", forKey: "language") // 5 -> 2 in the remap table
        PreferencesMigrations.migrateLanguagePreferenceIndex()
        XCTAssertEqual(defaults.string(forKey: "language"), "2")
    }

    func testLanguageRemapsLastKnownIndex() {
        defaults.set("58", forKey: "language") // 58 -> 21
        PreferencesMigrations.migrateLanguagePreferenceIndex()
        XCTAssertEqual(defaults.string(forKey: "language"), "21")
    }

    func testLanguageRemovedLanguageFallsBackToSystemDefault() {
        defaults.set("3", forKey: "language") // not in the table -> 0 (systemDefault)
        PreferencesMigrations.migrateLanguagePreferenceIndex()
        XCTAssertEqual(defaults.string(forKey: "language"), "0")
    }

    func testLanguageNoStoredValueIsNoOp() {
        PreferencesMigrations.migrateLanguagePreferenceIndex()
        XCTAssertNil(defaults.string(forKey: "language"))
    }

    // MARK: - D. Blacklist -> exceptions (rename)

    func testBlacklistCopiedToExceptionsAndRemoved() {
        defaults.set("com.foo", forKey: "blacklist")
        PreferencesMigrations.migrateBlacklistToExceptions()
        XCTAssertEqual(defaults.string(forKey: "exceptions"), "com.foo")
        XCTAssertNil(defaults.string(forKey: "blacklist"))
    }

    func testBlacklistDoesNotOverwriteExistingExceptions() {
        defaults.set("com.foo", forKey: "blacklist")
        defaults.set("com.bar", forKey: "exceptions")
        PreferencesMigrations.migrateBlacklistToExceptions()
        XCTAssertEqual(defaults.string(forKey: "exceptions"), "com.bar")
        XCTAssertNil(defaults.string(forKey: "blacklist"))
    }

    // MARK: - E. Legacy blacklists -> structured exceptions

    func testExceptionsFromDontShowBlacklistBecomesHideAlways() throws {
        defaults.set("com.foo", forKey: "dontShowBlacklist")
        PreferencesMigrations.migrateExceptions()
        let entries = try decodeExceptions()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].bundleIdentifier, "com.foo")
        XCTAssertEqual(entries[0].hide, .always)
        XCTAssertEqual(entries[0].ignore, .none)
        XCTAssertNil(defaults.string(forKey: "dontShowBlacklist"))
    }

    func testExceptionsFromDisableShortcutsOnlyFullscreenBecomesIgnoreWhenFullscreen() throws {
        defaults.set("com.bar", forKey: "disableShortcutsBlacklist")
        defaults.set(true, forKey: "disableShortcutsBlacklistOnlyFullscreen")
        PreferencesMigrations.migrateExceptions()
        let entries = try decodeExceptions()
        XCTAssertEqual(entries[0].bundleIdentifier, "com.bar")
        XCTAssertEqual(entries[0].hide, .none)
        XCTAssertEqual(entries[0].ignore, .whenFullscreen)
        XCTAssertNil(defaults.string(forKey: "disableShortcutsBlacklist"))
    }

    // MARK: - F. windowTitleContains String -> [String]

    func testTitleArrayWrapsLegacyStringIntoArray() throws {
        defaults.set(#"[{"bundleIdentifier":"com.x","hide":"1","ignore":"0","windowTitleContains":"abc"}]"#, forKey: "exceptions")
        PreferencesMigrations.migrateExceptionsTitleArray()
        let entries = try decodeExceptions()
        XCTAssertEqual(entries[0].windowTitleContains, ["abc"])
    }

    func testTitleArrayEmptyLegacyStringBecomesNil() throws {
        defaults.set(#"[{"bundleIdentifier":"com.x","hide":"1","ignore":"0","windowTitleContains":""}]"#, forKey: "exceptions")
        PreferencesMigrations.migrateExceptionsTitleArray()
        let entries = try decodeExceptions()
        XCTAssertNil(entries[0].windowTitleContains)
    }

    func testTitleArrayIsIdempotentOnAlreadyMigratedData() throws {
        // Already array form: decoding into the legacy (String?) shape fails -> early return, unchanged.
        defaults.set(#"[{"bundleIdentifier":"com.x","hide":"1","ignore":"0","windowTitleContains":["keep"]}]"#, forKey: "exceptions")
        PreferencesMigrations.migrateExceptionsTitleArray()
        let entries = try decodeExceptions()
        XCTAssertEqual(entries[0].windowTitleContains, ["keep"])
    }

    // MARK: - G. showWindowlessApps value remap

    func testShowWindowlessAppsOldShowAtEndBecomesTwo() {
        defaults.set("0", forKey: "showWindowlessApps") // old showAtTheEnd (0) -> 2
        PreferencesMigrations.migrateShowWindowlessApps()
        XCTAssertEqual(defaults.string(forKey: "showWindowlessApps"), "2")
    }

    func testShowWindowlessAppsOtherValueBecomesOne() {
        defaults.set("1", forKey: "showWindowlessApps2")
        PreferencesMigrations.migrateShowWindowlessApps()
        XCTAssertEqual(defaults.string(forKey: "showWindowlessApps2"), "1")
    }

    // MARK: - H. Show-windows checkbox -> dropdown

    func testShowWindowsCheckboxTrueBecomesShow() {
        defaults.set("true", forKey: "showMinimizedWindows")
        PreferencesMigrations.migrateShowWindowsCheckboxToDropdown()
        XCTAssertEqual(defaults.string(forKey: "showMinimizedWindows"), "0") // .show
    }

    func testShowWindowsCheckboxFalseBecomesHide() {
        defaults.set("false", forKey: "showHiddenWindows")
        PreferencesMigrations.migrateShowWindowsCheckboxToDropdown()
        XCTAssertEqual(defaults.string(forKey: "showHiddenWindows"), "1") // .hide
    }

    // MARK: - I. Gestures split

    func testGesturesFourFingerRemapsToHorizontal() {
        defaults.set("2", forKey: "nextWindowGesture") // 2 (4-finger) -> 3 (4-finger-horizontal)
        PreferencesMigrations.migrateGestures()
        XCTAssertEqual(defaults.string(forKey: "nextWindowGesture"), "3")
    }

    func testGesturesOtherValueUnchanged() {
        defaults.set("1", forKey: "nextWindowGesture")
        PreferencesMigrations.migrateGestures()
        XCTAssertEqual(defaults.string(forKey: "nextWindowGesture"), "1")
    }

    // MARK: - J. cursorFollowFocus toggle -> dropdown

    func testCursorFollowFocusTrueBecomesAlways() {
        defaults.set("true", forKey: "cursorFollowFocusEnabled")
        PreferencesMigrations.migrateCursorFollowFocus()
        XCTAssertEqual(defaults.integer(forKey: "cursorFollowFocus"), 1)
    }

    func testCursorFollowFocusFalseBecomesNever() {
        defaults.set("false", forKey: "cursorFollowFocusEnabled")
        PreferencesMigrations.migrateCursorFollowFocus()
        XCTAssertEqual(defaults.integer(forKey: "cursorFollowFocus"), 0)
    }

    // MARK: - K. Menubar icon hidden-value -> shown toggle

    func testMenubarIconHiddenValueSplitsIntoShownToggle() {
        defaults.set("3", forKey: "menubarIcon") // 3 meant "hidden"
        PreferencesMigrations.migrateMenubarIconWithNewShownToggle()
        XCTAssertEqual(defaults.string(forKey: "menubarIcon"), "0")
        XCTAssertEqual(defaults.string(forKey: "menubarIconShown"), "false")
    }

    // MARK: - L/M. Width / size splits

    func testMinMaxWidthZeroBecomesOne() {
        defaults.set("0", forKey: "windowMinWidthInRow")
        PreferencesMigrations.migrateMinMaxWindowsWidthInRow()
        XCTAssertEqual(defaults.string(forKey: "windowMinWidthInRow"), "1")
    }

    func testMaxSizeOnScreenSplitsIntoWidthAndHeight() {
        defaults.set("80", forKey: "maxScreenUsage")
        PreferencesMigrations.migrateMaxSizeOnScreenToWidthAndHeight()
        XCTAssertEqual(defaults.string(forKey: "maxWidthOnScreen"), "80")
        XCTAssertEqual(defaults.string(forKey: "maxHeightOnScreen"), "80")
    }

    // MARK: - N. nextWindowShortcut hold-modifier cleanup + index move

    func testNextWindowShortcutStripsHoldModifierChars() {
        defaults.set("⌥", forKey: "holdShortcut")
        defaults.set("⌥⇥", forKey: "nextWindowShortcut")
        PreferencesMigrations.migrateNextWindowShortcuts()
        XCTAssertEqual(defaults.string(forKey: "nextWindowShortcut"), "⇥")
    }

    func testShortcutIndexesMoveSuffix4To10AndSetCount() {
        defaults.set("X", forKey: "nextWindowGesture4")
        defaults.set("dummy", forKey: "holdShortcut3") // a 3rd shortcut exists
        PreferencesMigrations.migrateShortcutIndexes()
        XCTAssertEqual(defaults.string(forKey: "nextWindowGesture10"), "X")
        XCTAssertNil(defaults.string(forKey: "nextWindowGesture4"))
        XCTAssertEqual(defaults.string(forKey: "shortcutCount"), "3")
    }

    // MARK: - P. Dropdowns: English text -> indexes

    func testDropdownTextValuesBecomeIndexes() {
        defaults.set("Active app", forKey: "appsToShow")
        defaults.set("❖ Windows 10", forKey: "theme")
        PreferencesMigrations.migrateDropdownsFromTextToIndexes()
        XCTAssertEqual(defaults.string(forKey: "appsToShow"), "1")
        XCTAssertEqual(defaults.string(forKey: "theme"), "1")
    }

    // MARK: - Helpers

    private func decodeExceptions() throws -> [ExceptionEntry] {
        let raw = try XCTUnwrap(defaults.string(forKey: "exceptions"), "expected an 'exceptions' JSON string")
        return try JSONDecoder().decode([ExceptionEntry].self, from: Data(raw.utf8))
    }
}

// MARK: - Test-target stand-ins for app-only symbols
//
// `PreferencesMigrations.swift` is compiled into the test target so we can pin its UserDefaults
// transforms; the regular `Preferences.swift` / `MacroPreferences.swift` aren't (they drag in the
// whole prefs/AppKit graph). The declarations below stand in for the symbols those files supply.
//
// FAITHFUL stubs (behavior matches production, so the migrations that use them are tested for real):
//   - ExceptionEntry + ExceptionHide/IgnorePreference: same fields + same String rawValues, so the
//     JSON produced by `jsonEncode` is byte-identical to production.
//   - ShowHowPreference.indexAsString: same case order / index values.
//   - Preferences.jsonEncode: the real JSONEncoder round-trip.
// COMPILE-ONLY stubs (the migration that uses them is intentionally NOT covered — noted in the spec):
//   - the shortcut-codec helpers (decode/unarchive/store/fromKeyEquivalent) + allShortcutPreferenceKeys,
//     used only by `migrateShortcutPreferencesToSecureCoding`.

// Faithful: exceptions model (matches src/preferences/Preferences.swift + MacroPreferences.swift)

enum ExceptionHidePreference: String, Codable, CaseIterable {
    case none = "0"
    case always = "1"
    case whenNoOpenWindow = "2"
    case windowTitleContains = "3"
}

enum ExceptionIgnorePreference: String, Codable, CaseIterable {
    case none = "0"
    case always = "1"
    case whenFullscreen = "2"
}

struct ExceptionEntry: Codable, Equatable {
    var bundleIdentifier: String
    var hide: ExceptionHidePreference
    var ignore: ExceptionIgnorePreference
    var windowTitleContains: [String]?

    init(bundleIdentifier: String, hide: ExceptionHidePreference, ignore: ExceptionIgnorePreference, windowTitleContains: [String]? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.hide = hide
        self.ignore = ignore
        self.windowTitleContains = windowTitleContains
    }
}

// Faithful: ShowHowPreference index mapping (show=0, hide=1, showAtTheEnd=2)

enum ShowHowPreference {
    case show
    case hide
    case showAtTheEnd

    var indexAsString: String {
        switch self {
            case .show: return "0"
            case .hide: return "1"
            case .showAtTheEnd: return "2"
        }
    }
}

// App-only singletons referenced by `migratePreferences()` (not exercised by the per-migration tests)

extension App {
    static let version = "99.99.99"
}

enum ProTransitionState {
    static func markFreshInstallIfUnknown(_ value: Bool) {}
}

enum AxError: Error {
    case runtimeError
}

// Preferences codec surface used by the migrations

extension Preferences {
    /// Faithful: same JSONEncoder default behavior as production, so exceptions migrations are tested for real.
    static func jsonEncode<T>(_ value: T) -> String where T: Encodable {
        let data = try! JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
    }

    // Compile-only: only `migrateShortcutPreferencesToSecureCoding` uses these, which is not covered
    // by the test suite (it needs the real NSKeyedArchiver/ShortcutRecorder codec). Empty key list
    // makes that migration a no-op here.
    static var allShortcutPreferenceKeys: [String] { [] }
    static func decodeShortcutStorage(_ value: Any) -> (Bool, Shortcut?) { (false, nil) }
    static func shortcutStorage(_ shortcut: Shortcut?, _ stringRepresentation: String?) -> [String: Any] { [:] }
    static func unarchiveShortcut(_ data: Data) -> (Bool, Shortcut?) { (false, nil) }
    static func shortcutFromKeyEquivalent(_ keyEquivalent: String) -> Shortcut? { nil }
}
