import XCTest

/// Pins the pure timing decisions of the AX scheduling layer — coalescing (leading + trailing + drop) and
/// retry backoff/give-up — deterministically, with no clocks or queues. The owners (`Throttler`,
/// `ThrottlerWithKey`, `AXCallScheduler`) branch on these, so keeping them green keeps that behavior fixed.
final class SchedulingPolicyTests: XCTestCase {

    // MARK: - A. ThrottleDecision

    func testThrottleFirstCallRunsNow() {
        XCTAssertEqual(ThrottleDecision.decide(lastFireNs: nil, nowNs: 1000, delayNs: 200, tailScheduled: false), .runNow)
    }

    func testThrottleAfterWindowRunsNow() {
        XCTAssertEqual(ThrottleDecision.decide(lastFireNs: 1000, nowNs: 1200, delayNs: 200, tailScheduled: false), .runNow) // elapsed == delay
        XCTAssertEqual(ThrottleDecision.decide(lastFireNs: 1000, nowNs: 5000, delayNs: 200, tailScheduled: true), .runNow)  // well past, even with a stale tail flag
    }

    func testThrottleWithinWindowSchedulesTail() {
        XCTAssertEqual(ThrottleDecision.decide(lastFireNs: 1000, nowNs: 1050, delayNs: 200, tailScheduled: false), .scheduleTail(remainingNs: 150))
    }

    func testThrottleWithinWindowWithPendingTailCoalesces() {
        XCTAssertEqual(ThrottleDecision.decide(lastFireNs: 1000, nowNs: 1050, delayNs: 200, tailScheduled: true), .coalesce)
    }

    func testThrottleClockGoingBackwardsRunsNow() {
        XCTAssertEqual(ThrottleDecision.decide(lastFireNs: 1000, nowNs: 500, delayNs: 200, tailScheduled: false), .runNow)
    }

    func testThrottleBurstCoalescesAfterOneTail() {
        // a live drag: leading call runs; the first follower schedules the single trailing run; the rest coalesce
        XCTAssertEqual(ThrottleDecision.decide(lastFireNs: nil, nowNs: 0, delayNs: 200, tailScheduled: false), .runNow)
        XCTAssertEqual(ThrottleDecision.decide(lastFireNs: 0, nowNs: 10, delayNs: 200, tailScheduled: false), .scheduleTail(remainingNs: 190))
        XCTAssertEqual(ThrottleDecision.decide(lastFireNs: 0, nowNs: 20, delayNs: 200, tailScheduled: true), .coalesce)
        XCTAssertEqual(ThrottleDecision.decide(lastFireNs: 0, nowNs: 30, delayNs: 200, tailScheduled: true), .coalesce)
    }

    // MARK: - B. RetryPolicy

    func testRetryBackoffSequence() {
        XCTAssertEqual(RetryPolicy.backoffDelayNs(retryCount: 0), 200_000_000)
        XCTAssertEqual(RetryPolicy.backoffDelayNs(retryCount: 1), 1_000_000_000)
        XCTAssertEqual(RetryPolicy.backoffDelayNs(retryCount: 2), 2_000_000_000)
        XCTAssertEqual(RetryPolicy.backoffDelayNs(retryCount: 3), 5_000_000_000)
        XCTAssertEqual(RetryPolicy.backoffDelayNs(retryCount: 4), 5_000_000_000)
    }

    func testRetryBackoffClampsAndFloors() {
        XCTAssertEqual(RetryPolicy.backoffDelayNs(retryCount: 999), 5_000_000_000) // clamp to last step
        XCTAssertEqual(RetryPolicy.backoffDelayNs(retryCount: -1), 200_000_000)    // floor to first step
    }

    func testRetryGivesUpAtThreshold() {
        XCTAssertTrue(RetryPolicy.shouldGiveUp(elapsedSinceStartNs: 60_000_000_000))
        XCTAssertTrue(RetryPolicy.shouldGiveUp(elapsedSinceStartNs: 120_000_000_000))
    }

    func testRetryDoesNotGiveUpEarly() {
        XCTAssertFalse(RetryPolicy.shouldGiveUp(elapsedSinceStartNs: 0))
        XCTAssertFalse(RetryPolicy.shouldGiveUp(elapsedSinceStartNs: 59_999_999_999))
    }

    // MARK: - C. InactiveTabScanPolicy

