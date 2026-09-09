import XCTest

/// Pins the supersede-and-repair rule that keeps a slow focus operation from raising its window after a
/// faster one already switched. See FocusIntentPolicySpecs.md.
final class FocusIntentPolicyTests: XCTestCase {
    private let safari: pid_t = 500
    private let terminal: pid_t = 600

    /// The fast alt-tab, in one line. Both operations are in flight; only the newest may act.
    func testANewerRequestSupersedesTheOlderOne() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        let second = policy.request(wid: 2, pid: terminal, now: 0.2)
        XCTAssertFalse(policy.mayProceed(first), "a superseded operation was still allowed to touch the screen")
        XCTAssertTrue(policy.mayProceed(second))
    }

    /// A backlog collapses to its last member rather than replaying every switch the user passed through.
    func testTheNewestRequestAlwaysProceeds() {
        var policy = FocusIntentPolicy()
        let generations = (0..<5).map { policy.request(wid: CGWindowID($0), pid: safari, now: Double($0) * 0.2) }
        for generation in generations.dropLast() {
            XCTAssertFalse(policy.mayProceed(generation))
        }
        XCTAssertTrue(policy.mayProceed(generations.last!))
    }

    /// **The case a bail alone misses.** Safari's raise was posted before Terminal was ever requested, and a
    /// posted event cannot be recalled: it lands late and puts Safari back on top of Terminal. The stale
    /// operation has to re-assert the current intent on its way out.
    func testASupersededOpThatAlreadyReorderedAsksForARepair() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        policy.noteReordered(first, now: 0.01)
        let second = policy.request(wid: 2, pid: terminal, now: 0.2)
        let repair = policy.finish(first, now: 0.5)
        XCTAssertEqual(repair?.generation, second, "the stale raise landed and nothing re-asserted the switch")
        XCTAssertEqual(repair?.wid, 2)
        XCTAssertEqual(repair?.pid, terminal)
    }

    /// It stopped at a checkpoint before fronting or raising anything, so the screen is already right and a
    /// repair would be a redundant re-front.
    func testASupersededOpThatNeverReorderedAsksForNoRepair() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        _ = policy.request(wid: 2, pid: terminal, now: 0.2)
        XCTAssertNil(policy.finish(first, now: 0.5))
    }

    /// The ordinary single switch: nobody overtook it, so it owes nothing.
    func testTheCurrentOpAsksForNoRepair() {
        var policy = FocusIntentPolicy()
        let only = policy.request(wid: 1, pid: safari, now: 0)
        policy.noteReordered(only, now: 0.01)
        XCTAssertNil(policy.finish(only, now: 0.02))
    }

    /// Past the horizon the user has had a second to click somewhere themselves. Re-asserting then would take
    /// the front away from them, which is worse than the stale raise it repairs.
    func testARepairIsRefusedOnceTheIntentIsStale() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        policy.noteReordered(first, now: 0.01)
        _ = policy.request(wid: 2, pid: terminal, now: 0.2)
        XCTAssertNil(policy.finish(first, now: 0.2 + FocusIntentPolicy.repairHorizon + 0.01))
    }

    /// Both stale operations clobbered the same intent, and the first repair already re-asserted it.
    func testTwoStaleOpsProduceOneRepair() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        policy.noteReordered(first, now: 0.01)
        let second = policy.request(wid: 2, pid: terminal, now: 0.1)
        policy.noteReordered(second, now: 0.11)
        _ = policy.request(wid: 3, pid: safari, now: 0.2)
        XCTAssertNotNil(policy.finish(first, now: 0.5))
        XCTAssertNil(policy.finish(second, now: 0.6), "the intent was re-asserted twice for one clobber")
    }

    /// An operation reports its outcome once, so the re-assert cannot start another round of repairs.
    func testARepairDoesNotCascade() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        policy.noteReordered(first, now: 0.01)
        _ = policy.request(wid: 2, pid: terminal, now: 0.2)
        XCTAssertNotNil(policy.finish(first, now: 0.5))
        XCTAssertNil(policy.finish(first, now: 0.6))
    }

    /// The generation is per request, not per window: holding the shortcut through a window and back still
    /// leaves the older operation superseded.
    func testARepeatedFocusOfTheSameWindowStillSupersedes() {
        var policy = FocusIntentPolicy()
        let first = policy.request(wid: 1, pid: safari, now: 0)
        let second = policy.request(wid: 1, pid: safari, now: 0.2)
        XCTAssertFalse(policy.mayProceed(first))
        XCTAssertTrue(policy.mayProceed(second))
    }
}
