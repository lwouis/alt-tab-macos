import XCTest

/// Pins the switcher's grid arithmetic: where each tile goes, when a row wraps, the two totals the panel is
/// sized from, how a short row is centered, and which appearance size **auto** settles on. Pure numbers in,
/// numbers out — no AppKit, no screen, no `Appearance`.
///
/// Groups: A one row · B wrapping · C right-to-left · D tile size (the shape of #6010) · E centering ·
/// F the auto size.
final class TileGridLayoutTests: XCTestCase {
    private let padding = CGFloat(5)
    private let tileHeight = CGFloat(100)

    private func layout(_ widths: [CGFloat], widthMax: CGFloat, tileHeight: CGFloat? = nil,
                        isLeftToRight: Bool = true) -> TileGridLayout.Result {
        TileGridLayout.compute(TileGridLayout.Input(widths: widths, tileHeight: tileHeight ?? self.tileHeight,
            widthMax: widthMax, padding: padding, isLeftToRight: isLeftToRight))
    }

    // MARK: - A. One row

    func testTilesAdvanceByTheirOwnWidthPlusPadding() {
        let result = layout([40, 40], widthMax: 100)
        XCTAssertEqual(result.origins, [CGPoint(x: 5, y: 5), CGPoint(x: 50, y: 5)])
        XCTAssertEqual(result.rows, [[0, 1]])
        XCTAssertEqual(result.maxX, 95)
        XCTAssertEqual(result.maxY, 110)
    }

    func testEmptyGridStillReservesOneRow() {
        let result = layout([], widthMax: 100)
        XCTAssertEqual(result.origins, [])
        XCTAssertEqual(result.rows, [[]])
        XCTAssertEqual(result.maxX, 0)
        XCTAssertEqual(result.maxY, 110)
    }

    func testSingleTileFillsTheGridExactly() {
        let result = layout([90], widthMax: 100)
        XCTAssertEqual(result.rows, [[0]])
        XCTAssertEqual(result.maxX, 100)
    }

    // MARK: - B. Wrapping

    func testATileThatWouldCrossTheEdgeStartsANewRow() {
        let result = layout([40, 40, 40], widthMax: 100)
        XCTAssertEqual(result.origins, [CGPoint(x: 5, y: 5), CGPoint(x: 50, y: 5), CGPoint(x: 5, y: 110)])
        XCTAssertEqual(result.rows, [[0, 1], [2]])
        XCTAssertEqual(result.maxX, 95)
        XCTAssertEqual(result.maxY, 215)
    }

    func testEachRowIsOneTileHeightPlusPaddingBelowTheLast() {
        let result = layout([90, 90, 90, 90], widthMax: 100)
        XCTAssertEqual(result.origins.map { $0.y }, [5, 110, 215, 320])
        XCTAssertEqual(result.rows, [[0], [1], [2], [3]])
        XCTAssertEqual(result.maxY, 425)
    }

    func testSingleTileWiderThanTheGrid() {
        let result = layout([200], widthMax: 100)
        XCTAssertEqual(result.rows, [[], [0]])
        XCTAssertEqual(result.origins, [CGPoint(x: 5, y: 110)])
        XCTAssertEqual(result.maxX, 0)
    }

    // MARK: - C. Right to left

    func testRtlPlacesTilesFromTheRightEdge() {
        let result = layout([40, 40, 40], widthMax: 100, isLeftToRight: false)
        XCTAssertEqual(result.origins, [CGPoint(x: 55, y: 5), CGPoint(x: 10, y: 5), CGPoint(x: 55, y: 110)])
        XCTAssertEqual(result.rows, [[0, 1], [2]])
        XCTAssertEqual(result.maxX, 95)
        XCTAssertEqual(result.maxY, 215)
    }

    func testRtlWrapsWhenTheLeadingEdgeWouldPassZero() {
        let result = layout([90], widthMax: 100, isLeftToRight: false)
        XCTAssertEqual(result.rows, [[0]])
        XCTAssertEqual(result.origins, [CGPoint(x: 5, y: 5)])
    }

    // MARK: - D. Tile size (the shape of #6010)

