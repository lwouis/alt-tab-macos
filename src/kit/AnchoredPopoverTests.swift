import XCTest
import Cocoa

final class AnchoredPopoverTests: XCTestCase {
    private let rect = NSRect(x: 0, y: 0, width: 24, height: 24)

    private let screen = StatusItemAnchor.Screen(frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        notch: CGRect(x: 645.5, y: 924, width: 179, height: 32))
    private let placed = CGRect(x: 853, y: 923, width: 38, height: 33)

    private func readiness(isHidden: Bool = false, windowVisible: Bool = true, windowFrame: CGRect? = nil,
                           bounds: CGRect? = nil, visibleRect: CGRect? = nil, screens: [StatusItemAnchor.Screen]? = nil,
                           deadlinePassed: Bool = false) -> StatusItemAnchor.Readiness {
        StatusItemAnchor.readiness(isHidden: isHidden, windowVisible: windowVisible, windowFrame: windowFrame ?? placed,
            bounds: bounds ?? rect, visibleRect: visibleRect ?? rect, screens: screens ?? [screen], deadlinePassed: deadlinePassed)
    }

    func testAFrameAloneDoesNotMeanTheStatusItemCanHostAPopover() {
        XCTAssertEqual(readiness(windowVisible: false), .settling)
        XCTAssertEqual(readiness(windowFrame: .zero), .settling)
        XCTAssertEqual(readiness(bounds: .zero), .settling)
        XCTAssertEqual(readiness(visibleRect: .zero), .settling)
        XCTAssertEqual(readiness(visibleRect: rect.offsetBy(dx: 50, dy: 0)), .settling)
        XCTAssertEqual(readiness(), .ready)
    }

    /// Where macOS 27 keeps an item it has no room for, or one hidden with `isVisible = false`.
    func testAnItemParkedOffScreenIsNotAnAnchor() {
        let parked = CGRect(x: 0, y: -33, width: 38, height: 33)
        XCTAssertEqual(readiness(windowFrame: parked), .settling)
        XCTAssertEqual(readiness(windowFrame: parked, deadlinePassed: true), .unavailable)
    }

    /// An item switched off in System Settings before launch is never placed, and no layout event says so.
    func testAnItemNeverPlacedFallsBackOnceTheDeadlinePasses() {
        let unplaced = CGRect(x: 0, y: 0, width: 38, height: 0)
        XCTAssertEqual(readiness(windowFrame: unplaced), .settling)
        XCTAssertEqual(readiness(windowFrame: unplaced, deadlinePassed: true), .unavailable)
    }

    func testAnItemUnderTheNotchIsNotAnAnchor() {
        XCTAssertEqual(readiness(windowFrame: CGRect(x: 700, y: 923, width: 38, height: 33), deadlinePassed: true), .unavailable)
    }

    func testAnItemOutsideTheMenuBarIsNotAnAnchor() {
        XCTAssertEqual(readiness(windowFrame: CGRect(x: 853, y: 400, width: 38, height: 33), deadlinePassed: true), .unavailable)
        XCTAssertEqual(readiness(windowFrame: CGRect(x: -50, y: 923, width: 38, height: 33), deadlinePassed: true), .unavailable)
    }

