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

    func testCancelDropsOutstandingState() {
        let coordinator = WindowCaptureRequestCoordinator()
        XCTAssertEqual(coordinator.request(101), 1)
        XCTAssertNil(coordinator.request(101))
        coordinator.cancel(101)
        XCTAssertEqual(coordinator.request(101), 1)
    }
}
