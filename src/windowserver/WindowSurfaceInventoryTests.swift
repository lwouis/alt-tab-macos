import XCTest

final class WindowSurfaceInventoryTests: XCTestCase {
    private func raw(_ wid: CGWindowID, pid: pid_t = 7, parent: CGWindowID = 0) -> WsRawWindow {
        WsRawWindow(wid: wid, pid: pid, attributes: 0, level: 0, spaceTypeMask: 0, title: "", parentWid: parent)
    }

    /// A snapshot issued and applied back to back, which is what every test that does not deliberately
    /// reorder the two wants.
    private func replace(_ rows: [WsRawWindow]) {
        WindowSurfaceInventory.replace(rows, issuedAt: WindowSurfaceInventory.beginSnapshot())
    }

    override func tearDown() {
        replace([])
    }

    func testChildAndSheetResolveToDocumentRoot() {
        replace([raw(1), raw(2, parent: 1), raw(3, parent: 2)])
        XCTAssertEqual(WindowSurfaceInventory.representativeWid(3), 1)
    }

    func testNativeTabRowsRemainIndependentRoots() {
        replace([raw(1), raw(2)])
        XCTAssertEqual(WindowSurfaceInventory.representativeWid(1), 1)
        XCTAssertEqual(WindowSurfaceInventory.representativeWid(2), 2)
    }

    func testCrossProcessAndMissingParentsAreNotFollowed() {
        replace([raw(1, pid: 7, parent: 2), raw(2, pid: 8)])
        XCTAssertEqual(WindowSurfaceInventory.representativeWid(1), 1)
        replace([raw(1, parent: 9)])
        XCTAssertEqual(WindowSurfaceInventory.representativeWid(1), 1)
    }

    func testCycleStopsWithoutLooping() {
        replace([raw(1, parent: 2), raw(2, parent: 1)])
        XCTAssertEqual(WindowSurfaceInventory.representativeWid(1), 2)
    }

    func testRemovingASurfaceDropsItsRelationship() {
        replace([raw(1), raw(2, parent: 1)])
        WindowSurfaceInventory.remove(2)
        XCTAssertEqual(WindowSurfaceInventory.representativeWid(2), 2)
    }

    func testLateFullSnapshotDoesNotEraseANewerTargetedUpsert() {
        let old = WindowSurfaceInventory.beginSnapshot()
        WindowSurfaceInventory.upsert([raw(2, parent: 1)])
        WindowSurfaceInventory.replace([raw(2)], issuedAt: old)
        XCTAssertEqual(WindowSurfaceInventory.raw(2)?.parentWid, 1)
    }

    func testLateFullSnapshotDoesNotResurrectANewerRemoval() {
        replace([raw(1)])
        let old = WindowSurfaceInventory.beginSnapshot()
        WindowSurfaceInventory.remove(1)
        WindowSurfaceInventory.replace([raw(1)], issuedAt: old)
        XCTAssertNil(WindowSurfaceInventory.raw(1))
    }

    func testLateFullSnapshotDoesNotRestoreAnExitedProcessMissingFromTheInventory() {
        let old = WindowSurfaceInventory.beginSnapshot()
        WindowSurfaceInventory.remove(pid: 7)
        WindowSurfaceInventory.replace([raw(1)], issuedAt: old)
        XCTAssertNil(WindowSurfaceInventory.raw(1))
    }

    func testOlderFullSnapshotCannotOverwriteANewerFullSnapshot() {
        let old = WindowSurfaceInventory.beginSnapshot()
        let new = WindowSurfaceInventory.beginSnapshot()
        WindowSurfaceInventory.replace([raw(2)], issuedAt: new)
        WindowSurfaceInventory.replace([raw(1)], issuedAt: old)
        XCTAssertNil(WindowSurfaceInventory.raw(1))
        XCTAssertNotNil(WindowSurfaceInventory.raw(2))
    }
}
