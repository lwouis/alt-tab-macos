import XCTest

/// Pins the branch order of `ShortcutModifierResolver.matches` (the decision extracted from
/// `ATShortcut.modifiersMatch`). Pure data in, `Bool` out — no AppKit, no globals. `ATShortcut` is
/// the thin adapter that feeds these inputs from `SwitcherSession` / `ControlsTab` / `TilesView`.
///
/// Groups: A holdShortcut ("contains at least") · B nextWindow base-key during a session ·
/// C the search-editing gate for modifier-only shortcuts (#5781, the previousWindow = ⇧ regression) ·
/// D default exact / exact+hold matching.
final class ShortcutModifierResolverTests: XCTestCase {

    // Opaque modifier bits — the kernel only compares bits, so real Carbon values aren't needed.
    private static let option: UInt32 = 1 << 0   // the default hold modifier in these scenarios
    private static let command: UInt32 = 1 << 1
    private static let shift: UInt32 = 1 << 2

    /// `matches` with the common defaults spelled out; each test overrides only what it exercises.
    private func match(event: UInt32, shortcut: UInt32, hold: UInt32 = option,
                       isHold: Bool = false, isNextWindow: Bool = false, sessionActive: Bool = false,
                       isModifierOnly: Bool = false, isEditing: Bool = false, hasCommand: Bool = false) -> Bool {
        ShortcutModifierResolver.matches(
            eventModifiers: event, shortcutModifiers: shortcut, holdModifiers: hold,
            isHoldShortcut: isHold, isNextWindowShortcut: isNextWindow, sessionActive: sessionActive,
            isModifierOnly: isModifierOnly, isSearchEditing: isEditing, shortcutHasCommandModifier: hasCommand)
    }

    // MARK: - A. holdShortcut: event contains at least the shortcut's modifiers

    func testHoldShortcutMatchesWhenEventContainsItsModifiers() {
        XCTAssertTrue(match(event: Self.option | Self.command, shortcut: Self.option, isHold: true))
    }

    func testHoldShortcutFailsWhenEventMissingItsModifiers() {
        XCTAssertFalse(match(event: Self.command, shortcut: Self.option, isHold: true))
    }

    // MARK: - B. nextWindowShortcut base key (hold stripped) while a session is active

    func testNextWindowMatchesBaseKeyWithoutHoldDuringSession() {
        // shortcut = ⌥⇥-style (command|option here), hold = option → base = command; bare command matches.
        XCTAssertTrue(match(event: Self.command, shortcut: Self.command | Self.option,
                            isNextWindow: true, sessionActive: true))
    }

    func testNextWindowBaseKeyNotMatchedWithoutSession() {
        // No session → base-key shortcut doesn't apply; falls through to default (no exact / exact+hold).
        XCTAssertFalse(match(event: Self.command, shortcut: Self.command | Self.option,
                             isNextWindow: true, sessionActive: false))
    }

    // MARK: - C. Search-editing gate for modifier-only shortcuts (previousWindow = ⇧, #5781)

    func testModifierOnlyBareDoesNotMatchWhileEditing() {
        // The regression: bare ⇧ while editing is uppercasing input, not "select previous window".
        XCTAssertFalse(match(event: Self.shift, shortcut: Self.shift, isModifierOnly: true, isEditing: true))
    }

    func testModifierOnlyWithHoldMatchesWhileEditing() {
        // ⌥⇧ navigates, as outside search.
        XCTAssertTrue(match(event: Self.shift | Self.option, shortcut: Self.shift, isModifierOnly: true, isEditing: true))
    }

    func testModifierOnlyBareMatchesWhenNotEditing() {
        // The gate is editing-only: in a normal session, bare ⇧ still selects the previous window.
        XCTAssertTrue(match(event: Self.shift, shortcut: Self.shift, isModifierOnly: true, isEditing: false))
    }

    // MARK: - D. Default matching (exact, or exact + hold), incl. key shortcuts while editing

    func testKeyShortcutMatchesExactModifiers() {
        XCTAssertTrue(match(event: Self.command, shortcut: Self.command))
    }

    func testKeyShortcutMatchesShortcutPlusHold() {
        // e.g. closeWindow = W (no modifiers) triggered as ⌥W: event = hold, shortcut = 0.
        XCTAssertTrue(match(event: Self.option, shortcut: 0))
    }

    func testKeyShortcutFailsWithExtraModifier() {
        XCTAssertFalse(match(event: Self.command | Self.shift, shortcut: Self.command))
    }

    func testKeyShortcutNotGatedWhileEditing() {
        // Key shortcuts (not modifier-only) keep default matching even while editing — they are gated
        // upstream in `routeKey`, not here. ⌥W still matches.
        XCTAssertTrue(match(event: Self.option, shortcut: 0, isModifierOnly: false, isEditing: true))
    }
}
