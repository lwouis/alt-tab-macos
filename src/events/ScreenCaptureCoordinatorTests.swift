import XCTest

final class ScreenCaptureCoordinatorTests: XCTestCase {
    func testWatchdogCoversPreflightWithoutStartingLateCapture() {
        var watchdogs = [() -> Void]()
        let coordinator = ScreenCaptureCoordinator { _, action in watchdogs.append(action) }
        var captured = false
        coordinator.submit(if: {
            XCTAssertEqual(watchdogs.count, 1)
            watchdogs.first?()
            return true
        }) { _ in captured = true }
        XCTAssertFalse(captured)
        XCTAssertEqual(coordinator.inFlightCount, 0)
        XCTAssertFalse(coordinator.isCircuitOpen)
        coordinator.submit { completion in
            captured = true
            completion()
        }
        XCTAssertTrue(captured)
    }

    func testSharedCoordinatorSubmitsOutsideMainQueue() async {
        let submitted = expectation(description: "capture submitted off main")
        DispatchQueue.main.async {
            ScreenCaptureCoordinator.shared.submit { completion in
                XCTAssertFalse(Thread.isMainThread)
                completion()
                submitted.fulfill()
            }
        }
        await fulfillment(of: [submitted], timeout: 2)
    }

    func testFocusedPreviewStartsBeforeQueuedThumbnails() {
        let coordinator = ScreenCaptureCoordinator(maximumInFlight: 1) { _, _ in }
        var release: (() -> Void)!
        var started = [String]()
        coordinator.submit { release = $0 }
        coordinator.submit { completion in
            started.append("thumbnail")
            completion()
        }
        coordinator.submit(priority: .focusedPreview) { completion in
            started.append("preview")
            completion()
        }
        release()
        XCTAssertEqual(started, ["preview", "thumbnail"])
    }

    func testLostCompletionsKeepCircuitClosedToNewWork() {
        var watchdogs = [() -> Void]()
        let coordinator = ScreenCaptureCoordinator { _, action in watchdogs.append(action) }
        var starts = 0
        for _ in 0 ..< 2 { coordinator.submit { _ in starts += 1 } }
        watchdogs.forEach { $0() }
        for _ in 0 ..< 20 { coordinator.submit { _ in starts += 1 } }
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(coordinator.inFlightCount, 2)
        XCTAssertTrue(coordinator.isCircuitOpen)
    }

    func testQueuedCaptureIsDroppedWhenEligibilityChanges() {
        let coordinator = ScreenCaptureCoordinator(maximumInFlight: 1) { _, _ in }
        var release: (() -> Void)!
        var switcherOpen = true
        var captured = false
        coordinator.submit { release = $0 }
        coordinator.submit(if: { switcherOpen }) { completion in
            captured = true
            completion()
        }
        switcherOpen = false
        release()
        XCTAssertFalse(captured)
        XCTAssertEqual(coordinator.inFlightCount, 0)
    }

    func testMaximumOfTwoCapturesCanRun() {
        var watchdogs = [() -> Void]()
        let coordinator = ScreenCaptureCoordinator(maximumInFlight: 2) { _, action in
            watchdogs.append(action)
        }
        var started = [Int]()
        var completions = [() -> Void]()

        for id in 1 ... 3 {
            coordinator.submit { completion in
                started.append(id)
                completions.append(completion)
            }
        }

        XCTAssertEqual(started, [1, 2])
        XCTAssertEqual(coordinator.inFlightCount, 2)
        completions[0]()
        XCTAssertEqual(started, [1, 2, 3])
        XCTAssertEqual(coordinator.inFlightCount, 2)
        XCTAssertEqual(watchdogs.count, 3)
    }

    func testWatchdogOpensCircuitUntilLateCompletion() {
        var watchdogs = [() -> Void]()
        let coordinator = ScreenCaptureCoordinator(maximumInFlight: 1, watchdogSeconds: 10) { _, action in
            watchdogs.append(action)
        }
        var started = [Int]()
        var firstCompletion: (() -> Void)!

        coordinator.submit { completion in
            started.append(1)
            firstCompletion = completion
        }
        coordinator.submit { _ in started.append(2) }
        XCTAssertEqual(started, [1])

        watchdogs[0]()

        XCTAssertEqual(started, [1])
        XCTAssertEqual(coordinator.inFlightCount, 1)
        XCTAssertTrue(coordinator.isCircuitOpen)
        coordinator.submit { _ in started.append(3) }
        XCTAssertEqual(started, [1])

        firstCompletion()
        coordinator.submit { _ in started.append(4) }

        XCTAssertEqual(started, [1, 4])
        XCTAssertFalse(coordinator.isCircuitOpen)
    }

    func testCompletionCanReleaseOnlyOneSlot() {
        let coordinator = ScreenCaptureCoordinator(maximumInFlight: 1) { _, _ in }
        var firstCompletion: (() -> Void)!
        var starts = 0

        coordinator.submit { completion in
            starts += 1
            firstCompletion = completion
        }
        coordinator.submit { _ in starts += 1 }

        firstCompletion()
        firstCompletion()

        XCTAssertEqual(starts, 2)
        XCTAssertEqual(coordinator.inFlightCount, 1)
    }
}
