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

    func testDiscoveryParentChainStopsAtACycle() {
        let rows: [CGWindowID: WsRawWindow] = [1: raw(1, parent: 2), 2: raw(2, parent: 1)]
        let result = WindowParentChain.resolve(1) { rows[$0] }
        XCTAssertEqual(result.rows.map(\.wid), [1, 2])
        XCTAssertEqual(result.stop, .cycle)
    }

    func testDiscoveryParentChainStopsBeforeACrossProcessParent() {
        let rows: [CGWindowID: WsRawWindow] = [1: raw(1, pid: 7, parent: 2), 2: raw(2, pid: 8)]
        let result = WindowParentChain.resolve(1) { rows[$0] }
        XCTAssertEqual(result.rows.map(\.wid), [1])
        XCTAssertEqual(result.stop, .crossProcess)
    }

    func testDiscoveryParentChainKeepsRowsBeforeAMissingParent() {
        let rows: [CGWindowID: WsRawWindow] = [1: raw(1, parent: 2)]
        let result = WindowParentChain.resolve(1) { rows[$0] }
        XCTAssertEqual(result.rows.map(\.wid), [1])
        XCTAssertEqual(result.stop, .missing)
    }

    func testDiscoveryParentChainHasAHardDepthLimit() {
        let result = WindowParentChain.resolve(1) { wid in raw(wid, parent: wid + 1) }
        XCTAssertEqual(result.rows.count, WindowParentChain.maxDepth)
        XCTAssertEqual(result.stop, .depthLimit)
    }

    func testWindowQueryGuardCapsRowsAndRejectsDuplicatesOrForeignIds() {
        var guardrail = WindowQueryGuard([1, 2])
        XCTAssertTrue(guardrail.beginRow())
        XCTAssertTrue(guardrail.accepts(1))
        XCTAssertTrue(guardrail.beginRow())
        XCTAssertFalse(guardrail.accepts(1))
        XCTAssertFalse(guardrail.canReadAnotherRow)
        XCTAssertFalse(guardrail.beginRow())
        var foreign = WindowQueryGuard([1])
        XCTAssertTrue(foreign.beginRow())
        XCTAssertFalse(foreign.accepts(9))
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

    private func surface(_ wid: CGWindowID, _ bounds: CGRect, pid: pid_t = 7, parent: CGWindowID = 0,
                         visible: Bool = true) -> WsRawWindow {
        WsRawWindow(wid: wid, pid: pid, attributes: visible ? WsWindowState.visibleAttribute : 0, level: 0,
                    spaceTypeMask: 0, title: "", parentWid: parent, bounds: bounds)
    }

    private let textEditFrame = CGRect(x: 146, y: 72, width: 389, height: 188)

    /// The measured case: a small TextEdit window whose Save sheet hangs below it.
    func testSheetHangingPastTheWindowGrowsTheCaptureArea() {
        let sheet = surface(2, CGRect(x: 146, y: 140, width: 390, height: 218), parent: 1)
        XCTAssertEqual(CaptureArea.bounds(textEditFrame, 1, 7, [sheet]), CGRect(x: 146, y: 72, width: 390, height: 286))
    }

    func testSheetInsideTheWindowLeavesTheCaptureAreaAlone() {
        let sheet = surface(2, CGRect(x: 160, y: 100, width: 300, height: 120), parent: 1)
        XCTAssertEqual(CaptureArea.bounds(textEditFrame, 1, 7, [sheet]), textEditFrame)
    }

    func testOrderedOutSheetIsNotInTheCaptureArea() {
        let sheet = surface(2, CGRect(x: 146, y: 140, width: 390, height: 218), parent: 1, visible: false)
        XCTAssertEqual(CaptureArea.bounds(textEditFrame, 1, 7, [sheet]), textEditFrame)
    }

    func testChildOfAChildIsInTheCaptureArea() {
        let sheet = surface(2, CGRect(x: 146, y: 100, width: 389, height: 100), parent: 1)
        let nested = surface(3, CGRect(x: 146, y: 150, width: 389, height: 200), parent: 2)
        XCTAssertEqual(CaptureArea.bounds(textEditFrame, 1, 7, [nested, sheet]).maxY, 350)
    }

    func testOtherWindowsAndTheirChildrenAreNotInTheCaptureArea() {
        let otherWindow = surface(4, CGRect(x: 0, y: 0, width: 800, height: 600))
        let otherSheet = surface(5, CGRect(x: 0, y: 500, width: 800, height: 400), parent: 4)
        XCTAssertEqual(CaptureArea.bounds(textEditFrame, 1, 7, [otherWindow, otherSheet]), textEditFrame)
    }

    func testCrossProcessOrCyclicChainsAreNotInTheCaptureArea() {
        let foreign = surface(2, CGRect(x: 146, y: 100, width: 389, height: 500), pid: 8, parent: 1)
        let childOfForeign = surface(3, CGRect(x: 146, y: 150, width: 389, height: 500), parent: 2)
        let cycleA = surface(6, CGRect(x: 146, y: 150, width: 389, height: 500), parent: 7)
        let cycleB = surface(7, CGRect(x: 146, y: 150, width: 389, height: 500), parent: 6)
        XCTAssertEqual(CaptureArea.bounds(textEditFrame, 1, 7, [foreign, childOfForeign, cycleA, cycleB]), textEditFrame)
    }
}
