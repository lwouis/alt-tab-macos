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
}
