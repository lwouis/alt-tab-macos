import XCTest

final class PermissionCheckRetryTests: XCTestCase {
    func testTimeoutRetriesAreBounded() {
        var retry = PermissionCheckRetry()
        retry.begin()
        XCTAssertEqual((0..<4).map { _ in retry.nextDelay(unknown: true) }, [1, 2, 4, nil])
    }

    func testAnAnswerCancelsThePendingRetry() {
        var retry = PermissionCheckRetry()
        _ = retry.nextDelay(unknown: true)
        let pending = retry.generation
        XCTAssertNil(retry.nextDelay(unknown: false))
        XCTAssertNotEqual(retry.generation, pending)
    }

    func testANewerPermissionEventReplacesTheRetryBudget() {
        var retry = PermissionCheckRetry()
        for _ in 0..<4 { _ = retry.nextDelay(unknown: true) }
        let pending = retry.generation
        retry.begin()
        XCTAssertNotEqual(retry.generation, pending)
        XCTAssertEqual(retry.nextDelay(unknown: true), 1)
    }

    func testAKnownDenialDoesNotPoll() {
        var retry = PermissionCheckRetry()
        XCTAssertNil(retry.nextDelay(unknown: false))
    }
}