    /// A three-line title added two line heights (38pt at the medium appearance) to `labelHeight`, and
    /// `TileView.height` adds `labelHeight` straight into the tile. Every row below the first moved down by
    /// that much, for every window — which is what the report describes as the grid breaking.
    func testATallerTileMovesEveryRowDownByTheDifference() {
        let normal = layout([40, 40, 40], widthMax: 100)
        let inflated = layout([40, 40, 40], widthMax: 100, tileHeight: tileHeight + 38)
        XCTAssertEqual(inflated.origins[2].y - normal.origins[2].y, 38)
        XCTAssertEqual(inflated.maxY - normal.maxY, 76)
        XCTAssertEqual(inflated.rows, normal.rows)
    }

    func testANarrowerGridWrapsSooner() {
        let widths = [40, 40, 40] as [CGFloat]
        XCTAssertEqual(layout(widths, widthMax: 140).rows.count, 1)
        XCTAssertEqual(layout(widths, widthMax: 100).rows.count, 2)
        XCTAssertEqual(layout(widths, widthMax: 50).rows.count, 3)
    }

    func testWiderTilesFitFewerPerRow() {
        XCTAssertEqual(layout([20, 20, 20, 20], widthMax: 120).rows, [[0, 1, 2, 3]])
        XCTAssertEqual(layout([45, 45, 45, 45], widthMax: 120).rows, [[0, 1], [2, 3]])
    }

    // MARK: - E. Centering

    func testAFullRowIsNotMoved() {
        let offsets = TileGridLayout.centeringOffsets(rowWidths: [[40, 40]], padding: padding, within: 95)
        XCTAssertEqual(offsets, [0])
    }

    func testAShortRowIsCentered() {
        let offsets = TileGridLayout.centeringOffsets(rowWidths: [[40, 40], [40]], padding: padding, within: 95)
        XCTAssertEqual(offsets, [0, 23])
    }

    func testAnEmptyRowGetsNoOffset() {
        let offsets = TileGridLayout.centeringOffsets(rowWidths: [[], [40]], padding: padding, within: 95)
        XCTAssertEqual(offsets, [0, 23])
    }

    func testARowWiderThanTheSpaceIsNotPulledBack() {
        let offsets = TileGridLayout.centeringOffsets(rowWidths: [[400]], padding: padding, within: 95)
        XCTAssertEqual(offsets, [0])
    }

    // MARK: - F. The auto size

    func testAutoTakesTheFirstSizeThatFits() {
        let heights: [String: CGFloat] = ["large": 200, "medium": 100, "small": 50]
        let picked = TileGridLayout.firstSizeThatFits(["large", "medium", "small"], heightMax: 300) { heights[$0]! }
        XCTAssertEqual(picked, "large")
    }

    func testAutoFallsThroughToTheNextSize() {
        let heights: [String: CGFloat] = ["large": 200, "medium": 100, "small": 50]
        var measured = [String]()
        let picked = TileGridLayout.firstSizeThatFits(["large", "medium", "small"], heightMax: 150) {
            measured.append($0)
            return heights[$0]!
        }
        XCTAssertEqual(picked, "medium")
        XCTAssertEqual(measured, ["large", "medium"])
    }

    func testAutoKeepsTheSmallestWhenNothingFits() {
        let heights: [String: CGFloat] = ["large": 200, "medium": 100, "small": 50]
        let picked = TileGridLayout.firstSizeThatFits(["large", "medium", "small"], heightMax: 10) { heights[$0]! }
        XCTAssertEqual(picked, "small")
    }

    /// In production the measurement applies the size to `Appearance` before laying the grid out, so the
    /// appearance is left on whatever was measured last. It must be the size that is returned.
    func testAutoMeasuresEachCandidateExactlyOnce() {
        var measured = [String]()
        let picked = TileGridLayout.firstSizeThatFits(["large", "medium", "small"], heightMax: 10) {
            measured.append($0)
            return 999
        }
        XCTAssertEqual(measured, ["large", "medium", "small"])
        XCTAssertEqual(picked, measured.last)
    }
}
