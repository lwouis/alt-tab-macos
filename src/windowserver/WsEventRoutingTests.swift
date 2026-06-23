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
        XCTAssertEqual(WsEventRouting.action(for: .windowFocused), .bumpFocusOrder)
        XCTAssertEqual(WsEventRouting.action(for: .windowOrderedIn), .refreshVisibility)
        XCTAssertEqual(WsEventRouting.action(for: .windowOrderedOut), .refreshVisibility)
        XCTAssertEqual(WsEventRouting.action(for: .windowAddedToSpace), .updateSpaceMembership)
        XCTAssertEqual(WsEventRouting.action(for: .windowRemovedFromSpace), .updateSpaceMembership)
        XCTAssertEqual(WsEventRouting.action(for: .spaceCurrentChanged), .spaceTransition)
        XCTAssertEqual(WsEventRouting.action(for: .activeSpaceChanged), .spaceTransition)
    }

    // MARK: - C. Payload

    func testOnlySpaceMembershipNotificationsCarrySpaceId() {
        for n in WsEventRouting.Notification.allCases {
            let expected = (n == .windowAddedToSpace || n == .windowRemovedFromSpace)
            XCTAssertEqual(WsEventRouting.payloadCarriesSpaceId(n), expected, "\(n)")
        }
    }
}