    /// The bug, as a rule: an attempt that adopted NOTHING must be retryable. The situation used to be recorded
    /// before the scan ran and then refused forever, so one fruitless attempt (the app's AX tree not ready yet
    /// at launch) permanently gave up — measured live as 82 tab reads naming untracked tabs and zero
    /// adoptions, against 57 in a run whose first attempt happened to land.
    func testFruitlessScanIsRetriedOnTheSameSituation() {
        let situation = "lwouis\u{1}lwouis|1"
        var attempts = 0
        var recorded: String? = nil
        for _ in 0..<InactiveTabScanPolicy.maxAttemptsPerSituation {
            XCTAssertTrue(InactiveTabScanPolicy.shouldScan(recordedSituation: recorded, attempts: attempts,
                                                           situation: situation))
            attempts = InactiveTabScanPolicy.attemptsAfterScan(previousAttempts: attempts,
                sameSituation: recorded == situation, adopted: 0)
            recorded = situation
        }
    }

    /// ...but BOUNDED, because a fruitless scan is ordinary rather than an error: Finder destroys a
    /// backgrounded tab's window, so its AXTabGroup routinely names tabs with no window to find and no number
    /// of walks will resolve them. Past the cap the app's tree is left alone until something changes.
    func testFruitlessScansStopAtTheCap() {
        let situation = "lwouis|1"
        XCTAssertFalse(InactiveTabScanPolicy.shouldScan(recordedSituation: situation,
            attempts: InactiveTabScanPolicy.maxAttemptsPerSituation, situation: situation))
    }

    /// Any change to the app's window set — a tab adopted, opened or closed — moves the titles or the count and
    /// makes the app eligible again, however exhausted the previous situation was.
    func testANewSituationIsAlwaysEligible() {
        XCTAssertTrue(InactiveTabScanPolicy.shouldScan(recordedSituation: "lwouis|1", attempts: 99,
                                                       situation: "lwouis\u{1}lwouis|2"))
        XCTAssertTrue(InactiveTabScanPolicy.shouldScan(recordedSituation: nil, attempts: 0, situation: "~|4"))
    }

    /// **Where the sweep begins is what decided whether it found anything.** The scan walks AXUIElementIDs one
    /// by one under a wall-clock budget, so it covers a WINDOW of the id space and never the space itself.
    /// Starting at 0 aimed that window at wherever the app was hours ago: measured live 2026-07-30, three
    /// attempts covered ids 0..<30000 and adopted nothing, while Finder's window elements sat at ~31000 —
    /// stopping just short every time. Anchoring a margin below a window we already track finds them in one.
    func testTheSweepStartsNearTheAppsOwnElementsNotAtZero() {
        XCTAssertEqual(InactiveTabScanPolicy.scanStart(cursor: nil, lowestKnownId: 31130), 27130)
        // ...and low anchors floor at 0 rather than wrapping around the UInt64 space
        XCTAssertEqual(InactiveTabScanPolicy.scanStart(cursor: nil, lowestKnownId: 500), 0)
        // nothing tracked yet ⇒ nothing to anchor on
        XCTAssertEqual(InactiveTabScanPolicy.scanStart(cursor: nil, lowestKnownId: nil), 0)
    }

    /// A retry RESUMES: the cursor from a fruitless attempt wins over the anchor, so successive attempts make
    /// progress up the id space instead of re-walking the ids that already failed.
    func testARetryResumesWhereTheLastSweepStopped() {
        XCTAssertEqual(InactiveTabScanPolicy.scanStart(cursor: 18585, lowestKnownId: 31130), 18585)
    }

    /// A scan that adopted something spends no budget: it made progress, and the situation it leaves is new
    /// anyway (the window count moved).
    func testASuccessfulScanSpendsNoBudget() {
        XCTAssertEqual(InactiveTabScanPolicy.attemptsAfterScan(previousAttempts: 2, sameSituation: true, adopted: 3), 0)
        XCTAssertEqual(InactiveTabScanPolicy.attemptsAfterScan(previousAttempts: 2, sameSituation: true, adopted: 0), 3)
        // a fresh situation restarts the budget rather than inheriting the previous one's
        XCTAssertEqual(InactiveTabScanPolicy.attemptsAfterScan(previousAttempts: 2, sameSituation: false, adopted: 0), 1)
    }

