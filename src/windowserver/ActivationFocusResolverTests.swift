import XCTest

/// Pins the activation-focus decisions (`ActivationFocusResolver`) — which 808s bump the MRU around an app
/// activation, and when the AX backstop yields — against the recorded ground truth that produced them
/// (TextEdit storm, iTerm single-808, #5596). See ActivationFocusResolverSpecs.md.
final class ActivationFocusResolverTests: XCTestCase {

    private func entry(wids: Set<CGWindowID> = [1, 2], until: TimeInterval = 100, focusBumped: Bool = false) -> ActivationEntry {
        ActivationEntry(wids: wids, until: until, focusBumped: focusBumped)
    }

    // MARK: - onFocusEvent

    func testFirstFocusOfActivationBumpsEvenWhileInactive() {
        // the iTerm case (#5596): a single 808 arrives right after activation, while
        // NSRunningApplication.isActive can still read false — it IS the focus, it must bump.
        let d = ActivationFocusResolver.onFocusEvent(entry(), wid: 2, now: 50, wasJustCreated: false, appIsActive: false)
        XCTAssertTrue(d.bump)
        XCTAssertEqual(d.entry, entry(wids: [1], focusBumped: true))
    }

    func testRaiseTailSwallowed() {
        // the TextEdit storm: after the focus 808, the remaining windows' raises must NOT re-front
        // (bumping each would reverse the app's MRU).
        let d = ActivationFocusResolver.onFocusEvent(entry(focusBumped: true), wid: 1, now: 50, wasJustCreated: false, appIsActive: true)
        XCTAssertFalse(d.bump)
        XCTAssertEqual(d.entry, entry(wids: [2], focusBumped: true))
    }

    func testSecondFocusOfSameWidBumps() {
        // a wid's SECOND 808 (its raise already consumed its snapshot entry) is a genuine re-focus.
        let d = ActivationFocusResolver.onFocusEvent(entry(wids: [2], focusBumped: true), wid: 1, now: 50, wasJustCreated: false, appIsActive: true)
        XCTAssertTrue(d.bump)
        XCTAssertEqual(d.entry, entry(wids: [2], focusBumped: true))
    }

    func testExpiredEntryPrunedAndNormalRulesApply() {
        // past `until` the activation is over: the entry is pruned and the plain isActive rule decides.
        let d = ActivationFocusResolver.onFocusEvent(entry(until: 10), wid: 1, now: 50, wasJustCreated: false, appIsActive: true)
        XCTAssertTrue(d.bump)
        XCTAssertNil(d.entry)
    }

    func testNoActivationActiveAppBumps() {
        let d = ActivationFocusResolver.onFocusEvent(nil, wid: 1, now: 50, wasJustCreated: false, appIsActive: true)
        XCTAssertTrue(d.bump)
        XCTAssertNil(d.entry)
    }

    func testNoActivationInactiveAppDropped() {
        // a background app re-focusing one of its windows: ignore to avoid MRU churn.
        let d = ActivationFocusResolver.onFocusEvent(nil, wid: 1, now: 50, wasJustCreated: false, appIsActive: false)
        XCTAssertFalse(d.bump)
    }

    func testJustCreatedAlwaysBumps() {
        // a brand-new window's first focus is honored even inactive and even mid-raise-tail (cmd-N spam).
        XCTAssertTrue(ActivationFocusResolver.onFocusEvent(nil, wid: 1, now: 50, wasJustCreated: true, appIsActive: false).bump)
        XCTAssertTrue(ActivationFocusResolver.onFocusEvent(entry(focusBumped: true), wid: 1, now: 50, wasJustCreated: true, appIsActive: false).bump)
    }

    // MARK: - onActivation

    func testAltTabInitiatedActivationBumpsKnownTarget() {
        // the switcher just focused this window — bump it directly, mark the focus spoken (raise tail
        // swallowed, AX backstop yields). Closes the zero-808 + stale-AX race for AltTab's own switches.
        let a = ActivationFocusResolver.onActivation(snapshotWids: [1, 2], until: 100, altTabTarget: 2)
        XCTAssertEqual(a.bumpWid, 2)
        XCTAssertEqual(a.entry, ActivationEntry(wids: [1, 2], until: 100, focusBumped: true))
    }

    func testExternalActivationWaitsForFocusSignal() {
        // no known target (Cmd+Tab, click): plain entry — the first 808 or the AX backstop decides.
        let a = ActivationFocusResolver.onActivation(snapshotWids: [1, 2], until: 100, altTabTarget: nil)
        XCTAssertNil(a.bumpWid)
        XCTAssertEqual(a.entry, ActivationEntry(wids: [1, 2], until: 100, focusBumped: false))
    }

    // MARK: - axBackstopShouldApply

    func testBackstopAppliesBeforeFocus808() {
        // no 808 arrived yet (some activations emit none): the AX read is the only signal — apply it.
        XCTAssertTrue(ActivationFocusResolver.axBackstopShouldApply(entry()))
        XCTAssertTrue(ActivationFocusResolver.axBackstopShouldApply(nil))
    }

    func testBackstopYieldsAfterFocus808() {
        // the AX read races the app's internal focus update and can return the PREVIOUS window (iTerm,
        // #5596) — once the activation's focus 808 has spoken, the backstop must yield.
        XCTAssertFalse(ActivationFocusResolver.axBackstopShouldApply(entry(focusBumped: true)))
    }
}
