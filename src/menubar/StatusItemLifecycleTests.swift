import XCTest

final class StatusItemLifecycleTests: XCTestCase {
    func testHiddenLaunchNeverCreatesAStatusItem() {
        let harness = StatusItemHarness()
        harness.lifecycle.setVisible(false)
        harness.lifecycle.setVisible(false)
        XCTAssertNil(harness.lifecycle.item)
        XCTAssertTrue(harness.events.isEmpty)
    }

    func testVisibleItemIsConfiguredBeforeObservingRemovalAndReusedForUpdates() {
        let harness = StatusItemHarness()
        harness.lifecycle.setVisible(true)
        let item = harness.lifecycle.item
        harness.icon = 2
        harness.badge = true
        harness.lifecycle.setVisible(true)
        XCTAssertTrue(harness.lifecycle.item === item)
        XCTAssertEqual(item?.icon, 2)
        XCTAssertEqual(item?.badge, true)
        XCTAssertEqual(harness.events, ["create", "update", "observe", "update"])
    }

    func testHidingInvalidatesObservationBeforeNativeRemovalAndReleasesTheItem() {
        let harness = StatusItemHarness()
        weak var item: TestStatusItem?
        autoreleasepool {
            harness.lifecycle.setVisible(true)
            item = harness.lifecycle.item
            harness.lifecycle.setVisible(false)
        }
        XCTAssertNil(harness.lifecycle.item)
        XCTAssertNil(item)
        XCTAssertNil(harness.onRemoval)
        XCTAssertEqual(harness.events, ["create", "update", "observe", "stop", "remove"])
        XCTAssertEqual(harness.userRemovals, 0)
        harness.lifecycle.setVisible(false)
        XCTAssertEqual(harness.events.filter { $0 == "remove" }.count, 1)
    }

    func testRepeatedHideShowRecreatesWithCurrentIconAndBadge() {
        let harness = StatusItemHarness()
        for icon in 0..<5 {
            harness.icon = icon
            harness.badge = icon % 2 == 0
            harness.lifecycle.setVisible(true)
            XCTAssertEqual(harness.lifecycle.item?.icon, icon)
            XCTAssertEqual(harness.lifecycle.item?.badge, harness.badge)
            harness.lifecycle.setVisible(false)
            XCTAssertNil(harness.lifecycle.item)
        }
        XCTAssertEqual(harness.events.filter { $0 == "create" }.count, 5)
        XCTAssertEqual(harness.events.filter { $0 == "remove" }.count, 5)
    }

    func testCommandDragLeavesKvoBeforeRemovingAndPersistsOnlyOnce() {
        let harness = StatusItemHarness()
        harness.lifecycle.setVisible(true)
        harness.onRemoval?()
        harness.onRemoval?()
        XCTAssertNotNil(harness.lifecycle.item)
        XCTAssertEqual(harness.userRemovals, 0)
        drainMainQueue()
        XCTAssertNil(harness.lifecycle.item)
        XCTAssertEqual(harness.userRemovals, 1)
        XCTAssertEqual(harness.events.suffix(2), ["stop", "remove"])
    }

    func testShowingAgainCancelsQueuedCommandDragRemoval() {
        let harness = StatusItemHarness()
        harness.lifecycle.setVisible(true)
        let item = harness.lifecycle.item
        harness.onRemoval?()
        harness.lifecycle.setVisible(true)
        drainMainQueue()
        XCTAssertTrue(harness.lifecycle.item === item)
        XCTAssertEqual(harness.userRemovals, 0)
    }

    func testOldObservationCannotRemoveAReplacementItem() {
        let harness = StatusItemHarness()
        harness.lifecycle.setVisible(true)
        let oldItem = harness.lifecycle.item
        let oldObservation = harness.onRemoval
        harness.onRemoval?()
        harness.lifecycle.setVisible(false)
        harness.lifecycle.setVisible(true)
        oldObservation?()
        drainMainQueue()
        XCTAssertNotNil(harness.lifecycle.item)
        XCTAssertFalse(harness.lifecycle.item === oldItem)
        XCTAssertEqual(harness.userRemovals, 0)
        harness.onRemoval?()
        drainMainQueue()
        XCTAssertNil(harness.lifecycle.item)
        XCTAssertEqual(harness.userRemovals, 1)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "queued status-item removal completed")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}

private final class TestStatusItem {
    var icon = 0
    var badge = false
}

private final class StatusItemHarness {
    var events = [String]()
    var onRemoval: (() -> Void)?
    var icon = 0
    var badge = false
    var userRemovals = 0
    lazy var lifecycle: StatusItemLifecycle<TestStatusItem> = StatusItemLifecycle(create: { [unowned self] in
        self.events.append("create")
        return TestStatusItem()
    }, update: { [unowned self] item in
        self.events.append("update")
        item.icon = self.icon
        item.badge = self.badge
    }, observeRemoval: { [unowned self] _, onRemoval in
        self.events.append("observe")
        self.onRemoval = onRemoval
        return { [unowned self] in
            self.events.append("stop")
            self.onRemoval = nil
        }
    }, remove: { [unowned self] _ in
        XCTAssertNil(self.lifecycle.item)
        XCTAssertNil(self.onRemoval)
        self.events.append("remove")
    }, onUserRemoval: { [unowned self] in
        self.userRemovals += 1
    })
}
