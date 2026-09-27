import XCTest
import Cocoa

final class AnchoredPopoverTests: XCTestCase {
    private let rect = NSRect(x: 0, y: 0, width: 24, height: 24)

    func testAFrameAloneDoesNotMeanTheStatusItemCanHostAPopover() {
        XCTAssertFalse(AnchoredPopover.anchorIsReady(windowVisible: false, windowFrame: rect, bounds: rect, visibleRect: rect))
        XCTAssertFalse(AnchoredPopover.anchorIsReady(windowVisible: true, windowFrame: .zero, bounds: rect, visibleRect: rect))
        XCTAssertFalse(AnchoredPopover.anchorIsReady(windowVisible: true, windowFrame: rect, bounds: .zero, visibleRect: rect))
        XCTAssertFalse(AnchoredPopover.anchorIsReady(windowVisible: true, windowFrame: rect, bounds: rect, visibleRect: .zero))
        XCTAssertFalse(AnchoredPopover.anchorIsReady(windowVisible: true, windowFrame: rect, bounds: rect, visibleRect: rect.offsetBy(dx: 50, dy: 0)))
        XCTAssertTrue(AnchoredPopover.anchorIsReady(windowVisible: true, windowFrame: rect, bounds: rect, visibleRect: rect))
    }

    func testOnboardingWaitsForAUsableAnchorAndShowsOnceAfterLayout() {
        let popover = TestPopover()
        let anchor = NSView()
        popover.present(NSView(), from: anchor)
        drainMainQueue()
        XCTAssertEqual(popover.showCount, 0)
        XCTAssertTrue(popover.isWaitingForAnchor)
        popover.ready = true
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
        popover.ready = true
        anchor.frame = rect
        drainMainQueue()
        XCTAssertEqual(popover.showCount, 1)
        popover.close()
    }

    func testARejectedNativeShowIsRetriedOnTheNextLayoutUpdate() {
        let popover = TestPopover()
        let anchor = NSView()
        popover.ready = true
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
        popover.ready = true
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
        popover.ready = true
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
        popover.ready = true
        popover.present(NSView(), from: anchor) { announcements += 1 }
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
        popover.ready = true
        popover.present(NSView(), from: anchor) { announcements += 1 }
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
        popover.ready = true
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
        popover.ready = true
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
    var ready = false
    var acceptsShow = true
    var showCount = 0
    override func canShow(from anchor: NSView) -> Bool { ready }
    override func showImmediately(from anchor: NSView) -> Bool {
        showCount += 1
        return acceptsShow
    }
}

private final class RetainingView: NSView {
    var popover: AnchoredPopover?
}
