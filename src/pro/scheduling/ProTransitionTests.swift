import XCTest

final class ProTransitionTests: XCTestCase {
    typealias S = ProTransitionManagerTestable.State
    typealias TimedAction = ProTransitionManagerTestable.TimedAction
    typealias HardGateAction = ProTransitionManagerTestable.HardGateAction
    typealias SwitcherOpenAction = ProTransitionManagerTestable.SwitcherOpenAction

    // MARK: - Timed action: Day 1 Welcome

    func testDay1_welcomeShows() {
        var s = S.fresh() // day 0, hasSeenWelcome = false
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showWelcome)
        // after seeing welcome, it doesn't show again
        s.hasSeenWelcome = true
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showWelcome)
    }

    func testDay1_welcomeBlocksAllOtherActions() {
        var s = S.fresh()
        s.daysSinceTrialStart = 35
        // welcome hasn't been shown yet — it takes priority over everything
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showWelcome)
    }

    // MARK: - Timed action: end of the trial

    func testLastTrialDays_noTimedPrompt() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        for day in 10...13 {
            s.daysSinceTrialStart = day
            XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
        }
    }

    // MARK: - Timed action: Day 15 Proactive

    func testDay15_waitsForSwitcherInsteadOfInterrupting() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 14 // Day 15
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
    }

    func testDay15_proactiveSkippedIfFullUpgradeAlreadyShown() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 14
        s.hasSeenFullUpgrade = true // hard-gate already fired → [C] was shown
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
    }

    // MARK: - Timed action: Day 35 Final

    func testDay35_notShownByClock() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenProactiveDay15 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 34 // Day 35
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
    }

    func testDay49_givesUp() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenProactiveDay15 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 48 // Day 49
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay35Final)
    }

    // MARK: - Timed action: Pro user

    func testProUser_noTimedActions() {
        var s = S.fresh()
        s.isPro = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
    }

    func testProUser_noTimedActionsEvenOnDay35() {
        var s = S.fresh()
        s.isPro = true
        s.daysSinceTrialStart = 34
        s.hasSeenWelcome = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
    }

    // MARK: - Hard-gate: trial active

    func testHardGate_allowedDuringTrial() {
        var s = S.fresh()
        s.isTrialActive = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .allow)
    }

    func testHardGate_allowedForProUser() {
        var s = S.fresh()
        s.isPro = true
        s.isTrialActive = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .allow)
    }

    // MARK: - Hard-gate: free pass

    func testHardGate_freePassOnFirstAttempt() {
        var s = S.fresh()
        s.isTrialActive = false
        s.freePassUsed = false
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .freePass)
    }

    func testHardGate_fullUpgradeAfterFreePass() {
        var s = S.fresh()
        s.isTrialActive = false
        s.freePassUsed = true
        s.hasSeenFullUpgrade = false
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .showFullUpgrade)
    }

    // MARK: - Hard-gate: popover fires on every post-[C] attempt

    func testHardGate_popoverAfterFullUpgrade() {
        var s = S.fresh()
        s.isTrialActive = false
        s.freePassUsed = true
        s.hasSeenFullUpgrade = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .showHardGatePopover)
    }

    // MARK: - Hard-gate: edge case — [D] shown but free pass not yet used

    func testHardGate_freePassStillAvailableAfterProactiveDay15() {
        var s = S.fresh()
        s.isTrialActive = false
        s.hasSeenProactiveDay15 = true // [D] was shown
        s.freePassUsed = false          // but user never triggered a hard-gate
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .freePass)
    }

    // MARK: - Hard-gate: opted out — [E] still fires

    func testHardGate_popoverStillFiresAfterOptOut() {
        var s = S.fresh()
        s.isTrialActive = false
        s.freePassUsed = true
        s.hasSeenFullUpgrade = true
        s.userOptedOut = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .showHardGatePopover)
    }

    // MARK: - Badge dot

    func testBadgeDot_showsOnDays13and14() {
        var s = S.fresh()
        s.isTrialActive = true
        s.daysSinceTrialStart = 12 // Day 13
        XCTAssertTrue(ProTransitionManagerTestable.shouldShowBadgeDot(s))
        s.daysSinceTrialStart = 13 // Day 14
        XCTAssertTrue(ProTransitionManagerTestable.shouldShowBadgeDot(s))
    }

    func testBadgeDot_notShownBeforeDay13() {
        var s = S.fresh()
        s.isTrialActive = true
        s.daysSinceTrialStart = 11 // Day 12
        XCTAssertFalse(ProTransitionManagerTestable.shouldShowBadgeDot(s))
    }

    func testBadgeDot_removedOnDay15() {
        var s = S.fresh()
        s.isTrialActive = false
        s.daysSinceTrialStart = 14 // Day 15
        XCTAssertFalse(ProTransitionManagerTestable.shouldShowBadgeDot(s))
    }

    func testBadgeDot_notShownForProUser() {
        // In production, `isTrialActive` is set from `licenseState.isProAvailable`, which is true for both
        // .trial and .pro.
        // A Pro user who activated on Day 5 still has daysSinceTrialStart advancing; on Days 13–14 we must
        // NOT show the badge.
        var s = S.fresh()
        s.isPro = true
        s.isTrialActive = true
        s.daysSinceTrialStart = 12
        XCTAssertFalse(ProTransitionManagerTestable.shouldShowBadgeDot(s))
        s.daysSinceTrialStart = 13
        XCTAssertFalse(ProTransitionManagerTestable.shouldShowBadgeDot(s))
    }

    /// An app left running from Day 12 must wake at the start of Day 13 to draw the badge, then at the trial's end to remove it.
    func testNextTrialDeadline_wakesForTheBadgeDaysThenForTheTrialsEnd() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        func deadline(atDay day: Double) -> Date? {
            ProTransitionManagerTestable.nextTrialDeadline(after: start.addingTimeInterval(day * 86400), trialStart: start)
        }
        let day13 = start.addingTimeInterval(12 * 86400 + 1), day15 = start.addingTimeInterval(14 * 86400 + 1)
        XCTAssertEqual(deadline(atDay: 0), day13)
        XCTAssertEqual(deadline(atDay: 11.99), day13)
        XCTAssertEqual(deadline(atDay: 12.5), day15)
        XCTAssertEqual(deadline(atDay: 13.99), day15)
        XCTAssertNil(deadline(atDay: 14.5))
    }

    // MARK: - Switcher open: Day 4 Pro tour

    func testSwitcherOpen_day4TourFiresFirstTime() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.daysSinceTrialStart = 3 // Day 4
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .showDay4Tour)
    }

    func testSwitcherOpen_day4TourNotShownTwice() {
        var s = S.fresh()
        s.daysSinceTrialStart = 3
        s.hasSeenDay4Tour = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)
    }

    func testSwitcherOpen_day4TourSkippedOnDay3() {
        var s = S.fresh()
        s.daysSinceTrialStart = 2 // Day 3 — too early
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)
    }

    func testSwitcherOpen_day4TourSkippedOnDay5() {
        var s = S.fresh()
        s.daysSinceTrialStart = 4 // Day 5 — too late, no retry
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)
    }

    func testSwitcherOpen_day4TourSkippedForProUser() {
        var s = S.fresh()
        s.isPro = true
        s.daysSinceTrialStart = 3
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)
    }

    // MARK: - Switcher open: post-expiration trigger

    func testSwitcherOpen_postExpirationFires() {
        // Fires for every post-expiration user (engaged or not). The pure decision no longer
        // discriminates on remembered Pro prefs — the manager builds the `HardGateReason` payload
        // from the persisted `remembered*` indices, which collapses to `.nonEngaged` when nil.
        var s = S.fresh()
        s.isTrialActive = false
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .triggerFreePass)
    }

    func testSwitcherOpen_retriesAnnouncementAfterCancelledPresentation() {
        var s = S.fresh()
        s.isTrialActive = false
        s.hasTriggeredPostExpirationSwitcher = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .showExpiration)
        s.hasSeenFullUpgrade = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)
    }

    func testSwitcherOpen_freePassDoesNotCountAsDeliveredAnnouncement() {
        var s = S.fresh()
        s.isTrialActive = false
        s.freePassUsed = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .showExpiration)
    }

    func testSwitcherOpen_postExpirationNoopDuringTrial() {
        var s = S.fresh()
        s.isTrialActive = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)
    }

    func testSwitcherOpen_proUserNoop() {
        var s = S.fresh()
        s.isPro = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)
    }

    // MARK: - Full flow: degradable-only user (never triggers hard-gate)

    func testFullFlow_degradableOnly() {
        var s = S.fresh()

        // Day 1: welcome
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showWelcome)
        s.hasSeenWelcome = true

        // Days 2-11: silent trial, nothing happens
        s.daysSinceTrialStart = 5
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)

        // Day 12: still silent
        s.daysSinceTrialStart = 11
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)

        // Days 13-14: badge dot shows
        s.daysSinceTrialStart = 12
        XCTAssertTrue(ProTransitionManagerTestable.shouldShowBadgeDot(s))

        // Day 15: trial expired, badge removed, proactive shows
        s.daysSinceTrialStart = 14
        s.isTrialActive = false
        XCTAssertFalse(ProTransitionManagerTestable.shouldShowBadgeDot(s))
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
        s.hasSeenProactiveDay15 = true

        // Day 21: no reminder
        s.daysSinceTrialStart = 20
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)

        // Day 35: final
        s.daysSinceTrialStart = 34
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
        s.hasSeenDay35 = true
    }

    // MARK: - Full flow: hard-gate user

    func testFullFlow_hardGateUser() {
        var s = S.fresh()

        // Day 1: welcome
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showWelcome)
        s.hasSeenWelcome = true

        // Day 15: trial expired, user hits hard-gate
        s.daysSinceTrialStart = 14
        s.isTrialActive = false
        // Hard-gate: free pass
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .freePass)
        s.freePassUsed = true
        // After free pass: [C] shows
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .showFullUpgrade)
        s.hasSeenFullUpgrade = true

        // Subsequent hard-gate: popover fires every time ([E])
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .showHardGatePopover)

        // Proactive [D] skipped because [C] was shown
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
    }

    // MARK: - Full flow: purchase stops everything

    func testPurchase_stopsEverything() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.daysSinceTrialStart = 20
        s.isPro = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .allow)
    }

    // MARK: - Edge case: Day 35 close ⨉ vs opt-out

    func testDay35_closeDoesNotOptOut() {
        var s = eligibleDay35State()
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .showDay35Final)
        s.hasSeenDay35 = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .showHardGatePopover)
    }

    func testDay35_optOutStopsReminderButNotHardGate() {
        var s = eligibleDay35State()
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .showDay35Final)
        s.userOptedOut = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .showHardGatePopover)
    }

    // MARK: - Day 35 retry window

    func testDay35_doesNotRetryOnDay36() {
        var s = eligibleDay35State()
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .showDay35Final)
        s.daysSinceTrialStart = 35
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)
    }

    func testDay35_doesNotRetryOnDay48() {
        var s = eligibleDay35State()
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .showDay35Final)
        s.daysSinceTrialStart = 47
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)
    }

    private func eligibleDay35State() -> S {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenFullUpgrade = true
        s.freePassUsed = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 34
        s.recentIntent = true
        return s
    }

    // MARK: - Day 15 Proactive — direct coverage

    func testDay15_proactiveNotShownIfAlreadySeen() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenProactiveDay15 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 14
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
    }

    /// User inactive from Day 15 through Day 22: nothing catches up on a timer.
    func testDay15_noTimedCatchUp() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 21 // Day 22
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
    }

    // MARK: - Full flow: post-expiration switcher trigger user

    /// Engaged user (e.g. `.titles` configured pre-trial). On Day 15, opens AltTab → free-pass + [C] queued.
    func testFullFlow_postExpirationSwitcherTrigger() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay4Tour = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 14 // Day 15

        // First switcher open: trigger free-pass
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .triggerFreePass)
        // Simulate the manager's side effects after firing
        s.freePassUsed = true
        s.hasTriggeredPostExpirationSwitcher = true
        s.hasSeenFullUpgrade = true // [C] was shown 1s after dismiss

        // Second switcher open: noop (one-shot)
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)

        // Subsequent search shortcut press: [E] popover (post-[C], not free-pass again)
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .showHardGatePopover)

        // Proactive [D] suppressed because [C] was shown
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
    }

    /// Non-engaged user (e.g. only `.auto` size, or no Pro feature at all). On Day 15, opens AltTab
    /// → free-pass + [C] queued (with `.nonEngaged` reason). [D] is then suppressed.
    func testFullFlow_nonEngagedUser() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay4Tour = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 14

        // First switcher open: trigger free-pass even without remembered Pro prefs
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .triggerFreePass)
        // Simulate the manager's side effects after firing
        s.freePassUsed = true
        s.hasTriggeredPostExpirationSwitcher = true
        s.hasSeenFullUpgrade = true

        // [D] suppressed because [C] was shown
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
    }

    // MARK: - Checkout origin

    func testCheckoutUrl_carriesOriginAndTrialDayAsVia() {
        let via = { (day: Int?) in Endpoints.checkoutUrl(from: .day35Final, trialDay: day, website: "https://alt-tab.app").absoluteString }
        XCTAssertEqual(via(1), "https://alt-tab.app/pricing?via=1-a6")
        XCTAssertEqual(via(35), "https://alt-tab.app/pricing?via=35-a6")
        XCTAssertEqual(via(100), "https://alt-tab.app/pricing?via=100-a6")
        XCTAssertEqual(via(nil), "https://alt-tab.app/pricing?via=a6")
    }

    // MARK: - Space changes

    /// Focusing a window on another Space moves there during the dismissal delay; the queued prompt follows.
    func testSpaceChangeFromTheSwitchersOwnFocusKeepsTheQueuedPrompt() {
        XCTAssertFalse(ProTransitionManagerTestable.spaceChangeCancelsPendingPrompt(switcherIsShown: false, awaitingDismissalDelay: true))
    }

    func testSpaceChangeWhileTheSwitcherIsOpenStillCancels() {
        XCTAssertTrue(ProTransitionManagerTestable.spaceChangeCancelsPendingPrompt(switcherIsShown: true, awaitingDismissalDelay: false))
        XCTAssertTrue(ProTransitionManagerTestable.spaceChangeCancelsPendingPrompt(switcherIsShown: true, awaitingDismissalDelay: true))
        XCTAssertTrue(ProTransitionManagerTestable.spaceChangeCancelsPendingPrompt(switcherIsShown: false, awaitingDismissalDelay: false))
    }

    func testCheckoutOrigin_codesMatchTheWebsiteList() {
        XCTAssertEqual(CheckoutOrigin.allCases.map(\.rawValue), ["a2", "a4", "a6", "a7", "a8"])
    }
}

