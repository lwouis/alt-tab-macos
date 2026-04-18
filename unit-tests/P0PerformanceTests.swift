import XCTest

// Inline the optimized extension so the test target compiles standalone
private extension Array where Element: Comparable {
    func countOfElementsLessThan_optimized(_ value: Element) -> Int {
        var lo = startIndex, hi = endIndex
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if self[mid] < value { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}

// MARK: - P0-1: Dictionary lookup vs Array linear scan for cached window IDs

final class CachedWindowLookupTests: XCTestCase {
    func testDictionaryLookupCorrectness() {
        let ids: [CGWindowID] = [10, 20, 30, 40, 50]
        let dict = Dictionary(uniqueKeysWithValues: ids.map { ($0, "window-\($0)") })
        XCTAssertEqual(dict[30], "window-30")
        XCTAssertNil(dict[99])
        XCTAssertEqual(dict.count, 5)
    }

    func testDictionaryLookupVsArrayLinearScan() {
        let count = 5000
        let allIds: [CGWindowID] = (0..<count).map { CGWindowID($0) }
        let queryIds: [CGWindowID] = (0..<500).map { _ in CGWindowID(Int.random(in: 0..<count)) }

        let dict = Dictionary(uniqueKeysWithValues: allIds.map { ($0, $0) })
        let array = allIds

        var dictResults = [CGWindowID]()
        var arrayResults = [CGWindowID]()

        let dictTime = ContinuousClock().measure {
            for _ in 0..<100 {
                for id in queryIds {
                    if let v = dict[id] { dictResults.append(v) }
                }
            }
        }

        let arrayTime = ContinuousClock().measure {
            for _ in 0..<100 {
                for id in queryIds {
                    if let v = (array.first { $0 == id }) { arrayResults.append(v) }
                }
            }
        }

        XCTAssertEqual(dictResults.count, arrayResults.count, "Both approaches should find the same number of matches")
        let speedup = Double(arrayTime.components.attoseconds) / Double(dictTime.components.attoseconds)
        print("P0-1 Dictionary lookup: \(dictTime)")
        print("P0-1 Array linear scan: \(arrayTime)")
        print("P0-1 Speedup: \(String(format: "%.1f", speedup))x")
        XCTAssertGreaterThan(speedup, 2.0, "Dictionary should be significantly faster than linear scan")
    }
}

// MARK: - P0-2: Queue separation (correctness / concurrency test)

final class QueueSeparationTests: XCTestCase {
    func testSeparateQueuesRunConcurrently() {
        let screenshotsQueue = OperationQueue()
        screenshotsQueue.maxConcurrentOperationCount = 8
        screenshotsQueue.name = "screenshots"

        let appIconsQueue = OperationQueue()
        appIconsQueue.maxConcurrentOperationCount = 4
        appIconsQueue.name = "appIcons"

        let expectation = XCTestExpectation(description: "All operations complete")
        expectation.expectedFulfillmentCount = 2

        let screenshotStarted = DispatchSemaphore(value: 0)
        let iconStarted = DispatchSemaphore(value: 0)

        var screenshotSawIconRunning = false
        var iconSawScreenshotRunning = false

        screenshotsQueue.addOperation {
            screenshotStarted.signal()
            iconStarted.wait()
            screenshotSawIconRunning = true
            expectation.fulfill()
        }

        appIconsQueue.addOperation {
            iconStarted.signal()
            screenshotStarted.wait()
            iconSawScreenshotRunning = true
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(screenshotSawIconRunning, "Screenshot op should observe icon op running concurrently")
        XCTAssertTrue(iconSawScreenshotRunning, "Icon op should observe screenshot op running concurrently")
    }

    func testSharedQueueBlocksWhenFull() {
        let sharedQueue = OperationQueue()
        sharedQueue.maxConcurrentOperationCount = 2

        let allSlotsUsed = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let thirdOpStarted = XCTestExpectation(description: "Third op started")

        sharedQueue.addOperation {
            allSlotsUsed.signal()
            release.wait()
        }
        sharedQueue.addOperation {
            allSlotsUsed.signal()
            release.wait()
        }

        allSlotsUsed.wait()
        allSlotsUsed.wait()

        var thirdStartTime: ContinuousClock.Instant?
        let enqueueTime = ContinuousClock.now
        sharedQueue.addOperation {
            thirdStartTime = ContinuousClock.now
            thirdOpStarted.fulfill()
        }

        Thread.sleep(forTimeInterval: 0.1)
        release.signal()
        release.signal()

        wait(for: [thirdOpStarted], timeout: 5.0)
        let delay = thirdStartTime! - enqueueTime
        let delayMs = Double(delay.components.attoseconds) / 1e15
        print("P0-2 Third op delayed by \(String(format: "%.0f", delayMs))ms when shared queue was full")
        XCTAssertGreaterThan(delayMs, 50, "Third op should be delayed when all slots are occupied")
    }
}

// MARK: - P0-3: Set contains vs Array contains + binary search shift count

final class RemoveWindowsOptimizationTests: XCTestCase {
    func testSetContainsCorrectness() {
        let toRemove = Set([2, 5, 8])
        XCTAssertTrue(toRemove.contains(2))
        XCTAssertTrue(toRemove.contains(5))
        XCTAssertTrue(toRemove.contains(8))
        XCTAssertFalse(toRemove.contains(3))
        XCTAssertFalse(toRemove.contains(0))
    }

    func testBinarySearchCountCorrectness() {
        let sorted = [2, 5, 8, 12, 20]
        XCTAssertEqual(sorted.countOfElementsLessThan_optimized(0), 0)
        XCTAssertEqual(sorted.countOfElementsLessThan_optimized(2), 0)
        XCTAssertEqual(sorted.countOfElementsLessThan_optimized(3), 1)
        XCTAssertEqual(sorted.countOfElementsLessThan_optimized(6), 2)
        XCTAssertEqual(sorted.countOfElementsLessThan_optimized(8), 2)
        XCTAssertEqual(sorted.countOfElementsLessThan_optimized(9), 3)
        XCTAssertEqual(sorted.countOfElementsLessThan_optimized(100), 5)
    }

    func testBinarySearchCountEdgeCases() {
        let empty: [Int] = []
        XCTAssertEqual(empty.countOfElementsLessThan_optimized(5), 0)
        let single = [10]
        XCTAssertEqual(single.countOfElementsLessThan_optimized(5), 0)
        XCTAssertEqual(single.countOfElementsLessThan_optimized(10), 0)
        XCTAssertEqual(single.countOfElementsLessThan_optimized(15), 1)
    }

    func testRemoveWindowsOptimizedVsOriginal() {
        let listSize = 5000
        let removeCount = 500
        let removeOrders = Set((0..<listSize).shuffled().prefix(removeCount))
        let sortedRemoveOrders = removeOrders.sorted()

        struct FakeWindow {
            var lastFocusOrder: Int
        }

        let originalList = (0..<listSize).map { FakeWindow(lastFocusOrder: $0) }
        let originalToRemove = Array(removeOrders)
        let originalTime = ContinuousClock().measure {
            for _ in 0..<100 {
                var list = originalList
                list.removeAll { w in
                    if originalToRemove.contains(w.lastFocusOrder) {
                        return true
                    }
                    let howManyToShift = originalToRemove.reduce(0) { $1 < w.lastFocusOrder ? $0 + 1 : $0 }
                    _ = howManyToShift
                    return false
                }
            }
        }

        let optimizedTime = ContinuousClock().measure {
            for _ in 0..<100 {
                var list = originalList
                list.removeAll { w in
                    if removeOrders.contains(w.lastFocusOrder) {
                        return true
                    }
                    let howManyToShift = sortedRemoveOrders.countOfElementsLessThan_optimized(w.lastFocusOrder)
                    _ = howManyToShift
                    return false
                }
            }
        }

        let speedup = Double(arrayTimeNs(originalTime)) / Double(arrayTimeNs(optimizedTime))
        print("P0-3 Original (Array contains + reduce): \(originalTime)")
        print("P0-3 Optimized (Set contains + binary search): \(optimizedTime)")
        print("P0-3 Speedup: \(String(format: "%.1f", speedup))x")
        XCTAssertGreaterThan(speedup, 5.0, "Set + binary search should be much faster than Array contains + reduce")
    }

    private func arrayTimeNs(_ duration: Duration) -> Int64 {
        return duration.components.seconds * 1_000_000_000 + duration.components.attoseconds / 1_000_000_000
    }
}
