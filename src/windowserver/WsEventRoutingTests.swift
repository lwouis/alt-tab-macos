import XCTest

/// Pins the WindowServer notification id→action map established empirically on macOS 26. A future macOS
/// that renumbers these, or a refactor that drops a case, fails here.
final class WsEventRoutingTests: XCTestCase {

    // MARK: - A. Notification decoding

    func testKnownIdsDecode() {
        XCTAssertEqual(WsEventRouting.notification(811), .windowCreated)
        XCTAssertEqual(WsEventRouting.notification(804), .windowDestroyed)
        XCTAssertEqual(WsEventRouting.notification(806), .windowMoved)
        XCTAssertEqual(WsEventRouting.notification(807), .windowResized)
        XCTAssertEqual(WsEventRouting.notification(815), .windowOrderedIn)
        XCTAssertEqual(WsEventRouting.notification(816), .windowOrderedOut)
        XCTAssertEqual(WsEventRouting.notification(808), .windowFocused)
        XCTAssertEqual(WsEventRouting.notification(1325), .windowAddedToSpace)
        XCTAssertEqual(WsEventRouting.notification(1326), .windowRemovedFromSpace)
        XCTAssertEqual(WsEventRouting.notification(1329), .spaceCurrentChanged)
        XCTAssertEqual(WsEventRouting.notification(1401), .activeSpaceChanged)
    }

    func testUnknownIdsAreNil() {
        for raw: UInt32 in [0, 999, 1322, 1502, 1503] { // 1502/1503 are heartbeats, 1322 a list-changed pulse
            XCTAssertNil(WsEventRouting.notification(raw), "\(raw) is not an actionable window notification")
        }
    }

    // MARK: - B. Action mapping

    func testActionForEachNotification() {
        XCTAssertEqual(WsEventRouting.action(for: .windowCreated), .acquireAndDiscriminate)
        XCTAssertEqual(WsEventRouting.action(for: .windowDestroyed), .remove)
        XCTAssertEqual(WsEventRouting.action(for: .windowMoved), .updateGeometry)
        XCTAssertEqual(WsEventRouting.action(for: .windowResized), .updateGeometry)
        XCTAssertEqual(WsEventRouting.action(for: .windowFocused), .noteFocusEvent)
        XCTAssertEqual(WsEventRouting.action(for: .windowOrderedIn), .refreshVisibility)
        XCTAssertEqual(WsEventRouting.action(for: .windowOrderedOut), .refreshVisibility)
        XCTAssertEqual(WsEventRouting.action(for: .windowAddedToSpace), .updateSpaceMembership)
        XCTAssertEqual(WsEventRouting.action(for: .windowRemovedFromSpace), .updateSpaceMembership)
        XCTAssertEqual(WsEventRouting.action(for: .spaceCurrentChanged), .spaceTransition)
        XCTAssertEqual(WsEventRouting.action(for: .activeSpaceChanged), .spaceTransition)
    }

    // MARK: - C. Ingress coalescing

    func testGeometryBurstKeepsOnlyTheLatestEventPerWindow() {
        var ingress = WsEventIngress()
        ingress.append(event(.windowMoved, wid: 7, at: 1))
        ingress.append(event(.windowResized, wid: 7, at: 2))
        ingress.append(event(.windowMoved, wid: 8, at: 3))
        let drain = ingress.drain()
        XCTAssertEqual(drain.events, [event(.windowResized, wid: 7, at: 2), event(.windowMoved, wid: 8, at: 3)])
        XCTAssertEqual(drain.coalescedGeometryEvents, 1)
    }

    func testSemanticEdgePreventsGeometryFromCrossingIt() {
        var ingress = WsEventIngress()
        ingress.append(event(.windowMoved, wid: 7, at: 1))
        ingress.append(event(.windowFocused, wid: 7, at: 2))
        ingress.append(event(.windowResized, wid: 7, at: 3))
        XCTAssertEqual(ingress.drain().events, [
            event(.windowMoved, wid: 7, at: 1), event(.windowFocused, wid: 7, at: 2),
            event(.windowResized, wid: 7, at: 3)
        ])
    }

    func testDrainResetsTheCoalescingSegment() {
        var ingress = WsEventIngress()
        ingress.append(event(.windowMoved, wid: 7, at: 1))
        _ = ingress.drain()
        ingress.append(event(.windowResized, wid: 7, at: 2))
        let drain = ingress.drain()
        XCTAssertEqual(drain.events, [event(.windowResized, wid: 7, at: 2)])
        XCTAssertEqual(drain.coalescedGeometryEvents, 0)
    }

    private func event(_ notification: WsEventRouting.Notification, wid: UInt32, at: TimeInterval) -> WsEventIngress.Event {
        WsEventIngress.Event(notification: notification, w0: wid, space: 0, widInSpace: 0, at: at)
    }
}
