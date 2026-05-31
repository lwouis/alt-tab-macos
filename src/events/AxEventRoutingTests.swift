import XCTest
import ApplicationServices.HIServices.AXNotificationConstants

/// Pins the AX event routing/throttling design as pure, deterministic decisions — no queues, threads,
/// or timing. Covers pool selection, throttle scoping, the MRU-order fast path, the de-dup-key collision
/// fixes, and the use-cases we walked through. Future refactors of the AX pipeline must keep this green.
final class AxEventRoutingTests: XCTestCase {

    // MARK: - A. Pool routing (queue selection)

    func testPoolFirstTryForResponsiveEvent() {
        XCTAssertEqual(AxEventRouting.pool(unresponsive: false, scan: false), .firstTry)
    }

    func testPoolScanIsolatesBulkInventory() {
        XCTAssertEqual(AxEventRouting.pool(unresponsive: false, scan: true), .scan)
    }

    func testPoolUnresponsiveQuarantinesToRetry() {
        XCTAssertEqual(AxEventRouting.pool(unresponsive: true, scan: false), .retry)
        // unresponsive wins over scan — a beach-balling app's scan call must not clog the scan pool
        XCTAssertEqual(AxEventRouting.pool(unresponsive: true, scan: true), .retry)
    }

    // MARK: - B. Throttle scoping (which events coalesce)

    func testOnlyResizeMoveTitleCoalesce() {
        XCTAssertTrue(AxEventRouting.coalesces(kAXWindowResizedNotification))
        XCTAssertTrue(AxEventRouting.coalesces(kAXWindowMovedNotification))
        XCTAssertTrue(AxEventRouting.coalesces(kAXTitleChangedNotification))
    }

    func testEdgeEventsAreNeverCoalesced() {
        for type in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXApplicationActivatedNotification,
                     kAXWindowCreatedNotification, kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                     kAXWindowDeminiaturizedNotification, kAXApplicationHiddenNotification, kAXApplicationShownNotification] {
            XCTAssertFalse(AxEventRouting.coalesces(type), "\(type) is edge-triggered and must run promptly")
        }
    }

    // MARK: - C. Fast-path classification (MRU order)

    func testFocusMainActivationTakeFastPath() {
        for type in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXApplicationActivatedNotification] {
            XCTAssertTrue(AxEventRouting.updatesFocusOrder(type))
        }
    }

    func testNonOrderEventsDoNotTakeFastPath() {
        for type in [kAXWindowResizedNotification, kAXWindowCreatedNotification, kAXApplicationHiddenNotification, kAXTitleChangedNotification] {
            XCTAssertFalse(AxEventRouting.updatesFocusOrder(type))
        }
    }

    // MARK: - D. De-dup keys (the collision fixes)

    func testWindowDedupKeysByBucket() {
        XCTAssertEqual(AxEventRouting.dedupKey(kAXFocusedWindowChangedNotification, pid: 7, wid: 42), "wid-42-focus")
        XCTAssertEqual(AxEventRouting.dedupKey(kAXMainWindowChangedNotification, pid: 7, wid: 42), "wid-42-focus")
        XCTAssertEqual(AxEventRouting.dedupKey(kAXWindowResizedNotification, pid: 7, wid: 42), "wid-42-geometry")
        XCTAssertEqual(AxEventRouting.dedupKey(kAXWindowMovedNotification, pid: 7, wid: 42), "wid-42-geometry")
        XCTAssertEqual(AxEventRouting.dedupKey(kAXTitleChangedNotification, pid: 7, wid: 42), "wid-42-generic")
        XCTAssertEqual(AxEventRouting.dedupKey(kAXWindowCreatedNotification, pid: 7, wid: 42), "wid-42-generic")
    }

    func testAppDedupKeysSeparateActivationFromVisibility() {
        XCTAssertEqual(AxEventRouting.dedupKey(kAXApplicationActivatedNotification, pid: 7, wid: 0), "pid-7-activate")
        XCTAssertEqual(AxEventRouting.dedupKey(kAXApplicationHiddenNotification, pid: 7, wid: 0), "pid-7-visibility")
        XCTAssertEqual(AxEventRouting.dedupKey(kAXApplicationShownNotification, pid: 7, wid: 0), "pid-7-visibility")
    }

    func testActivationAndVisibilityNeverShareAKey() {
        let activate = AxEventRouting.dedupKey(kAXApplicationActivatedNotification, pid: 7, wid: 0)
        let hidden = AxEventRouting.dedupKey(kAXApplicationHiddenNotification, pid: 7, wid: 0)
        XCTAssertNotEqual(activate, hidden)
        // ...and neither collides with the bare manuallyUpdateWindows scan key "pid-7"
        XCTAssertNotEqual(activate, "pid-7")
        XCTAssertNotEqual(hidden, "pid-7")
    }

    func testFocusAndGeometryNeverShareAKey() {
        XCTAssertNotEqual(AxEventRouting.dedupKey(kAXFocusedWindowChangedNotification, pid: 7, wid: 42),
                          AxEventRouting.dedupKey(kAXWindowResizedNotification, pid: 7, wid: 42))
    }

    // MARK: - E. Use-case integration (deterministic routing of the discussed scenarios)

    func testUseCaseManualRefreshIsolatesOnScanPool() {
        // manuallyRefreshAllWindows → 60-app inventory: every call routes to the isolated scan pool
        for _ in 0..<60 {
            XCTAssertEqual(AxEventRouting.pool(unresponsive: false, scan: true), .scan)
        }
    }

    func testUseCaseRapidFocusSwitchIsFastAndUncoalesced() {
        for type in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            XCTAssertTrue(AxEventRouting.updatesFocusOrder(type))
            XCTAssertFalse(AxEventRouting.coalesces(type))
        }
    }

    func testUseCaseResizeDragCoalesces() {
        XCTAssertTrue(AxEventRouting.coalesces(kAXWindowResizedNotification))
        XCTAssertEqual(AxEventRouting.pool(unresponsive: false, scan: false), .firstTry)
    }

    func testUseCaseUnresponsiveAppQuarantines() {
        XCTAssertEqual(AxEventRouting.pool(unresponsive: true, scan: false), .retry)
        XCTAssertEqual(AxEventRouting.pool(unresponsive: true, scan: true), .retry)
    }
}
