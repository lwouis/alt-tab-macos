import XCTest

final class WindowCaptureRequestCoordinatorTests: XCTestCase {
    func testFirstRequestStartsCapture() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(coordinator.request(101), 1)
        XCTAssertTrue(coordinator.shouldApplyResult(for: 101, generation: 1))
    }

    func testNewerRequestsCoalesceIntoOneRetryAndMakeOlderResultStale() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(coordinator.request(101), 1)
        XCTAssertNil(coordinator.request(101))
        XCTAssertNil(coordinator.request(101))
        XCTAssertFalse(coordinator.shouldApplyResult(for: 101, generation: 1))
        XCTAssertEqual(coordinator.finish(101, generation: 1), 3)
        XCTAssertTrue(coordinator.shouldApplyResult(for: 101, generation: 3))
        XCTAssertNil(coordinator.finish(101, generation: 3))
    }

    func testWindowsTrackIndependentGenerations() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(coordinator.request(101), 1)
        XCTAssertEqual(coordinator.request(202), 1)
        XCTAssertNil(coordinator.request(101))
        XCTAssertTrue(coordinator.shouldApplyResult(for: 202, generation: 1))
        XCTAssertFalse(coordinator.shouldApplyResult(for: 101, generation: 1))
        XCTAssertEqual(coordinator.finish(101, generation: 1), 2)
        XCTAssertNil(coordinator.finish(202, generation: 1))
    }

    func testCompletedWindowKeepsMonotonicGenerations() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(coordinator.request(101), 1)
        XCTAssertNil(coordinator.finish(101, generation: 1))
        XCTAssertEqual(coordinator.request(101), 2)
    }

    func testCancelInvalidatesOutstandingStateAndKeepsMonotonicGenerations() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(coordinator.request(101), 1)
        XCTAssertNil(coordinator.request(101))
        coordinator.cancel(101)
        XCTAssertFalse(coordinator.shouldApplyResult(for: 101, generation: 1))
        let nextGeneration = coordinator.request(101)
        XCTAssertNotNil(nextGeneration)
        XCTAssertGreaterThan(nextGeneration ?? 0, 1)
    }

    func testCancelPreventsOldCompletionFromClearingNewActiveGeneration() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(coordinator.request(101), 1)
        XCTAssertNil(coordinator.request(101))
        coordinator.cancel(101)
        let nextGeneration = coordinator.request(101)
        XCTAssertNotNil(nextGeneration)
        XCTAssertTrue(coordinator.shouldApplyResult(for: 101, generation: nextGeneration!))
        XCTAssertNil(coordinator.finish(101, generation: 1))
        XCTAssertNil(coordinator.request(101))
        XCTAssertEqual(coordinator.finish(101, generation: nextGeneration!), nextGeneration! + 1)
    }

    // Hammers the coordinator from 8 concurrent queues to verify the NSLock-based critical
    // section holds under load: at most one request() may be granted before that caller
    // invokes finish(), and latestRequestedGeneration must reflect every request() bump.
    func testConcurrentRequestsAndFinishesHonorActiveSlotInvariant() {
        let coordinator = WindowCaptureRequestCoordinator()
        let wid: CGWindowID = 42
        let producers = 8
        let perProducer = 5_000
        let lock = NSLock()
        var preFinishHolders = 0
        var maxPreFinish = 0
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.producers", attributes: .concurrent)
        for _ in 0..<producers {
            group.enter()
            queue.async {
                for _ in 0..<perProducer {
                    if let generation = coordinator.request(wid) {
                        lock.lock()
                        preFinishHolders += 1
                        if preFinishHolders > maxPreFinish { maxPreFinish = preFinishHolders }
                        lock.unlock()
                        lock.lock()
                        preFinishHolders -= 1
                        lock.unlock()
                        var current: Int? = generation
                        while let cur = current { current = coordinator.finish(wid, generation: cur) }
                    }
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + .seconds(30)), .success)
        XCTAssertEqual(maxPreFinish, 1)
        let finalGeneration = coordinator.request(wid)
        XCTAssertNotNil(finalGeneration)
        XCTAssertGreaterThanOrEqual(finalGeneration ?? 0, producers * perProducer)
    }
}
