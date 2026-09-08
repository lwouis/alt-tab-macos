import Foundation

/// The switcher's grid, as arithmetic. Tiles of a fixed height and their own widths are laid left to right
/// (or right to left) until the next one would cross `widthMax`, then a new row starts. `TilesView` owns the
/// AppKit half — measuring a tile, assigning a frame, sizing the panel — and this owns the placement, so the
/// wrapping, the totals the panel is sized from, and the row centering can be pinned by unit tests at any
/// width, any tile size and either writing direction.
///
/// Coordinates are the document view's: y grows downward (`FlippedView`), origin at the top-left in LTR and
/// at the top-right in RTL.
enum TileGridLayout {
    struct Input {
        var widths: [CGFloat]
        var tileHeight: CGFloat
        var widthMax: CGFloat
        var padding: CGFloat
        var isLeftToRight: Bool

        init(widths: [CGFloat], tileHeight: CGFloat, widthMax: CGFloat, padding: CGFloat, isLeftToRight: Bool = true) {
            self.widths = widths
            self.tileHeight = tileHeight
            self.widthMax = widthMax
            self.padding = padding
            self.isLeftToRight = isLeftToRight
        }
    }

    struct Result: Equatable {
        /// One per input width, in the same order.
        var origins: [CGPoint]
        /// Input indexes, grouped by row. Always holds at least one row, empty input included.
        var rows: [[Int]]
        /// What the panel is sized from: the far edge of the widest run of tiles, and the bottom of the
        /// last row. Both include the padding that follows the tile.
        var maxX: CGFloat
        var maxY: CGFloat
    }

    static func compute(_ input: Input) -> Result {
        let startingX = input.isLeftToRight ? input.padding : input.widthMax - input.padding
        var currentX = startingX
        var currentY = input.padding
        var maxX = CGFloat(0)
        var maxY = currentY + input.tileHeight + input.padding
        var origins = [CGPoint]()
        var rows = [[Int]]()
        rows.append([Int]())
        for (index, width) in input.widths.enumerated() {
            let nextX = projectedX(currentX, width, input).rounded(.down)
            if needsNewRow(nextX, input) {
                currentX = startingX
                currentY = (currentY + input.tileHeight + input.padding).rounded(.down)
                origins.append(CGPoint(x: originX(currentX, width, input), y: currentY))
                currentX = projectedX(currentX, width, input).rounded(.down)
                maxY = max(currentY + input.tileHeight + input.padding, maxY)
                rows.append([Int]())
            } else {
                origins.append(CGPoint(x: originX(currentX, width, input), y: currentY))
                currentX = nextX
                // Deliberately not updated on the branch above: a tile that OPENS a row does not widen the
                // grid. Row 1 always fills to within one tile of `widthMax` before it wraps, so no later row
                // can be wider than what row 1 already recorded — except when the very first tile is wider
                // than `widthMax` on its own, which wraps immediately and leaves `maxX` at 0.
                // `TileGridLayoutTests.testSingleTileWiderThanTheGrid` pins that case.
                maxX = max(input.isLeftToRight ? currentX : input.widthMax - currentX, maxX)
            }
            rows[rows.count - 1].append(index)
        }
        return Result(origins: origins, rows: rows, maxX: maxX, maxY: maxY)
    }

    /// How far each row has to move along the writing direction to sit centered in `within`. Zero for a row
    /// that is already at least that wide, so a full row is never pulled backwards off the edge.
    static func centeringOffsets(rowWidths: [[CGFloat]], padding: CGFloat, within: CGFloat) -> [CGFloat] {
        rowWidths.map { row in
            guard !row.isEmpty else { return 0 }
            let rowWidth = padding + row.reduce(CGFloat(0)) { $0 + $1 + padding }
            return max(0, ((within - rowWidth) / 2).rounded())
        }
    }

    /// The auto size: the first candidate whose grid fits in `heightMax`, and the last candidate when none
    /// do. `measure` is called once for every candidate up to and including the chosen one, in order — the
    /// production caller applies the size to `Appearance` inside it before laying the grid out, so the
    /// appearance is left on the size this returns.
    static func firstSizeThatFits<Size>(_ candidates: [Size], heightMax: CGFloat, measure: (Size) -> CGFloat) -> Size? {
        for (position, candidate) in candidates.enumerated() {
            if measure(candidate) <= heightMax || position == candidates.count - 1 { return candidate }
        }
        return nil
    }

    private static func needsNewRow(_ projectedX: CGFloat, _ input: Input) -> Bool {
        input.isLeftToRight ? projectedX > input.widthMax : projectedX < 0
    }

    private static func projectedX(_ currentX: CGFloat, _ width: CGFloat, _ input: Input) -> CGFloat {
        input.isLeftToRight ? currentX + width + input.padding : currentX - width - input.padding
    }

    /// In RTL `currentX` is the tile's trailing edge, so the frame's origin is one width before it.
    private static func originX(_ currentX: CGFloat, _ width: CGFloat, _ input: Input) -> CGFloat {
        input.isLeftToRight ? currentX : currentX - width
    }
}
