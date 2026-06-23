import XCTest

/// Pins the AX query pool-selection as a pure, deterministic decision — no queues, threads, or timing.
/// Covers the three lanes and the use-cases we walked through. Future refactors of `AXCallScheduler`'s
/// pool routing must keep this green.
final class AxQueryRoutingTests: XCTestCase {

    // MARK: - Pool routing (queue selection)

    func testPoolFirstTryForResponsiveEvent() {
        XCTAssertEqual(AxQueryRouting.pool(unresponsive: false, scan: false), .firstTry)
    }

    func testPoolScanIsolatesBulkInventory() {
        XCTAssertEqual(AxQueryRouting.pool(unresponsive: false, scan: true), .scan)
    }

    func testPoolUnresponsiveQuarantinesToRetry() {
        XCTAssertEqual(AxQueryRouting.pool(unresponsive: true, scan: false), .retry)
        // unresponsive wins over scan — a beach-balling app's scan call must not clog the scan pool
        XCTAssertEqual(AxQueryRouting.pool(unresponsive: true, scan: true), .retry)
    }

    // MARK: - Use-case integration (deterministic routing of the discussed scenarios)

    func testUseCaseManualRefreshIsolatesOnScanPool() {
        // manuallyRefreshAllWindows → 60-app inventory: every call routes to the isolated scan pool
        for _ in 0..<60 {
            XCTAssertEqual(AxQueryRouting.pool(unresponsive: false, scan: true), .scan)
        }
    }

    func testUseCaseUnresponsiveAppQuarantines() {
        XCTAssertEqual(AxQueryRouting.pool(unresponsive: true, scan: false), .retry)
        XCTAssertEqual(AxQueryRouting.pool(unresponsive: true, scan: true), .retry)
    }
}
