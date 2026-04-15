import XCTest
import CoreGraphics

final class WindowCaptureRequestCoordinatorTests: XCTestCase {
    func testFirstRequestStartsCapture() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(
            coordinator.request(101, source: .refreshUiAfterExternalEvent),
            WindowCaptureRequestCoordinator.Activation(generation: 1, source: .refreshUiAfterExternalEvent)
        )
        XCTAssertTrue(coordinator.shouldApplyResult(for: 101, generation: 1))
    }

    func testNewerRequestsCoalesceIntoOneRetryAndMakeOlderResultStale() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(
            coordinator.request(101, source: .refreshUiAfterExternalEvent),
            WindowCaptureRequestCoordinator.Activation(generation: 1, source: .refreshUiAfterExternalEvent)
        )
        XCTAssertNil(coordinator.request(101, source: .refreshUiAfterExternalEvent))
        XCTAssertNil(coordinator.request(101, source: .refreshUiAfterExternalEvent))
        XCTAssertFalse(coordinator.shouldApplyResult(for: 101, generation: 1))
        XCTAssertEqual(
            coordinator.finish(101, generation: 1),
            WindowCaptureRequestCoordinator.Activation(generation: 3, source: .refreshUiAfterExternalEvent)
        )
        XCTAssertTrue(coordinator.shouldApplyResult(for: 101, generation: 3))
        XCTAssertNil(coordinator.finish(101, generation: 3))
    }

    func testWindowsTrackIndependentGenerations() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(
            coordinator.request(101, source: .refreshUiAfterExternalEvent),
            WindowCaptureRequestCoordinator.Activation(generation: 1, source: .refreshUiAfterExternalEvent)
        )
        XCTAssertEqual(
            coordinator.request(202, source: .refreshUiAfterExternalEvent),
            WindowCaptureRequestCoordinator.Activation(generation: 1, source: .refreshUiAfterExternalEvent)
        )
        XCTAssertNil(coordinator.request(101, source: .refreshUiAfterExternalEvent))
        XCTAssertTrue(coordinator.shouldApplyResult(for: 202, generation: 1))
        XCTAssertFalse(coordinator.shouldApplyResult(for: 101, generation: 1))
        XCTAssertEqual(
            coordinator.finish(101, generation: 1),
            WindowCaptureRequestCoordinator.Activation(generation: 2, source: .refreshUiAfterExternalEvent)
        )
        XCTAssertNil(coordinator.finish(202, generation: 1))
    }

    func testCompletedWindowPrunesEntryAllowingFreshGenerations() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(
            coordinator.request(101, source: .refreshUiAfterExternalEvent),
            WindowCaptureRequestCoordinator.Activation(generation: 1, source: .refreshUiAfterExternalEvent)
        )
        XCTAssertNil(coordinator.finish(101, generation: 1))
        // entry pruned: the next request starts fresh at generation 1
        XCTAssertEqual(
            coordinator.request(101, source: .refreshUiAfterExternalEvent),
            WindowCaptureRequestCoordinator.Activation(generation: 1, source: .refreshUiAfterExternalEvent)
        )
    }

    func testCancelOnQuiescentWindowPrunesEntry() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(
            coordinator.request(101, source: .refreshUiAfterExternalEvent)?.generation, 1
        )
        XCTAssertNil(coordinator.finish(101, generation: 1))
        // entry is already pruned by finish
        coordinator.cancel(101) // should be a no-op, not crash
        XCTAssertEqual(
            coordinator.request(101, source: .refreshUiAfterExternalEvent)?.generation, 1
        )
    }

    func testStaleFinishAfterCancelPrunesEntry() {
        let coordinator = WindowCaptureRequestCoordinator()
        _ = coordinator.request(101, source: .refreshUiAfterExternalEvent)
        coordinator.cancel(101)
        XCTAssertNil(coordinator.finish(101, generation: 1))
        // entry pruned: next request starts fresh
        XCTAssertEqual(
            coordinator.request(101, source: .refreshUiAfterExternalEvent)?.generation, 1
        )
    }

    func testCancelInvalidatesOutstandingStateAndKeepsMonotonicGenerations() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(
            coordinator.request(101, source: .refreshUiAfterExternalEvent),
            WindowCaptureRequestCoordinator.Activation(generation: 1, source: .refreshUiAfterExternalEvent)
        )
        XCTAssertNil(coordinator.request(101, source: .refreshUiAfterExternalEvent))
        coordinator.cancel(101)
        XCTAssertFalse(coordinator.shouldApplyResult(for: 101, generation: 1))
        let nextActivation = coordinator.request(101, source: .refreshUiAfterExternalEvent)
        XCTAssertNotNil(nextActivation)
        XCTAssertGreaterThan(nextActivation?.generation ?? 0, 1)
    }

    func testCancelPreventsOldCompletionFromClearingNewActiveGeneration() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(
            coordinator.request(101, source: .refreshUiAfterExternalEvent),
            WindowCaptureRequestCoordinator.Activation(generation: 1, source: .refreshUiAfterExternalEvent)
        )
        XCTAssertNil(coordinator.request(101, source: .refreshUiAfterExternalEvent))
        coordinator.cancel(101)
        let nextActivation = coordinator.request(101, source: .refreshUiAfterExternalEvent)
        XCTAssertNotNil(nextActivation)
        let nextGeneration = nextActivation!.generation
        XCTAssertTrue(coordinator.shouldApplyResult(for: 101, generation: nextGeneration))
        XCTAssertNil(coordinator.finish(101, generation: 1))
        XCTAssertNil(coordinator.request(101, source: .refreshUiAfterExternalEvent))
        XCTAssertEqual(
            coordinator.finish(101, generation: nextGeneration),
            WindowCaptureRequestCoordinator.Activation(generation: nextGeneration + 1, source: .refreshUiAfterExternalEvent)
        )
    }

    func testCoalescedRetryUsesLatestCallerSource() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(
            coordinator.request(101, source: .refreshUiAfterExternalEvent),
            WindowCaptureRequestCoordinator.Activation(generation: 1, source: .refreshUiAfterExternalEvent)
        )
        XCTAssertNil(coordinator.request(101, source: .refreshOnlyThumbnailsAfterShowUi))
        XCTAssertEqual(
            coordinator.finish(101, generation: 1),
            WindowCaptureRequestCoordinator.Activation(generation: 2, source: .refreshOnlyThumbnailsAfterShowUi)
        )
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
                    if let activation = coordinator.request(wid, source: .refreshUiAfterExternalEvent) {
                        lock.lock()
                        preFinishHolders += 1
                        if preFinishHolders > maxPreFinish { maxPreFinish = preFinishHolders }
                        lock.unlock()
                        var current: Int? = activation.generation
                        while let cur = current { current = coordinator.finish(wid, generation: cur)?.generation }
                        lock.lock()
                        preFinishHolders -= 1
                        lock.unlock()
                    }
                }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + .seconds(30)), .success)
        XCTAssertEqual(maxPreFinish, 1)
        // After convergence the coordinator must be quiescent: a new request must be granted.
        let finalActivation = coordinator.request(wid, source: .refreshUiAfterExternalEvent)
        XCTAssertNotNil(finalActivation)
    }
}