    /// A candidate the sweep found and the caller handed back — because it is parked on ANOTHER window of the
    /// same app, so it is that window's tab — rewinds the cursor onto itself instead of being stepped over.
    /// Two tab groups of one app used to be permanently uncrossable this way: each requester's sweep stopped
    /// on the other group's tabs, dropped them, and moved the shared cursor past them, so the requester that
    /// owned them started above them next time (measured live: six tabs collapsing to two).
    func testACandidateLeftForAnotherWindowIsNotSteppedOver() {
        XCTAssertEqual(InactiveTabScanPolicy.nextCursor(adopted: 0, deferredId: 21446, sweptTo: 21267), 21267)
        XCTAssertEqual(InactiveTabScanPolicy.nextCursor(adopted: 0, deferredId: 21200, sweptTo: 21267), 21200)
        // nothing deferred ⇒ resume where the sweep stopped, as before
        XCTAssertEqual(InactiveTabScanPolicy.nextCursor(adopted: 0, deferredId: nil, sweptTo: 21267), 21267)
        // an adoption restarts from the anchor: the window set moved, so the band to sweep did too
        XCTAssertEqual(InactiveTabScanPolicy.nextCursor(adopted: 2, deferredId: 21200, sweptTo: 21267), 0)
    }

    // MARK: - D. SurfaceAcquisitionPolicy

    /// a surface with no failure on record is swept, as before
    func testAFreshSurfaceIsAlwaysAttempted() {
        XCTAssertTrue(SurfaceAcquisitionPolicy.shouldAttempt(recordedSituation: nil, attempts: 0, situation: 7))
    }

    /// a failure is not a verdict: the situation keeps its attempts, because an app still building its
    /// accessibility tree at launch fails transiently
    func testAFailedSurfaceIsRetriedWithinTheBudget() {
        for spent in 0..<SurfaceAcquisitionPolicy.maxAttemptsPerSituation {
            XCTAssertTrue(SurfaceAcquisitionPolicy.shouldAttempt(recordedSituation: 7, attempts: spent, situation: 7))
        }
    }

    /// past the cap the sweep leaves it out of subsequent process batches
    func testAFailedSurfaceStopsAtTheCap() {
        XCTAssertFalse(SurfaceAcquisitionPolicy.shouldAttempt(recordedSituation: 7,
            attempts: SurfaceAcquisitionPolicy.maxAttemptsPerSituation, situation: 7))
    }

    /// the app gaining or losing a window is what plausibly makes a previously-unreachable element
    /// reachable, so it restarts the budget however exhausted the last situation was
    func testANewWindowSetMakesTheSurfaceEligibleAgain() {
        XCTAssertTrue(SurfaceAcquisitionPolicy.shouldAttempt(recordedSituation: 7, attempts: 99, situation: 8))
    }

    /// the counter is per situation, not cumulative, so a long-lived app that churns windows never
    /// accumulates its way into a permanent refusal
    func testAttemptsResetOnANewSituation() {
        XCTAssertEqual(SurfaceAcquisitionPolicy.attemptsAfterFailure(previousAttempts: 2, sameSituation: true), 3)
        XCTAssertEqual(SurfaceAcquisitionPolicy.attemptsAfterFailure(previousAttempts: 2, sameSituation: false), 1)
    }

    /// a busy app is still inside its budget, so nothing that waits on the give-up verdict may act yet
    func testGivingUpDoesNotHappenWhileTriesRemain() {
        for spent in 0..<SurfaceAcquisitionPolicy.maxAttemptsPerSituation {
            XCTAssertFalse(SurfaceAcquisitionPolicy.hasGivenUp(attempts: spent))
        }
    }

    /// giving up is the same moment the sweep stops paying, never a later one: a caller must not act on a
    /// verdict the sweep has not reached
    func testGivingUpIsExactlyWhereTheSweepStops() {
        XCTAssertTrue(SurfaceAcquisitionPolicy.hasGivenUp(attempts: SurfaceAcquisitionPolicy.maxAttemptsPerSituation))
        XCTAssertFalse(SurfaceAcquisitionPolicy.shouldAttempt(recordedSituation: 7,
            attempts: SurfaceAcquisitionPolicy.maxAttemptsPerSituation, situation: 7))
    }

