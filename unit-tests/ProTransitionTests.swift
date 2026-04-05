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
        s.isInTimeWindow = true
        // welcome hasn't been shown yet — it takes priority over everything
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showWelcome)
    }

    // MARK: - Timed action: Day 12 Heads-Up

    func testDay12_headsUpShowsInTimeWindow() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.daysSinceTrialStart = 11 // Day 12
        s.isInTimeWindow = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay12HeadsUp)
    }

    func testDay12_headsUpSkippedOutsideTimeWindow() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.daysSinceTrialStart = 11
        s.isInTimeWindow = false
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
    }

    func testDay12_headsUpNotShownTwice() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.daysSinceTrialStart = 11
        s.isInTimeWindow = true
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay12HeadsUp)
    }

    func testDay12_tooEarly() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.daysSinceTrialStart = 10 // Day 11 — too early
        s.isInTimeWindow = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
    }

    // MARK: - Timed action: Day 15 Proactive

    func testDay15_proactiveShowsIfNoHardGate() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 14 // Day 15
        s.isInTimeWindow = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay15Proactive)
    }

    func testDay15_proactiveSkippedIfFullUpgradeAlreadyShown() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 14
        s.isInTimeWindow = true
        s.hasSeenFullUpgrade = true // hard-gate already fired → [C] was shown
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay15Proactive)
    }

    func testDay15_proactiveSkippedOutsideTimeWindow() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 14
        s.isInTimeWindow = false
        // should only refresh badge dot
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .refreshBadgeDot)
    }

    // MARK: - Timed action: Day 21 Reminder

    func testDay21_reminderShows() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.hasSeenProactiveDay15 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 20 // Day 21
        s.isInTimeWindow = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay21Reminder)
    }

    func testDay21_reminderNotShownTwice() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.hasSeenProactiveDay15 = true
        s.hasSeenDay21 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 20
        s.isInTimeWindow = true
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay21Reminder)
    }

    // MARK: - Timed action: Day 35 Final

    func testDay35_finalShows() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.hasSeenProactiveDay15 = true
        s.hasSeenDay21 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 34 // Day 35
        s.isInTimeWindow = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay35Final)
    }

    func testDay49_givesUp() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.hasSeenProactiveDay15 = true
        s.hasSeenDay21 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 48 // Day 49
        s.isInTimeWindow = true
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay35Final)
    }

    // MARK: - Timed action: Pro user

    func testProUser_noTimedActions() {
        var s = S.fresh()
        s.isPro = true
        s.isInTimeWindow = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
    }

    func testProUser_noTimedActionsEvenOnDay35() {
        var s = S.fresh()
        s.isPro = true
        s.daysSinceTrialStart = 34
        s.isInTimeWindow = true
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
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
        // In production, `isTrialActive` is set from `licenseState.isProAvailable`, which is true for both .trial and .pro.
        // A Pro user who activated on Day 5 still has daysSinceTrialStart advancing; on Days 13–14 we must NOT show the badge.
        var s = S.fresh()
        s.isPro = true
        s.isTrialActive = true
        s.daysSinceTrialStart = 12
        XCTAssertFalse(ProTransitionManagerTestable.shouldShowBadgeDot(s))
        s.daysSinceTrialStart = 13
        XCTAssertFalse(ProTransitionManagerTestable.shouldShowBadgeDot(s))
    }

    // MARK: - Scheduling completeness

    func testSchedulingComplete_forProUser() {
        var s = S.fresh()
        s.isPro = true
        XCTAssertTrue(ProTransitionManagerTestable.isSchedulingComplete(s))
    }

    func testSchedulingComplete_afterOptOutAndDay35() {
        var s = S.fresh()
        s.userOptedOut = true
        s.hasSeenDay35 = true
        XCTAssertTrue(ProTransitionManagerTestable.isSchedulingComplete(s))
    }

    func testSchedulingNotComplete_optedOutButDay35NotShown() {
        var s = S.fresh()
        s.userOptedOut = true
        s.hasSeenDay35 = false
        XCTAssertFalse(ProTransitionManagerTestable.isSchedulingComplete(s))
    }

    func testSchedulingComplete_allEventsShown() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.hasSeenProactiveDay15 = true
        s.hasSeenDay21 = true
        s.hasSeenDay35 = true
        XCTAssertTrue(ProTransitionManagerTestable.isSchedulingComplete(s))
    }

    func testSchedulingComplete_allEventsShown_fullUpgradeInsteadOfProactive() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.hasSeenFullUpgrade = true // hard-gate path instead of proactive
        s.hasSeenDay21 = true
        s.hasSeenDay35 = true
        XCTAssertTrue(ProTransitionManagerTestable.isSchedulingComplete(s))
    }

    // MARK: - Time window

    func testTimeWindow_10am() {
        XCTAssertTrue(ProTransitionManagerTestable.isInTimeWindow(hour: 10, minute: 0))
    }

    func testTimeWindow_1130am() {
        XCTAssertTrue(ProTransitionManagerTestable.isInTimeWindow(hour: 11, minute: 30))
    }

    func testTimeWindow_330pm() {
        XCTAssertTrue(ProTransitionManagerTestable.isInTimeWindow(hour: 15, minute: 30))
    }

    func testTimeWindow_4pm() {
        XCTAssertTrue(ProTransitionManagerTestable.isInTimeWindow(hour: 16, minute: 0))
    }

    func testTimeWindow_5pm() {
        XCTAssertTrue(ProTransitionManagerTestable.isInTimeWindow(hour: 17, minute: 0))
    }

    func testTimeWindow_9am_outside() {
        XCTAssertFalse(ProTransitionManagerTestable.isInTimeWindow(hour: 9, minute: 59))
    }

    func testTimeWindow_1131am_outside() {
        XCTAssertFalse(ProTransitionManagerTestable.isInTimeWindow(hour: 11, minute: 31))
    }

    func testTimeWindow_1pm_gap() {
        XCTAssertFalse(ProTransitionManagerTestable.isInTimeWindow(hour: 13, minute: 0))
    }

    func testTimeWindow_2pm_outside() {
        XCTAssertFalse(ProTransitionManagerTestable.isInTimeWindow(hour: 14, minute: 0))
    }

    func testTimeWindow_230pm_outside() {
        XCTAssertFalse(ProTransitionManagerTestable.isInTimeWindow(hour: 14, minute: 30))
    }

    func testTimeWindow_329pm_outside() {
        XCTAssertFalse(ProTransitionManagerTestable.isInTimeWindow(hour: 15, minute: 29))
    }

    func testTimeWindow_501pm_outside() {
        XCTAssertFalse(ProTransitionManagerTestable.isInTimeWindow(hour: 17, minute: 1))
    }

    func testTimeWindow_midnight() {
        XCTAssertFalse(ProTransitionManagerTestable.isInTimeWindow(hour: 0, minute: 0))
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

    func testSwitcherOpen_postExpirationNoopAfterTriggered() {
        var s = S.fresh()
        s.isTrialActive = false
        s.hasTriggeredPostExpirationSwitcher = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)
    }

    func testSwitcherOpen_postExpirationNoopAfterFreePassConsumed() {
        var s = S.fresh()
        s.isTrialActive = false
        s.freePassUsed = true // user pressed search shortcut first; don't double-fire [C]
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .noop)
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

        // Day 12 in time window: heads-up
        s.daysSinceTrialStart = 11
        s.isInTimeWindow = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay12HeadsUp)
        s.hasSeenDay12 = true

        // Days 13-14: badge dot shows
        s.daysSinceTrialStart = 12
        XCTAssertTrue(ProTransitionManagerTestable.shouldShowBadgeDot(s))

        // Day 15: trial expired, badge removed, proactive shows
        s.daysSinceTrialStart = 14
        s.isTrialActive = false
        XCTAssertFalse(ProTransitionManagerTestable.shouldShowBadgeDot(s))
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay15Proactive)
        s.hasSeenProactiveDay15 = true

        // Day 21: reminder
        s.daysSinceTrialStart = 20
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay21Reminder)
        s.hasSeenDay21 = true

        // Day 35: final
        s.daysSinceTrialStart = 34
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay35Final)
        s.hasSeenDay35 = true

        // After: scheduling complete
        XCTAssertTrue(ProTransitionManagerTestable.isSchedulingComplete(s))
    }

    // MARK: - Full flow: hard-gate user

    func testFullFlow_hardGateUser() {
        var s = S.fresh()

        // Day 1: welcome
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showWelcome)
        s.hasSeenWelcome = true

        // Day 12: heads-up
        s.daysSinceTrialStart = 11
        s.isInTimeWindow = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay12HeadsUp)
        s.hasSeenDay12 = true

        // Day 15: trial expired, user hits hard-gate before time window
        s.daysSinceTrialStart = 14
        s.isTrialActive = false
        s.isInTimeWindow = false
        // Hard-gate: free pass
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .freePass)
        s.freePassUsed = true
        // After free pass: [C] shows
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .showFullUpgrade)
        s.hasSeenFullUpgrade = true

        // Subsequent hard-gate: popover fires every time ([E])
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .showHardGatePopover)

        // Proactive [D] skipped because [C] was shown
        s.isInTimeWindow = true
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay15Proactive)
    }

    // MARK: - Full flow: purchase stops everything

    func testPurchase_stopsEverything() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.daysSinceTrialStart = 20
        s.isInTimeWindow = true
        s.isPro = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .none)
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .allow)
        XCTAssertTrue(ProTransitionManagerTestable.isSchedulingComplete(s))
    }

    // MARK: - Edge case: Day 35 close ⨉ vs opt-out

    func testDay35_closeDoesNotOptOut() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.hasSeenProactiveDay15 = true
        s.hasSeenDay21 = true
        s.hasSeenDay35 = true
        s.isTrialActive = false
        s.userOptedOut = false
        // [E] still fires on hard-gate
        s.freePassUsed = true
        s.hasSeenFullUpgrade = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .showHardGatePopover)
        // no more timed prompts
        s.isInTimeWindow = true
        s.daysSinceTrialStart = 40
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay35Final)
    }

    func testDay35_optOutStopsTimedButNotHardGate() {
        var s = S.fresh()
        s.hasSeenDay35 = true
        s.userOptedOut = true
        s.isTrialActive = false
        // scheduling is done
        XCTAssertTrue(ProTransitionManagerTestable.isSchedulingComplete(s))
        // but hard-gate popover still fires
        s.freePassUsed = true
        s.hasSeenFullUpgrade = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateHardGate(s), .showHardGatePopover)
    }

    // MARK: - Cross-event ordering (Day 21 vs Day 35)

    /// Spec edge case: "If Day 35 arrives first, skip Day 21."
    /// User inactive from Day 15 through Day 35; on Day 35 they should see [G], not [F].
    func testDay35_skipsDay21WhenDueSimultaneously() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.hasSeenProactiveDay15 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 34 // Day 35
        s.isInTimeWindow = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay35Final)
    }

    func testDay21_notShownOnOrAfterDay35() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.hasSeenProactiveDay15 = true
        s.hasSeenDay35 = true // [G] already dismissed; [F] must not retroactively fire
        s.isTrialActive = false
        s.daysSinceTrialStart = 34
        s.isInTimeWindow = true
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay21Reminder)
    }

    func testDay21_notShownPastDay49() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.hasSeenProactiveDay15 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 48 // Day 49 — past the Day 35 give-up cutoff
        s.isInTimeWindow = true
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay21Reminder)
    }

    // MARK: - Day 35 retry window

    func testDay35_retriesOnDay36() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.hasSeenProactiveDay15 = true
        s.hasSeenDay21 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 35 // Day 36
        s.isInTimeWindow = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay35Final)
    }

    func testDay35_retriesOnDay48() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.hasSeenProactiveDay15 = true
        s.hasSeenDay21 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 47 // Day 48 — last retry before give-up
        s.isInTimeWindow = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay35Final)
    }

    // MARK: - Day 49 give-up

    func testSchedulingComplete_pastDay49EvenWithoutDay35() {
        // User was inactive from Day 15 through Day 49 — [G] never shown.
        // Spec: "give up at Day 49". Scheduling must still be considered complete.
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 48
        XCTAssertTrue(ProTransitionManagerTestable.isSchedulingComplete(s))
    }

    // MARK: - Day 12 skip-entirely

    /// Spec: "Try 14:00–14:30, then skip entirely." [B] does not retry on Day 13+.
    func testDay12_skipsEntirelyOnDay13() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.daysSinceTrialStart = 12 // Day 13
        s.isInTimeWindow = true
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay12HeadsUp)
    }

    func testDay12_skipsEntirelyOnDay14() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.daysSinceTrialStart = 13 // Day 14
        s.isInTimeWindow = true
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay12HeadsUp)
    }

    // MARK: - Day 15 Proactive — direct coverage

    func testDay15_proactiveNotShownIfAlreadySeen() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.hasSeenProactiveDay15 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 14
        s.isInTimeWindow = true
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay15Proactive)
    }

    /// User inactive from Day 15 through Day 22 — [D] catches up before [F].
    func testDay15_proactiveShowsOnLaterDayIfStillNotShown() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay12 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 21 // Day 22
        s.isInTimeWindow = true
        XCTAssertEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay15Proactive)
    }

    // MARK: - Full flow: post-expiration switcher trigger user

    /// Engaged user (e.g. `.titles` configured pre-trial). On Day 15, opens AltTab → free-pass + [C] queued.
    func testFullFlow_postExpirationSwitcherTrigger() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay4Tour = true
        s.hasSeenDay12 = true
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
        s.isInTimeWindow = true
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay15Proactive)
    }

    /// Non-engaged user (e.g. only `.auto` size, or no Pro feature at all). On Day 15, opens AltTab
    /// → free-pass + [C] queued (with `.nonEngaged` reason). [D] is then suppressed.
    func testFullFlow_nonEngagedUser() {
        var s = S.fresh()
        s.hasSeenWelcome = true
        s.hasSeenDay4Tour = true
        s.hasSeenDay12 = true
        s.isTrialActive = false
        s.daysSinceTrialStart = 14

        // First switcher open: trigger free-pass even without remembered Pro prefs
        XCTAssertEqual(ProTransitionManagerTestable.evaluateSwitcherOpen(s), .triggerFreePass)
        // Simulate the manager's side effects after firing
        s.freePassUsed = true
        s.hasTriggeredPostExpirationSwitcher = true
        s.hasSeenFullUpgrade = true

        // [D] suppressed because [C] was shown
        s.isInTimeWindow = true
        XCTAssertNotEqual(ProTransitionManagerTestable.evaluateTimedAction(s), .showDay15Proactive)
    }
}