    func testAnItemOnAnotherScreensMenuBarIsAnAnchor() {
        let second = StatusItemAnchor.Screen(frame: CGRect(x: 1470, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(readiness(windowFrame: CGRect(x: 3000, y: 1048, width: 38, height: 32), screens: [screen, second]), .ready)
    }

    /// Hidden by the user through AltTab's own setting: nothing to wait for.
    func testAHiddenItemIsUnavailableAtOnce() {
        XCTAssertEqual(readiness(isHidden: true), .unavailable)
    }

    func testAnUnavailableIconShowsTheContentWithoutAnchor() {
        let popover = TestPopover()
        let anchor = NSView()
        popover.readiness = .unavailable
        popover.present(NSView(), from: anchor)
        drainMainQueue()
        XCTAssertEqual(popover.showCount, 0)
        XCTAssertEqual(popover.unanchoredShowCount, 1)
        XCTAssertFalse(popover.isWaitingForAnchor)
        popover.close()
    }

    /// No layout event arrives for an item macOS never places: the deadline alone has to trigger the fallback.
    func testTheSettleDeadlineFallsBackWithoutAnotherEvent() {
        let popover = TestPopover()
        let anchor = NSView()
        popover.settleTimeout = 0.05
        popover.present(NSView(), from: anchor)
        drainMainQueue()
        XCTAssertEqual(popover.unanchoredShowCount, 0)
        let fellBack = expectation(description: "fell back after the deadline")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { fellBack.fulfill() }
        wait(for: [fellBack], timeout: 1)
        XCTAssertEqual(popover.showCount, 0)
        XCTAssertEqual(popover.unanchoredShowCount, 1)
        popover.close()
    }

    func testOnboardingWaitsForAUsableAnchorAndShowsOnceAfterLayout() {
        let popover = TestPopover()
        let anchor = NSView()
        popover.present(NSView(), from: anchor)
        drainMainQueue()
        XCTAssertEqual(popover.showCount, 0)
        XCTAssertTrue(popover.isWaitingForAnchor)
        popover.readiness = .ready
        NotificationCenter.default.post(name: NSApplication.didUpdateNotification, object: nil)
        drainMainQueue()
        XCTAssertEqual(popover.showCount, 1)
        XCTAssertFalse(popover.isWaitingForAnchor)
        NotificationCenter.default.post(name: NSApplication.didUpdateNotification, object: nil)
        drainMainQueue()
        XCTAssertEqual(popover.showCount, 1)
        popover.close()
    }

    func testAButtonLayoutChangeRetriesWithoutAnotherUserEvent() {
        let popover = TestPopover()
        let anchor = NSView()
        popover.present(NSView(), from: anchor)
        drainMainQueue()
        popover.readiness = .ready
        anchor.frame = rect
        drainMainQueue()
        XCTAssertEqual(popover.showCount, 1)
        popover.close()
    }

    func testARejectedNativeShowIsRetriedOnTheNextLayoutUpdate() {
        let popover = TestPopover()
        let anchor = NSView()
        popover.readiness = .ready
        popover.acceptsShow = false
        popover.present(NSView(), from: anchor)
        drainMainQueue()
        XCTAssertEqual(popover.showCount, 1)
        popover.acceptsShow = true
        NotificationCenter.default.post(name: NSApplication.didUpdateNotification, object: nil)
        drainMainQueue()
        XCTAssertEqual(popover.showCount, 2)
        popover.close()
    }

    func testSummoningTheSwitcherCancelsAQueuedLessonBeforeItCanTakeFocus() {
        let popover = TestPopover()
        let anchor = NSView()
        popover.readiness = .ready
        popover.present(NSView(), from: anchor)
        popover.cancelPresentation()
        NotificationCenter.default.post(name: NSApplication.didUpdateNotification, object: nil)
        drainMainQueue()
        XCTAssertEqual(popover.showCount, 0)
    }

    func testReplacingAnUnshownLessonOnlyPresentsTheLatestContent() {
        let popover = TestPopover()
        let anchor = NSView()
        let latest = NSView()
        popover.readiness = .ready
        popover.present(NSView(), from: anchor)
        popover.present(latest, from: anchor)
        drainMainQueue()
        XCTAssertEqual(popover.showCount, 1)
        XCTAssertTrue(popover.contentViewController?.view === latest)
        popover.close()
    }

    func testTheTrialAnnouncementIsConsumedOnlyAfterThePopoverAppears() {
        let popover = TestPopover()
        let anchor = NSView()
        var announcements = 0
        popover.readiness = .ready
        popover.present(NSView(), from: anchor, onShown: { announcements += 1 })
        NotificationCenter.default.post(name: NSPopover.didShowNotification, object: popover)
        XCTAssertEqual(announcements, 0, "An obsolete show notification must not consume the pending announcement")
        drainMainQueue()
        XCTAssertEqual(announcements, 0)
        NotificationCenter.default.post(name: NSPopover.didShowNotification, object: popover)
        NotificationCenter.default.post(name: NSPopover.didShowNotification, object: popover)
        XCTAssertEqual(announcements, 1)
        popover.close()
    }

    func testClosingAQueuedReminderPreventsItFromAppearingAfterPurchase() {
        let popover = TestPopover()
        let anchor = NSView()
        var announcements = 0
        popover.readiness = .ready
        popover.present(NSView(), from: anchor, onShown: { announcements += 1 })
        popover.close()
        drainMainQueue()
        NotificationCenter.default.post(name: NSPopover.didShowNotification, object: popover)
        XCTAssertEqual(popover.showCount, 0)
        XCTAssertEqual(announcements, 0)
        XCTAssertNil(popover.contentViewController)
    }

    func testClosingReleasesContentThatRetainsItsPopover() {
        let popover = TestPopover()
        let anchor = NSView()
        weak var released: RetainingView?
        popover.readiness = .ready
        autoreleasepool {
            let content = RetainingView()
            content.popover = popover
            released = content
            popover.present(content, from: anchor)
        }
        drainMainQueue()
        XCTAssertNotNil(released)
        popover.close()
        XCTAssertNil(released, "Closing must break the button-content-popover retention cycle")
    }

    func testTransientDismissalAlsoReleasesTheContent() {
        let popover = TestPopover()
        let anchor = NSView()
        popover.readiness = .ready
        popover.present(NSView(), from: anchor)
        drainMainQueue()
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: popover)
        XCTAssertNil(popover.contentViewController)
        NotificationCenter.default.post(name: NSApplication.didUpdateNotification, object: nil)
        drainMainQueue()
        XCTAssertEqual(popover.showCount, 1)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "pending presentation has run")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}

/// Native show/activation are the only replaced effects: these tests never display a window.
private final class TestPopover: AnchoredPopover {
    var readiness = StatusItemAnchor.Readiness.settling
    var acceptsShow = true
    var showCount = 0
    var unanchoredShowCount = 0
    override func readiness(of anchor: NSView, isHidden: Bool, deadlinePassed: Bool) -> StatusItemAnchor.Readiness {
        readiness == .settling && deadlinePassed ? .unavailable : readiness
    }
    override func showImmediately(from anchor: NSView) -> Bool {
        showCount += 1
        return acceptsShow
    }
    override func showUnanchored() -> Bool {
        unanchoredShowCount += 1
        return acceptsShow
    }
}

private final class RetainingView: NSView {
    var popover: AnchoredPopover?
}