    /// a new window set restarts the budget, so the app is not permanently condemned by one bad arrangement:
    /// `hasGivenUp` reads the count the caller just stored, and that count resets with the situation
    func testGivingUpIsUndoneByANewSituation() {
        let afterReset = SurfaceAcquisitionPolicy.attemptsAfterFailure(previousAttempts: 99, sameSituation: false)
        XCTAssertFalse(SurfaceAcquisitionPolicy.hasGivenUp(attempts: afterReset))
    }

    // MARK: - E. AX traversal bounds

    func testTraversalReachesHighIdsWhileTimeRemains() {
        var elapsed = 0.0
        let target: UInt64 = 30_000
        var found: UInt64?
        let next = AxTraversalPolicy.scan(from: 0, elapsedMs: { elapsed }, candidate: { id -> UInt64? in
            elapsed += 0.001
            return id == target ? id : nil
        }) { id, mayStart in
            guard mayStart() else { return false }
            found = id
            return true
        }
        XCTAssertEqual(found, target)
        XCTAssertEqual(next, target + 1)
        XCTAssertLessThan(elapsed, AxTraversalPolicy.budgetMs)
    }

    func testTraversalResumesWithoutGapsAfterTheDeadline() {
        var visited = [UInt64]()
        var elapsed = 0.0
        let next = AxTraversalPolicy.scan(from: 0, elapsedMs: { elapsed }, candidate: { $0 }) { id, mayStart in
            guard mayStart() else { return false }
            visited.append(id)
            elapsed += 1
            return false
        }
        XCTAssertEqual(visited.count, Int(AxTraversalPolicy.budgetMs))
        XCTAssertTrue(visited.enumerated().allSatisfy { UInt64($0.offset) == $0.element })
        XCTAssertEqual(next, UInt64(visited.count))
        let end = AxTraversalPolicy.scan(from: next, elapsedMs: { 0 }, candidate: { $0 }) { id, mayStart in
            XCTAssertTrue(mayStart())
            visited.append(id)
            return true
        }
        XCTAssertEqual(visited.last, next)
        XCTAssertEqual(end, next + 1)
    }

    func testTraversalResumesCandidateInterruptedBetweenItsWindowAndRoleReads() {
        var elapsed = 0.0
        var roleReads = [UInt64]()
        let next = AxTraversalPolicy.scan(from: 41, elapsedMs: { elapsed }, candidate: { $0 }) { id, mayStart in
            guard mayStart() else { return false }
            if id == 42 { elapsed = AxTraversalPolicy.budgetMs }
            guard mayStart() else { return false }
            roleReads.append(id)
            return false
        }
        XCTAssertEqual(next, 42)
        XCTAssertEqual(roleReads, [41])
        let end = AxTraversalPolicy.scan(from: next, elapsedMs: { 0 }, candidate: { $0 }) { id, mayStart in
            XCTAssertTrue(mayStart())
            roleReads.append(id)
            return true
        }
        XCTAssertEqual(end, 43)
        XCTAssertEqual(roleReads, [41, 42])
    }

    func testTraversalRetriesCandidateWhenConstructionUsesTheRemainingTime() {
        var elapsed = 0.0
        let next = AxTraversalPolicy.scan(from: 7, elapsedMs: { elapsed }, candidate: { id in
            elapsed = AxTraversalPolicy.budgetMs
            return id
        }) { _, mayStart in
            XCTAssertFalse(mayStart())
            return false
        }
        XCTAssertEqual(next, 7)
    }

    func testTraversalCountsMissingCandidatesAndDoesNotWrapAtTheLastId() {
        var constructed = 0
        let next = AxTraversalPolicy.scan(from: 10, elapsedMs: { Double(constructed) }, candidate: { _ -> UInt64? in
            constructed += 1
            return nil
        }) { _, _ in XCTFail("A missing element cannot be inspected"); return false }
        XCTAssertEqual(constructed, Int(AxTraversalPolicy.budgetMs))
        XCTAssertEqual(next, UInt64(10 + constructed))
        XCTAssertEqual(AxTraversalPolicy.scan(from: UInt64.max - 1, elapsedMs: { 0 }, candidate: { $0 }) {
            _, mayStart in mayStart()
        }, UInt64.max)
    }

    func testAxTraversalStopsAtTheWallClockBudget() {
        XCTAssertTrue(AxTraversalPolicy.mayStartIpc(elapsedMs: AxTraversalPolicy.budgetMs - 0.001))
        XCTAssertFalse(AxTraversalPolicy.mayStartIpc(elapsedMs: AxTraversalPolicy.budgetMs))
    }
}