final class ProJourneyTests: XCTestCase {
    func testOneExploratorySearchDoesNotOutrankAdoptedStyleOrRepeatedShortcuts() {
        var evidence = ProJourneyEvidence(searches: 1, extraShortcuts: 20, adoptedStyle: 2, usedAuto: true)
        XCTAssertEqual(evidence.preferredFeature, .styles)
        evidence.adoptedStyle = nil
        XCTAssertEqual(evidence.preferredFeature, .shortcuts)
        evidence.extraShortcuts = 0
        XCTAssertEqual(evidence.preferredFeature, .autoSize)
    }

    func testRepeatedActionsUseCountsWithDeterministicTies() {
        var evidence = ProJourneyEvidence(searches: 2, extraShortcuts: 20, usedAuto: true)
        XCTAssertEqual(evidence.preferredFeature, .shortcuts)
        evidence.searches = 21
        XCTAssertEqual(evidence.preferredFeature, .search)
        evidence.extraShortcuts = 21
        XCTAssertEqual(evidence.preferredFeature, .search)
        evidence.searches = 1
        evidence.extraShortcuts = 0
        XCTAssertEqual(evidence.preferredFeature, .autoSize)
        evidence.usedAuto = false
        XCTAssertEqual(evidence.preferredFeature, .search)
        XCTAssertEqual(evidence.searches, 1, "ranking does not alter truthful usage counts")
    }

