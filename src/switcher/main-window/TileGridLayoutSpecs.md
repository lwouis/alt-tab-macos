# TileGridLayout — Specs

## Summary

The switcher draws its windows as a grid of tiles inside a scroll view. Every tile is the same height and
has its own width (a thumbnail's aspect ratio in **thumbnails** style, the icon plus the title in **titles**,
the icon alone in **appIcons**), and they are placed along the writing direction until the next one would
cross the panel's maximum width, at which point a new row starts.

`TileGridLayout` is that placement as arithmetic, extracted from `TilesView`. `TilesView` keeps the AppKit
half — measuring a tile by filling it, assigning frames, sizing the panel and the document view — and this
owns the decisions: where each tile goes, which row it lands on, the two totals the panel is sized from, how
much each row moves to be centered, and which appearance size the **auto** setting settles on.

The point of the split is that the grid can now be pinned at any width, any tile size, either writing
direction and any number of tiles, without a screen. Before it, every layout question had to be answered by
looking at a running switcher, which is why #6010 (a multi-line window title inflating the label height and
so every tile's height) shipped in every version from 10 onwards.

### Coordinates

The document view is flipped, so **y grows downward**. In LTR the origin is the top-left and tiles advance
to the right; in RTL the origin is the top-right, `currentX` tracks the tile's *trailing* edge, and the
frame's origin is one tile width before it.

## Behavior & edge cases

- **A tile wraps when its far edge would pass `widthMax`**, measured with the padding that follows it. Both
  the projection and the row's y are floored, matching what shipped: a half-pixel of accumulated rounding
  must not push a row that fits onto the next one.
- **`maxY` always counts at least one row**, even with no tiles at all, because the panel reserves a row's
  height before it knows what is in it.
- **`maxX` is not updated by a tile that opens a row.** Row 1 always fills to within one tile of `widthMax`
  before it wraps, so a later row cannot be wider than what row 1 already recorded — and the panel is sized
  from `maxX`. The exception is a single tile wider than the whole grid: it wraps on the first step and
  leaves `maxX` at 0. Pinned rather than fixed, because it is what shipped and the panel has its own minimum
  width for that case.
- **`rows` always holds at least one row**, and a first tile that is wider than the grid leaves row 0 empty
  (it wraps before it is placed). `TilesView.centerRows` and `TilesView.nextRow` both skip empty rows.
- **A row is centered only when it is narrower than the space it is given.** A full row's offset is zero,
  never negative, so no row is ever pulled backwards off the edge. Half-pixels round away from zero
  (`(22.5).rounded() == 23`), the same as the shipped code.
- **Centering is measured against a width the caller chooses** (`TilesView` passes the panel's final
  `thumbnailsWidth`, not the grid's `maxX`), so the last row of a short list sits under the middle of the
  panel rather than under the middle of the tiles.
- **The auto size takes the first that fits, and the last one regardless.** `firstSizeThatFits` walks
  large → medium → small and stops at the first whose grid is no taller than the space available; if none
  fit, the smallest is used anyway. The measurement is a closure because the production caller has to apply
  the size to `Appearance` before it can measure it — which means the appearance is left on the size that is
  returned, and the closure is called once per candidate up to and including that one.

---

## Test scenarios

Mirrors `TileGridLayoutTests.swift` 1:1.

### A. One row
- **testTilesAdvanceByTheirOwnWidthPlusPadding** — three tiles that fit sit on one row, each one width and
  one padding after the last; `rows` is a single row and `maxY` is one row tall.
- **testEmptyGridStillReservesOneRow** — no tiles → no origins, one empty row, `maxX` 0, `maxY` one row tall.
- **testSingleTileFillsTheGridExactly** — a tile whose far edge lands exactly on `widthMax` does not wrap.

### B. Wrapping
- **testATileThatWouldCrossTheEdgeStartsANewRow** — the third of three 40pt tiles in a 100pt grid drops to
  row 1 at the starting x, and `maxY` grows by one row.
- **testEachRowIsOneTileHeightPlusPaddingBelowTheLast** — four rows of one tile each are evenly spaced.
- **testSingleTileWiderThanTheGrid** — one 200pt tile in a 100pt grid wraps immediately: row 0 is left
  empty, the tile is on row 1, and `maxX` stays 0.

### C. Right to left
- **testRtlPlacesTilesFromTheRightEdge** — the same three tiles mirrored: origins measured from `widthMax`,
  same rows, same `maxX` and `maxY` as the LTR case.
- **testRtlWrapsWhenTheLeadingEdgeWouldPassZero** — the wrap test is the left edge, not the right.

### D. Tile size (the shape of #6010)
- **testATallerTileMovesEveryRowDownByTheDifference** — the grid is a pure function of `tileHeight`: adding
  38pt to it (the two extra line heights a three-line title added to `labelHeight`) moves row 1 down by
  exactly 38 and grows `maxY` by 76. This is how one window's title moved every other window's thumbnail.
- **testANarrowerGridWrapsSooner** — the same tiles at three widths produce 1, 2 and 3 rows.
- **testWiderTilesFitFewerPerRow** — the same grid width with wider tiles.

### E. Centering
- **testAFullRowIsNotMoved** — a row that already spans the width gets a zero offset.
- **testAShortRowIsCentered** — a half-empty last row is offset by half the slack, rounded away from zero.
- **testAnEmptyRowGetsNoOffset** — the empty row 0 left by an oversized first tile.
- **testARowWiderThanTheSpaceIsNotPulledBack** — the offset is clamped at zero, never negative.

### F. The auto size
- **testAutoTakesTheFirstSizeThatFits** — large is measured first and kept when its grid fits.
- **testAutoFallsThroughToTheNextSize** — large does not fit, medium does; both are measured, small is not.
- **testAutoKeepsTheSmallestWhenNothingFits** — every candidate is measured and the last one is returned.
- **testAutoMeasuresEachCandidateExactlyOnce** — the measurement has side effects in production
  (`Appearance.applySize`), so the call order and count are part of the contract.
