import XCTest

final class WindowEventReducerDiscoveryTests: XCTestCase {
    private func geometry(_ state: inout TrackedWindowState, _ now: TimeInterval, wid: CGWindowID = 7,
                          resized: Bool = false, transitioning: Bool = false) -> [ReducerEffect] {
        state.now = now
        return WindowEventReducer.reduce(&state, .windowMovedOrResized(wid: wid, resized: resized,
            inSpaceTransition: transitioning))
    }

    private func landed(_ state: inout TrackedWindowState, accepted: Bool) {
        _ = WindowEventReducer.reduce(&state, .discoveryLanded(wid: 7, accepted: accepted, newlyTracked: false,
            adoptedAsInactiveTab: false, spaceMembership: .unavailable, isOrderedIn: true, tabGroup: .unknown))
    }

    func testFrameByFrameRejectedPopupDiscoversOncePerSecond() {
        var state = TrackedWindowState()
        var discoveries = 0
        for frame in 0..<180 {
            discoveries += geometry(&state, Double(frame) / 60).filter { $0 == .discoverWindow(wid: 7) }.count
            landed(&state, accepted: false)
        }
        XCTAssertEqual(discoveries, 3)
    }

    func testInFlightDiscoveryAlsoCapsSubsequentMoves() {
        var state = TrackedWindowState()
        XCTAssertEqual(geometry(&state, 4), [.discoverWindow(wid: 7)])
        XCTAssertEqual(geometry(&state, 4.01), [])
        XCTAssertEqual(geometry(&state, 4.99), [])
        XCTAssertEqual(geometry(&state, 5), [.discoverWindow(wid: 7)])
    }

    func testZeroSizeCreationKeepsItsFirstMoveAndResizeDiscovery() {
        var state = TrackedWindowState()
        XCTAssertEqual(WindowEventReducer.reduce(&state, .windowCreated(wid: 7, now: 4,
            inSpaceTransition: false)), [.discoverWindow(wid: 7)])
        landed(&state, accepted: false)
        XCTAssertEqual(geometry(&state, 4.01), [.discoverWindow(wid: 7)])
        landed(&state, accepted: false)
        XCTAssertEqual(geometry(&state, 4.02, resized: true), [.discoverWindow(wid: 7)])
        XCTAssertEqual(geometry(&state, 4.03, resized: true), [.discoverWindow(wid: 7)])
        XCTAssertEqual(geometry(&state, 4.04), [.discoverWindow(wid: 7)])
    }

    func testFocusAndOrderInCanDiscoverChangedSemanticsDuringBackoff() {
        for input in [ReducerInput.windowFocused(wid: 7, now: 4.01),
                      .windowOrderedIn(wid: 7, now: 4.01, inSpaceTransition: false)] {
            var state = TrackedWindowState()
            _ = geometry(&state, 4)
            XCTAssertTrue(WindowEventReducer.reduce(&state, input).contains(.discoverWindow(wid: 7)))
            XCTAssertNil(state.carried.moveDiscoveryAt[7])
        }
    }

    func testLaterMoveCanDiscoverChangedSemanticsWithoutExplicitSignals() {
        var state = TrackedWindowState()
        _ = geometry(&state, 4)
        landed(&state, accepted: false)
        XCTAssertEqual(geometry(&state, 5.01), [.discoverWindow(wid: 7)])
    }

    func testAdmissionClearsTheMoveAttempt() {
        var state = TrackedWindowState()
        _ = geometry(&state, 4)
        landed(&state, accepted: true)
        XCTAssertNil(state.carried.moveDiscoveryAt[7])
    }

    func testTrackedGeometryIsNeverRateLimited() {
        var state = TrackedWindowState()
        state.windows = [TrackedWindow(id: "wid-7", wid: 7, pid: 42, title: "Document",
            size: CGSize(width: 300, height: 200), position: .zero,
            spaceIds: [1], spaceIndexes: [1], isOnAllSpaces: false, spaceIsBorrowed: false,
            isFullscreen: false, isFullscreenMirrored: false, isMinimized: false, isMainWindow: true,
            isWindowlessApp: false, cgsPhantomLatch: false, lastFocusOrder: 0,
            creationOrder: 0, hasThumbnail: true)]
        state.carried.moveDiscoveryAt[7] = 4
        for time in [4.01, 4.02, 4.03] {
            XCTAssertEqual(geometry(&state, time), [.queryWindowServerState(wids: [7])])
        }
    }

    func testDestroyAndCreateClearBackoffBeforeWindowIdReuse() {
        for input in [ReducerInput.windowDestroyed(wid: 7),
                      .windowCreated(wid: 7, now: 4.01, inSpaceTransition: false)] {
            var state = TrackedWindowState()
            _ = geometry(&state, 4)
            _ = WindowEventReducer.reduce(&state, input)
            XCTAssertNil(state.carried.moveDiscoveryAt[7])
            XCTAssertEqual(geometry(&state, 4.02), [.discoverWindow(wid: 7)])
        }
    }

    func testSpaceTransitionDoesNotSpendTheFirstMoveAfterSettling() {
        var state = TrackedWindowState()
        _ = geometry(&state, 4)
        _ = WindowEventReducer.reduce(&state, .spaceTransitionStarted)
        XCTAssertEqual(geometry(&state, 4.01, transitioning: true), [])
        XCTAssertTrue(state.carried.moveDiscoveryAt.isEmpty)
        _ = WindowEventReducer.reduce(&state, .spaceChangeSettled)
        XCTAssertEqual(geometry(&state, 4.02), [.discoverWindow(wid: 7)])
    }

    func testEachWindowHasItsOwnLeadingAttempt() {
        var state = TrackedWindowState()
        _ = geometry(&state, 4)
        XCTAssertEqual(geometry(&state, 4.01, wid: 8), [.discoverWindow(wid: 8)])
        XCTAssertEqual(geometry(&state, 4.02), [])
    }

    func testLazyExpirationAndHardCapBoundMissingDestroyEvents() {
        var state = TrackedWindowState()
        for wid: CGWindowID in 1...300 {
            _ = geometry(&state, Double(wid) / 1000, wid: wid)
            XCTAssertLessThanOrEqual(state.carried.moveDiscoveryAt.count, 256)
        }
        XCTAssertNil(state.carried.moveDiscoveryAt[1])
        XCTAssertNotNil(state.carried.moveDiscoveryAt[300])
        _ = geometry(&state, 2, wid: 301)
        XCTAssertEqual(state.carried.moveDiscoveryAt, [301: 2])
    }
}
