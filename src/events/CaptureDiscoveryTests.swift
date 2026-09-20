import XCTest

final class CaptureDiscoveryTests: XCTestCase {
    private let first = CaptureDiscoveryKey(wid: 1, fullRes: false)
    private let late = CaptureDiscoveryKey(wid: 2, fullRes: false)

    @discardableResult
    private func insert(_ buffer: inout CaptureDiscovery<Int>, _ key: CaptureDiscoveryKey,
                        value: Int = 1, prioritized: Bool = false) -> Int {
        buffer.insert(key, value, prioritized: prioritized) { $0 + $1 }
    }

    func testLateWindowMissingFromOldSnapshotGetsNewDiscovery() {
        var buffer = CaptureDiscovery<Int>(capacity: 256)
        insert(&buffer, first)
        XCTAssertNotNil(buffer.begin())
        insert(&buffer, late, value: 2)
        XCTAssertNil(buffer.begin())
        XCTAssertEqual(buffer.finish(generation: buffer.generation) { $0 == first }, [first: 1])
        XCTAssertNotNil(buffer.begin())
        XCTAssertEqual(buffer.finish(generation: buffer.generation) { $0 == late }, [late: 2])
        XCTAssertNil(buffer.begin())
    }

    func testStillMissingWindowStopsAfterItsOwnDiscovery() {
        var buffer = CaptureDiscovery<Int>(capacity: 256)
        insert(&buffer, first)
        XCTAssertNotNil(buffer.begin())
        insert(&buffer, late)
        XCTAssertEqual(buffer.finish(generation: buffer.generation) { _ in false }, [first: 1])
        XCTAssertNotNil(buffer.begin())
        XCTAssertEqual(buffer.finish(generation: buffer.generation) { _ in false }, [late: 1])
        XCTAssertNil(buffer.begin())
    }

    func testLateWindowAlreadyInSnapshotDoesNotNeedAnotherDiscovery() {
        var buffer = CaptureDiscovery<Int>(capacity: 256)
        insert(&buffer, first)
        XCTAssertNotNil(buffer.begin())
        insert(&buffer, late)
        XCTAssertEqual(buffer.finish(generation: buffer.generation) { _ in true }, [first: 1, late: 1])
        XCTAssertNil(buffer.begin())
    }

    func testRepeatedRequestsForCoveredMissingWindowDoNotExtendItsRetry() {
        var buffer = CaptureDiscovery<Int>(capacity: 256)
        insert(&buffer, first)
        XCTAssertNotNil(buffer.begin())
        for _ in 0..<100 { insert(&buffer, first) }
        XCTAssertEqual(buffer.finish(generation: buffer.generation) { _ in false }, [first: 101])
        XCTAssertNil(buffer.begin())
    }

    func testArrivalsDuringFollowUpBelongToAnotherGeneration() {
        var buffer = CaptureDiscovery<Int>(capacity: 256)
        let third = CaptureDiscoveryKey(wid: 3, fullRes: false)
        insert(&buffer, first)
        XCTAssertNotNil(buffer.begin())
        insert(&buffer, late)
        _ = buffer.finish(generation: buffer.generation) { _ in false }
        XCTAssertNotNil(buffer.begin())
        insert(&buffer, third)
        XCTAssertEqual(buffer.finish(generation: buffer.generation) { _ in false }, [late: 1])
        XCTAssertNotNil(buffer.begin())
        XCTAssertEqual(buffer.finish(generation: buffer.generation) { _ in true }, [third: 1])
        XCTAssertNil(buffer.begin())
    }

    func testCapacityAndPriorityApplyAcrossBothGenerations() {
        var buffer = CaptureDiscovery<Int>(capacity: 2)
        let preview = CaptureDiscoveryKey(wid: 1, fullRes: true)
        XCTAssertEqual(insert(&buffer, first, prioritized: true), 0)
        XCTAssertNotNil(buffer.begin())
        XCTAssertEqual(insert(&buffer, late), 0)
        XCTAssertEqual(insert(&buffer, preview, prioritized: true), 1)
        XCTAssertEqual(insert(&buffer, late), 1)
        XCTAssertEqual(buffer.finish(generation: buffer.generation) { _ in true }, [first: 1, preview: 1])
        XCTAssertNil(buffer.begin())
    }

    func testMergingUpgradesPriorityAndPreservesResolution() {
        var buffer = CaptureDiscovery<Int>(capacity: 2)
        let preview = CaptureDiscoveryKey(wid: 1, fullRes: true)
        insert(&buffer, first)
        insert(&buffer, first, value: 2, prioritized: true)
        insert(&buffer, preview, value: 4, prioritized: true)
        XCTAssertEqual(insert(&buffer, late, prioritized: true), 1)
        XCTAssertNotNil(buffer.begin())
        XCTAssertEqual(buffer.finish(generation: buffer.generation) { _ in true }, [first: 3, preview: 4])
    }

    func testTimeoutAllowsTheNextOrdinaryRequestToDiscoverAgain() throws {
        var buffer = CaptureDiscovery<Int>(capacity: 2)
        insert(&buffer, first)
        let expired = try XCTUnwrap(buffer.begin())
        XCTAssertEqual(buffer.finish(generation: expired) { _ in false }, [first: 1])
        XCTAssertNil(buffer.begin(), "A timeout must not start an unbounded retry loop")
        insert(&buffer, first, value: 2)
        let recovered = try XCTUnwrap(buffer.begin())
        XCTAssertNotEqual(expired, recovered)
        XCTAssertEqual(buffer.finish(generation: recovered) { _ in true }, [first: 2])
    }

    func testLateCallbackCannotDrainOrPublishOverTheRecoveryGeneration() throws {
        var buffer = CaptureDiscovery<Int>(capacity: 2)
        insert(&buffer, first)
        let expired = try XCTUnwrap(buffer.begin())
        insert(&buffer, late, value: 2)
        XCTAssertEqual(buffer.finish(generation: expired) { _ in false }, [first: 1])
        let recovery = try XCTUnwrap(buffer.begin())
        XCTAssertNil(buffer.finish(generation: expired) { _ in
            XCTFail("An expired callback must not even inspect the newer generation")
            return true
        })
        XCTAssertNil(buffer.begin(), "The late callback must not release the active generation")
        XCTAssertEqual(buffer.finish(generation: recovery) { _ in true }, [late: 2])
    }

    func testLateTimeoutCannotFinishAnAlreadySuccessfulGeneration() throws {
        var buffer = CaptureDiscovery<Int>(capacity: 2)
        insert(&buffer, first)
        let successful = try XCTUnwrap(buffer.begin())
        XCTAssertEqual(buffer.finish(generation: successful) { _ in true }, [first: 1])
        insert(&buffer, late)
        XCTAssertNil(buffer.finish(generation: successful) { _ in false })
        let next = try XCTUnwrap(buffer.begin())
        XCTAssertNil(buffer.finish(generation: successful) { _ in false })
        XCTAssertEqual(buffer.finish(generation: next) { _ in true }, [late: 1])
    }
}
