import XCTest

/// Documents every interaction of the in-switcher Search feature by pinning the decisions of the
/// `SearchModeResolver` kernel. Pure data in, `Equatable` decision out — no AppKit, no globals.
/// `TilesView` / `ShortcutAction` execute these decisions; this suite is the spec for what they do.
///
/// Groups: A entry · B toggle route · C enter-editing (+Pro gate) · D disable · E lock/unlock
/// (+Pro gate) · F escape-depends-on-entry · G nav/tab · H shortcut pass-through · I text
/// pass-through (cmd+A/C/V/X) · J IME/menu early return · K field editability.
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

    func testToggleFromLockedReEntersEditing() {
        XCTAssertEqual(SearchModeResolver.toggle(mode: .locked), .enterEditing)
    }

    // MARK: - C. Enter editing (Pro-gated)

    func testEnterFromOffEntersEditingAndRefreshes() {
        XCTAssertEqual(SearchModeResolver.enableEditing(mode: .off, canSearch: true), .enterEditing(refreshUi: true))
    }

    func testEnterFromLockedEntersEditingWithoutRefresh() {
        XCTAssertEqual(SearchModeResolver.enableEditing(mode: .locked, canSearch: true), .enterEditing(refreshUi: false))
    }

    func testEnterWhenAlreadyEditingJustPlacesCaret() {
        XCTAssertEqual(SearchModeResolver.enableEditing(mode: .editing, canSearch: true), .placeCaretOnly)
    }

    func testEnterBlockedWhenSearchNotEntitledFromOff() {
        XCTAssertEqual(SearchModeResolver.enableEditing(mode: .off, canSearch: false), .proGateBlocked(.search))
    }

    func testEnterBlockedWhenSearchNotEntitledFromLocked() {
        // Gate is checked before the already-editing / state branches.
        XCTAssertEqual(SearchModeResolver.enableEditing(mode: .locked, canSearch: false), .proGateBlocked(.search))
    }

    // MARK: - D. Disable

    func testDisableFromEditingExitsToOff() {
        XCTAssertEqual(SearchModeResolver.disable(mode: .editing), .exitToOff)
    }

    func testDisableFromLockedExitsToOff() {
        XCTAssertEqual(SearchModeResolver.disable(mode: .locked), .exitToOff)
    }

    func testDisableWhenAlreadyOffIsNoOp() {
        XCTAssertEqual(SearchModeResolver.disable(mode: .off), .noOp)
    }

    // MARK: - E. Lock / unlock (Pro-gated)

    func testLockFromEditingLocksResults() {
        XCTAssertEqual(SearchModeResolver.lock(mode: .editing, canLockSearch: true), .lockResults)
    }

    func testLockFromLockedUnlocksToEditing() {
        XCTAssertEqual(SearchModeResolver.lock(mode: .locked, canLockSearch: true), .unlockToEditing)
    }

    func testLockFromOffIsNoOp() {
        XCTAssertEqual(SearchModeResolver.lock(mode: .off, canLockSearch: true), .noOp)
    }

    func testLockBlockedWhenNotEntitledFromEditing() {
        XCTAssertEqual(SearchModeResolver.lock(mode: .editing, canLockSearch: false), .proGateBlocked(.lockSearch))
    }

    func testLockBlockedWhenNotEntitledFromLocked() {
        // Gate is checked before the editing/locked branch.
        XCTAssertEqual(SearchModeResolver.lock(mode: .locked, canLockSearch: false), .proGateBlocked(.lockSearch))
    }

    // MARK: - F. Escape depends on how search was entered

    func testEscapeEditingToggledMidSessionExitsSearch() {
        XCTAssertEqual(SearchModeResolver.escape(mode: .editing, entry: .toggledMidSession), .exitSearch)
    }

    func testEscapeLockedToggledMidSessionExitsSearch() {
        XCTAssertEqual(SearchModeResolver.escape(mode: .locked, entry: .toggledMidSession), .exitSearch)
    }

    func testEscapeEditingStartedInSearchClosesSwitcher() {
        // searchOnRelease: search is the session, so Escape closes the whole switcher.
        XCTAssertEqual(SearchModeResolver.escape(mode: .editing, entry: .startedInSearch), .closeSwitcher)
    }

    func testEscapeLockedStartedInSearchClosesSwitcher() {
        XCTAssertEqual(SearchModeResolver.escape(mode: .locked, entry: .startedInSearch), .closeSwitcher)
    }

    func testEscapeOffToggledMidSessionClosesSwitcher() {
        XCTAssertEqual(SearchModeResolver.escape(mode: .off, entry: .toggledMidSession), .closeSwitcher)
    }

    func testEscapeOffStartedInSearchClosesSwitcher() {
        XCTAssertEqual(SearchModeResolver.escape(mode: .off, entry: .startedInSearch), .closeSwitcher)
    }

    // MARK: - G. Key routing: navigation & tab

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

    // MARK: - H. Key routing: shortcut pass-through

    func testKeyCancelPassesToShortcuts() {
        XCTAssertEqual(SearchModeResolver.routeKey(matchesCancel: true), .passToShortcuts)
    }

    func testKeyLockSearchPassesToShortcuts() {
        XCTAssertEqual(SearchModeResolver.routeKey(matchesLockSearch: true), .passToShortcuts)
    }

    func testKeyFocusPassesToShortcuts() {
        XCTAssertEqual(SearchModeResolver.routeKey(matchesFocus: true), .passToShortcuts)
    }

    func testKeyArrowWinsOverMatchingShortcut() {
        // If an arrow is also bound as a shortcut, the arrow (navigation) branch takes precedence.
        XCTAssertEqual(SearchModeResolver.routeKey(arrow: .left, matchesCancel: true), .cycleSelection(.left))
    }

    // MARK: - I. Key routing: text editing passes to the field (cmd+A/C/V/X, typed characters)

    func testKeyPlainTextPassesToField() {
        // A normal character / cmd+A / cmd+C / cmd+V / cmd+X is none of arrow/tab/cancel/lock/focus,
        // so it falls through to the search field, where NSSearchField handles editing natively.
        XCTAssertEqual(SearchModeResolver.routeKey(), .passToField)
    }

    // MARK: - J. IME composing / open context menu beat everything (early return)

    func testKeyMarkedTextBeatsArrow() {
        XCTAssertEqual(SearchModeResolver.routeKey(hasMarkedText: true, arrow: .left), .passToField)
    }

    func testKeyOpenMenuBeatsTab() {
        XCTAssertEqual(SearchModeResolver.routeKey(isMenuOpen: true, isTab: true), .passToField)
    }

    func testKeyMarkedTextBeatsShortcut() {
        XCTAssertEqual(SearchModeResolver.routeKey(hasMarkedText: true, matchesCancel: true), .passToField)
    }

    // MARK: - K. Search-field editability

    func testFieldEditableOnlyWhenEditing() {
        XCTAssertTrue(SearchModeResolver.isFieldEditable(.editing))
        XCTAssertFalse(SearchModeResolver.isFieldEditable(.off))
        XCTAssertFalse(SearchModeResolver.isFieldEditable(.locked))
    }
}
