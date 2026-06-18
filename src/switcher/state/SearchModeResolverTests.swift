import XCTest

/// Documents every interaction of the in-switcher Search feature by pinning the decisions of the
/// `SearchModeResolver` kernel. Pure data in, `Equatable` decision out — no AppKit, no globals.
/// `TilesView` / `ShortcutAction` execute these decisions; this suite is the spec for what they do.
///
/// Groups: A entry · B toggle route · C enter-editing (+Pro gate) · D disable ·
/// E escape-depends-on-entry · F nav/tab · G shortcut pass-through · H text pass-through
/// (cmd+A/C/V/X) · I IME/menu early return · J field editability · K printable-key
/// disambiguation (bare typed key vs hold+key shortcut).
final class SearchModeResolverTests: XCTestCase {

    // MARK: - A. Session entry

    func testEntryStartedInSearchBeginsEditing() {
        XCTAssertEqual(SearchModeResolver.startMode(startInSearch: true), .editing)
    }

    func testEntryNormalSessionStartsOff() {
        XCTAssertEqual(SearchModeResolver.startMode(startInSearch: false), .off)
    }

    // MARK: - B. Toggle route (the search shortcut)

    func testToggleFromOffEntersEditing() {
        XCTAssertEqual(SearchModeResolver.toggle(mode: .off), .enterEditing)
    }

    func testToggleFromEditingDisables() {
        XCTAssertEqual(SearchModeResolver.toggle(mode: .editing), .disable)
    }

    // MARK: - C. Enter editing (Pro-gated)

    func testEnterFromOffEntersEditing() {
        XCTAssertEqual(SearchModeResolver.enableEditing(mode: .off, canSearch: true), .enterEditing)
    }

    func testEnterWhenAlreadyEditingJustPlacesCaret() {
        XCTAssertEqual(SearchModeResolver.enableEditing(mode: .editing, canSearch: true), .placeCaretOnly)
    }

    func testEnterBlockedWhenSearchNotEntitled() {
        // Gate is checked before the already-editing / state branches.
        XCTAssertEqual(SearchModeResolver.enableEditing(mode: .off, canSearch: false), .proGateBlocked)
    }

    // MARK: - D. Disable

    func testDisableFromEditingExitsToOff() {
        XCTAssertEqual(SearchModeResolver.disable(mode: .editing), .exitToOff)
    }

    func testDisableWhenAlreadyOffIsNoOp() {
        XCTAssertEqual(SearchModeResolver.disable(mode: .off), .noOp)
    }

    // MARK: - E. Escape depends on how search was entered

    func testEscapeEditingToggledMidSessionExitsSearch() {
        XCTAssertEqual(SearchModeResolver.escape(mode: .editing, entry: .toggledMidSession), .exitSearch)
    }

    func testEscapeEditingStartedInSearchClosesSwitcher() {
        // searchOnRelease: search is the session, so Escape closes the whole switcher.
        XCTAssertEqual(SearchModeResolver.escape(mode: .editing, entry: .startedInSearch), .closeSwitcher)
    }

    func testEscapeOffToggledMidSessionClosesSwitcher() {
        XCTAssertEqual(SearchModeResolver.escape(mode: .off, entry: .toggledMidSession), .closeSwitcher)
    }

    func testEscapeOffStartedInSearchClosesSwitcher() {
        XCTAssertEqual(SearchModeResolver.escape(mode: .off, entry: .startedInSearch), .closeSwitcher)
    }

    // MARK: - F. Key routing: navigation & tab

    func testKeyLeftArrowCyclesLeft() {
        XCTAssertEqual(SearchModeResolver.routeKey(arrow: .left), .cycleSelection(.left))
    }

    func testKeyRightArrowCyclesRight() {
        XCTAssertEqual(SearchModeResolver.routeKey(arrow: .right), .cycleSelection(.right))
    }

    func testKeyUpArrowCyclesUp() {
        XCTAssertEqual(SearchModeResolver.routeKey(arrow: .up), .cycleSelection(.up))
    }

    func testKeyDownArrowCyclesDown() {
        XCTAssertEqual(SearchModeResolver.routeKey(arrow: .down), .cycleSelection(.down))
    }

    func testKeyTabIsSwallowed() {
        XCTAssertEqual(SearchModeResolver.routeKey(isTab: true), .handled)
    }

    // MARK: - G. Key routing: shortcut pass-through

    func testKeyMatchedShortcutPassesToShortcuts() {
        // Any when-active shortcut (close / minimize / quit / focus / cancel / …) the caller matched
        // via `editingShortcutMatch` is handed to the shortcut pipeline.
        XCTAssertEqual(SearchModeResolver.routeKey(matchesShortcut: true), .passToShortcuts)
    }

    func testKeyArrowWinsOverMatchingShortcut() {
        // If an arrow is also bound as a shortcut, the arrow (navigation) branch takes precedence.
        XCTAssertEqual(SearchModeResolver.routeKey(arrow: .left, matchesShortcut: true), .cycleSelection(.left))
    }

    // MARK: - H. Key routing: text editing passes to the field (cmd+A/C/V/X, typed characters)

    func testKeyPlainTextPassesToField() {
        // A normal character / cmd+A / cmd+C / cmd+V / cmd+X is none of arrow/tab/shortcut, so it
        // falls through to the search field, where NSSearchField handles editing natively.
        XCTAssertEqual(SearchModeResolver.routeKey(), .passToField)
    }