    func testExplicitRequestAndRecentIntentOverrideEveryEvidenceFallback() {
        let evidence = ProJourneyEvidence(searches: 400, extraShortcuts: 500, adoptedStyle: 2, usedAuto: true)
        for feature in ProJourneyFeature.allCases {
            XCTAssertEqual(evidence.openingFeature(requested: feature), feature)
        }
        XCTAssertEqual(evidence.openingFeature(requested: nil), .styles)
    }

    func testUnknownAndZeroHistoryUseGenericFallbackWithoutInventingUse() {
        let unknown = ProJourneyEvidence()
        let zero = ProJourneyEvidence(searches: 0, extraShortcuts: 0, usedAuto: false)
        XCTAssertEqual(unknown.preferredFeature, .autoSize)
        XCTAssertEqual(zero.preferredFeature, .autoSize)
        XCTAssertNil(unknown.searches)
        XCTAssertEqual(zero.searches, 0)
        XCTAssertFalse(unknown.used(.autoSize))
        XCTAssertFalse(zero.used(.autoSize))
    }

    func testPreTrialNeverMarketsDowngradesOrConsumesAFreePass() {
        var state = ProTransitionManagerTestable.State.fresh()
        state.isAwaitingTrial = true
        state.isTrialActive = false
        for day in [0, 3, 12, 14, 34, 100] {
            state.daysSinceTrialStart = day
            state.recentIntent = true
            XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(state), .none)
            XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .noop)
            XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(state), .unavailable)
            XCTAssertFalse(ProTransitionManagerTestable.shouldShowBadgeDot(state))
        }
    }

    /// Every tab reflects the trial on its own, not only the tab opened first.
    func testEachTabClaimsTrialUseOnlyWhenItHappened() {
        let unused = ProJourneyEvidence(searches: 0, extraShortcuts: nil, adoptedStyle: nil, usedAuto: false)
        XCTAssertTrue(ProJourneyFeature.allCases.allSatisfy { !unused.used($0) })
        let used = ProJourneyEvidence(searches: 3, extraShortcuts: 5, adoptedStyle: 1, usedAuto: true)
        XCTAssertTrue(ProJourneyFeature.allCases.allSatisfy { used.used($0) })
        let searchOnly = ProJourneyEvidence(searches: 3, extraShortcuts: 0, adoptedStyle: nil, usedAuto: nil)
        XCTAssertEqual(ProJourneyFeature.allCases.filter { searchOnly.used($0) }, [.search])
    }

    func testTrialCountsExcludeBeforeTrialAndAfterExpiryAndPreserveUnknown() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = start.addingTimeInterval(14 * 86400)
        let timestamps = [999, 1000, 1001, Int(end.timeIntervalSince1970) - 1, Int(end.timeIntervalSince1970)]
        XCTAssertEqual(ProJourneyEvidence.count(timestamps, start: start, end: end, now: end), 3)
        XCTAssertEqual(ProJourneyEvidence.count([], start: start, end: end, now: end), 0)
        XCTAssertEqual(ProJourneyEvidence.count(timestamps, start: start, end: end, now: start), 1)
        XCTAssertNil(ProJourneyEvidence.count(nil, start: start, end: end, now: end))
        XCTAssertNil(ProJourneyEvidence.count(timestamps, start: nil, end: end, now: end))
        XCTAssertNil(ProJourneyEvidence.count(
            timestamps,
            start: start,
            end: end,
            now: end.addingTimeInterval(365 * 86400)
        ))
    }

    func testRecentIntentHasBoundedAgeAndNoFutureOrUnknownDates() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(ProJourneyEvidence.hasRecentIntent(at: now.addingTimeInterval(-7 * 86400), now: now))
        XCTAssertFalse(ProJourneyEvidence.hasRecentIntent(
            at: now.addingTimeInterval(-7 * 86400 - 1),
            now: now
        ))
        XCTAssertFalse(ProJourneyEvidence.hasRecentIntent(at: now.addingTimeInterval(1), now: now))
        XCTAssertFalse(ProJourneyEvidence.hasRecentIntent(at: nil, now: now))
    }

    func testDay35RequiresRecentIntentNoOtherMessageAndOnlyExactDay() {
        var state = ProTransitionManagerTestable.State.fresh()
        state.isTrialActive = false
        state.hasSeenWelcome = true
        state.hasSeenFullUpgrade = true
        state.freePassUsed = true
        state.daysSinceTrialStart = 34
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .noop)
        state.recentIntent = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .showDay35Final)
        state.messageShownToday = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .noop)
        state.messageShownToday = false
        state.userOptedOut = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .noop)
        state.userOptedOut = false
        for day in 35 ... 48 {
            state.daysSinceTrialStart = day
            XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .noop)
        }
        state.daysSinceTrialStart = 34
        state.hasSeenDay35 = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .noop)
    }

    func testDay4SkipsAdoptedStyleOptOutAndOtherMessages() {
        var state = ProTransitionManagerTestable.State.fresh()
        state.daysSinceTrialStart = 3
        state.usesThumbnails = false
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .noop)
        state.usesThumbnails = true
        state.messageShownToday = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .noop)
        state.messageShownToday = false
        state.userOptedOut = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .noop)
    }

    func testCaptureAdoptsOnlyAProStyleAndRecordsAutoSize() {
        XCTAssertTrue(ProJourneyEvidence.capture(styleIndex: 0, autoSize: false, previouslyDowngraded: false) == (nil, false))
        XCTAssertTrue(ProJourneyEvidence.capture(styleIndex: 1, autoSize: true, previouslyDowngraded: false) == (1, true))
        XCTAssertTrue(ProJourneyEvidence.capture(styleIndex: 2, autoSize: false, previouslyDowngraded: false) == (2, false))
    }

    /// An earlier version's downgrade lost the overrides: no claim beats a wrong one.
    func testCaptureClaimsNothingForAnInstallDowngradedBefore() {
        XCTAssertTrue(ProJourneyEvidence.capture(styleIndex: 2, autoSize: true, previouslyDowngraded: true) == (nil, nil))
    }

    func testCaptureFallsBackToTheFirstShortcutWhenTheLastOneIsGone() {
        XCTAssertEqual(ProJourneyEvidence.captureShortcutIndex(2, shortcutCount: 3), 2)
        XCTAssertEqual(ProJourneyEvidence.captureShortcutIndex(3, shortcutCount: 3), 0)
        XCTAssertEqual(ProJourneyEvidence.captureShortcutIndex(-1, shortcutCount: 3), 0)
    }

    func testOneMessagePerCalendarDayAndAFutureDateCounts() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 12, hour: 10))!
        XCTAssertFalse(ProJourneyEvidence.isMessageToday(nil, now: now, calendar: calendar))
        XCTAssertTrue(ProJourneyEvidence.isMessageToday(now.addingTimeInterval(-9 * 3600), now: now, calendar: calendar))
        XCTAssertFalse(ProJourneyEvidence.isMessageToday(now.addingTimeInterval(-11 * 3600), now: now, calendar: calendar))
        XCTAssertTrue(ProJourneyEvidence.isMessageToday(now.addingTimeInterval(86400 * 3), now: now, calendar: calendar))
    }

    /// Blocked by a fullscreen app or display sleep, the tour waits for a later session, on Day 4 or Day 5.
    func testDay4TourBlockedAtPresentationRetriesLaterOnDay4Or5() {
        var state = ProTransitionManagerTestable.State.fresh()
        state.hasSeenDay4Tour = true
        state.day4TourDeferred = true
        for day in [3, 4] {
            state.daysSinceTrialStart = day
            XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .showDay4Tour)
        }
        state.daysSinceTrialStart = 5
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .noop)
    }

    /// The retry still yields to an adopted style, an opt-out and another message that day.
    func testDeferredDay4TourKeepsItsOtherConditions() {
        var state = ProTransitionManagerTestable.State.fresh()
        state.daysSinceTrialStart = 4
        state.hasSeenDay4Tour = true
        state.day4TourDeferred = true
        state.usesThumbnails = false
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .noop)
        state.usesThumbnails = true
        state.messageShownToday = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .noop)
    }

    /// A user who did not switch windows on Day 4 is not chased on Day 5.
    func testDay4TourHasNoCatchUpForAnAbsentUser() {
        var state = ProTransitionManagerTestable.State.fresh()
        state.daysSinceTrialStart = 4
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(state), .noop)
    }

    func testLegacyExpirationAnnouncementDoesNotAnnounceTwiceAndEveryBlockedAttemptResponds() {
        var state = ProTransitionManagerTestable.State.fresh()
        state.isTrialActive = false
        state.freePassUsed = true
        state.hasSeenProactiveDay15 = true
        for _ in 0 ..< 10 {
            XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(state), .showHardGatePopover)
        }
    }
}
