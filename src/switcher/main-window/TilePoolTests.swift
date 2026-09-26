import XCTest

/// Pins when the switcher builds tiles. A tile built before launch applies the real appearance keeps the
/// placeholder one (red shadows, a title clipped to the height of a 3pt line), so the rule under test is:
/// nothing is built before the switcher UI, and the UI's first pool covers every window discovered before it.
///
/// Groups: A before the UI · B the first pool · C growth · D a replayed launch.
final class TilePoolTests: XCTestCase {
    // MARK: - A. Before the UI

    func testNoTileIsBuiltBeforeTheSwitcherUi() {
        for windowCount in [1, 2, 20, 35] {
            XCTAssertEqual(TilePool.tilesToAdd(poolSize: 0, windowCount: windowCount, uiIsBuilt: false), 0)
        }
    }

    // MARK: - B. The first pool

    func testFirstPoolHoldsTheMinimumWhenFewWindowsAreKnown() {
        XCTAssertEqual(TilePool.tilesToAdd(poolSize: 0, windowCount: 0, uiIsBuilt: true), TilePool.minimumSize)
        XCTAssertEqual(TilePool.tilesToAdd(poolSize: 0, windowCount: 2, uiIsBuilt: true), TilePool.minimumSize)
    }

    func testFirstPoolCoversWindowsDiscoveredBeforeIt() {
        XCTAssertEqual(TilePool.tilesToAdd(poolSize: 0, windowCount: 35, uiIsBuilt: true), 35)
    }

    // MARK: - C. Growth

    func testPoolGrowsOneTileForEachWindowPastIt() {
        XCTAssertEqual(TilePool.tilesToAdd(poolSize: 20, windowCount: 21, uiIsBuilt: true), 1)
    }

    func testPoolThatCoversTheListAddsNothing() {
        XCTAssertEqual(TilePool.tilesToAdd(poolSize: 20, windowCount: 20, uiIsBuilt: true), 0)
    }

    func testPoolNeverShrinks() {
        XCTAssertEqual(TilePool.tilesToAdd(poolSize: 40, windowCount: 3, uiIsBuilt: true), 0)
    }

    // MARK: - D. A replayed launch

    /// The screenshot's case: windows arrive while the permission check runs, then the UI is built, then
    /// more windows arrive. Each tile records whether the UI existed when it was built.
    func testReplayedLaunchBuildsEveryTileAfterTheUi() {
        var tilesBuiltWithUi = [Bool]()
        var windowCount = 0
        var uiIsBuilt = false
        func grow() {
            let count = TilePool.tilesToAdd(poolSize: tilesBuiltWithUi.count, windowCount: windowCount, uiIsBuilt: uiIsBuilt)
            tilesBuiltWithUi += Array(repeating: uiIsBuilt, count: count)
        }
        (1...2).forEach { _ in windowCount += 1; grow() }
        uiIsBuilt = true
        grow()
        (1...25).forEach { _ in windowCount += 1; grow() }
        XCTAssertFalse(tilesBuiltWithUi.contains(false))
        XCTAssertEqual(tilesBuiltWithUi.count, 27)
    }
}