    // MARK: - I. IME composing / open context menu beat everything (early return)

    func testKeyMarkedTextBeatsArrow() {
        XCTAssertEqual(SearchModeResolver.routeKey(hasMarkedText: true, arrow: .left), .passToField)
    }

    func testKeyOpenMenuBeatsTab() {
        XCTAssertEqual(SearchModeResolver.routeKey(isMenuOpen: true, isTab: true), .passToField)
    }

    func testKeyMarkedTextBeatsShortcut() {
        XCTAssertEqual(SearchModeResolver.routeKey(hasMarkedText: true, matchesShortcut: true), .passToField)
    }

    // MARK: - J. Search-field editability

    func testFieldEditableOnlyWhenEditing() {
        XCTAssertTrue(SearchModeResolver.isFieldEditable(.editing))
        XCTAssertFalse(SearchModeResolver.isFieldEditable(.off))
    }

    // MARK: - K. editingShortcutMatch: a bare printable key is typed text, not a shortcut

    // Opaque modifier bits — the kernel treats them as bitmasks, so real Carbon values aren't needed.
    private static let option: UInt32 = 1 << 0
    private static let command: UInt32 = 1 << 1
    private static let shift: UInt32 = 1 << 2

    func testEditingNonPrintableBareMatches() {
        // The default `cancel = Escape`: non-printable, so a bare tap still exits search.
        XCTAssertTrue(SearchModeResolver.editingShortcutMatch(
            eventModifiers: 0, shortcutModifiers: 0, holdModifiers: Self.option,
            isPrintable: false, shortcutHasCommandModifier: false))
    }

    func testEditingPrintableBareIsTypedTextNotShortcut() {
        // `cancel = Q`, hold released to type: bare `q` is text, not cancel (#5781).
        XCTAssertFalse(SearchModeResolver.editingShortcutMatch(
            eventModifiers: 0, shortcutModifiers: 0, holdModifiers: Self.option,
            isPrintable: true, shortcutHasCommandModifier: false))
    }

    func testEditingPrintableWithHoldModifiersMatches() {
        // Re-pressing the hold modifiers (e.g. Cmd+Option+Q) triggers the shortcut, as outside search.
        let hold = Self.command | Self.option
        XCTAssertTrue(SearchModeResolver.editingShortcutMatch(
            eventModifiers: hold, shortcutModifiers: 0, holdModifiers: hold,
            isPrintable: true, shortcutHasCommandModifier: false))
    }

    func testEditingPrintableSpecialCharTypesWhenEventLacksFullHold() {
        // hold = Cmd+Option, `cancel = Q`: Option-only `Q` (typing `œ`) is NOT the cancel chord, so it
        // falls through to the field. Special-character input survives.
        XCTAssertFalse(SearchModeResolver.editingShortcutMatch(
            eventModifiers: Self.option, shortcutModifiers: 0, holdModifiers: Self.command | Self.option,
            isPrintable: true, shortcutHasCommandModifier: false))
    }

    func testEditingPrintableBareKeptWhenNoHoldModifier() {
        // With no hold modifier there is no alternative chord, so the bare arm stays (status quo) rather
        // than leaving the shortcut untriggerable.
        XCTAssertTrue(SearchModeResolver.editingShortcutMatch(
            eventModifiers: 0, shortcutModifiers: 0, holdModifiers: 0,
            isPrintable: true, shortcutHasCommandModifier: false))
    }

    func testEditingPrintableBindingWithCommandModifierMatchesBare() {
        // A binding that already carries Cmd/Ctrl (e.g. `cancel = Cmd+Q`) is clearly a command, never
        // typed text, so its bare arm is honored.
        XCTAssertTrue(SearchModeResolver.editingShortcutMatch(
            eventModifiers: Self.command, shortcutModifiers: Self.command, holdModifiers: Self.option,
            isPrintable: true, shortcutHasCommandModifier: true))
    }

    func testEditingWindowActionTypesBareButTriggersWithHold() {
        // A default window action like `closeWindow = W`: bare `w` types into the field; hold+W closes.
        // This is the generalization of #5781 to the full when-active shortcut set.
        XCTAssertFalse(SearchModeResolver.editingShortcutMatch(
            eventModifiers: 0, shortcutModifiers: 0, holdModifiers: Self.option,
            isPrintable: true, shortcutHasCommandModifier: false))
        XCTAssertTrue(SearchModeResolver.editingShortcutMatch(
            eventModifiers: Self.option, shortcutModifiers: 0, holdModifiers: Self.option,
            isPrintable: true, shortcutHasCommandModifier: false))
    }

    func testEditingModifierOnlyShortcutTypesBareButTriggersWithHold() {
        // A modifier-only when-active shortcut like `previousWindow = ⇧`: bare Shift is uppercasing
        // input and must NOT navigate; ⌥⇧ navigates. These arrive as flagsChanged (no keyDown), so
        // `ATShortcut.modifiersMatch` feeds them through here with isPrintable: true while editing.
        XCTAssertFalse(SearchModeResolver.editingShortcutMatch(
            eventModifiers: Self.shift, shortcutModifiers: Self.shift, holdModifiers: Self.option,
            isPrintable: true, shortcutHasCommandModifier: false))
        XCTAssertTrue(SearchModeResolver.editingShortcutMatch(
            eventModifiers: Self.shift | Self.option, shortcutModifiers: Self.shift, holdModifiers: Self.option,
            isPrintable: true, shortcutHasCommandModifier: false))
    }
}
