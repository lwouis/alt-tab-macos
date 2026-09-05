import XCTest

final class ScreenCaptureCoordinatorTests: XCTestCase {
    func testPreflightDeadlineCannotExpireSubmittedCapture() {
        var watchdogs = [() -> Void]()
        let coordinator = ScreenCaptureCoordinator { _, action in watchdogs.append(action) }
        coordinator.submit { completion in
            XCTAssertEqual(watchdogs.count, 2)
            watchdogs[0]()
            XCTAssertFalse(coordinator.isCircuitOpen)
            watchdogs.last?()
            XCTAssertTrue(coordinator.isCircuitOpen)
            completion()
        }
        XCTAssertFalse(coordinator.isCircuitOpen)
        XCTAssertEqual(coordinator.inFlightCount, 0)
    }

    func testFocusedPreviewSubmissionIsNotOvertaken() {
        let coordinator = ScreenCaptureCoordinator.shared
        let initialSubmissions = expectation(description: "both slots occupied")
        initialSubmissions.expectedFulfillmentCount = 2
        let lock = NSLock()
        var completions = [() -> Void]()
        for _ in 0 ..< 2 {
            coordinator.submit { completion in
                lock.lock()
                completions.append(completion)
                lock.unlock()
                initialSubmissions.fulfill()
            }
        }
        wait(for: [initialSubmissions], timeout: 2)
        let previewChecking = expectation(description: "preview reaches preflight")
        let releasePreview = DispatchSemaphore(value: 0)
        let thumbnailStarted = DispatchSemaphore(value: 0)
        let finished = expectation(description: "both queued requests finish")
        finished.expectedFulfillmentCount = 2
        coordinator.submit { completion in
            thumbnailStarted.signal()
            completion()
            finished.fulfill()
        }
        coordinator.submit(priority: .focusedPreview, if: {
            previewChecking.fulfill()
            return releasePreview.wait(timeout: .now() + 2) == .success
        }) { completion in
            completion()
            finished.fulfill()
        }
        lock.lock()
        let releases = completions
        lock.unlock()
        guard releases.count == 2 else { XCTFail("missing occupied slots"); return }
        releases[0]()
        wait(for: [previewChecking], timeout: 2)
        releases[1]()
        XCTAssertEqual(thumbnailStarted.wait(timeout: .now() + 0.1), .timedOut)
        releasePreview.signal()
        wait(for: [finished], timeout: 2)
    }

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

    func testSharedCoordinatorSubmitsOutsideMainQueue() {
        let submitted = expectation(description: "capture submitted off main")
        DispatchQueue.main.async {
            ScreenCaptureCoordinator.shared.submit { completion in
                XCTAssertFalse(Thread.isMainThread)
                completion()
                submitted.fulfill()
            }
        }
        wait(for: [submitted], timeout: 2)
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
        XCTAssertEqual(watchdogs.count, 6)
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

        watchdogs.last?()

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
