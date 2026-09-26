# TilePool — Specs

## Summary

The switcher draws each window on a recycled tile from `TilesView.recycledViews`. A tile bakes part of the
switcher's appearance in when it is built: the title font and the shadow color of its thumbnail and icons.
Later shows refresh a tile's content and frames, not that construction-time state, which only
`TilesView.reset()` reapplies.

`Appearance` starts with placeholder values (a 3pt font, red shadows) so a tile built too early is visible
rather than subtly wrong. Launch applies the real values right before it builds the switcher UI, but
windows start arriving earlier: the WindowServer tap is installed ahead of the permission gate, and the
gate resumes launch asynchronously, from a background timer. `TilePool` decides how many tiles to build so
that none is built in that gap.

## Behavior & edge cases

- **Nothing is built before the switcher UI.** Windows discovered during the permission check are added to
  the model with no tile. Building one then gave it red shadows and a title clipped to the height of a 3pt
  line, on as many tiles as windows arrived in the gap (two in the reported case, always the first tiles).
- **The first pool covers every window already known**, with at least `minimumSize` (20) tiles so the
  first windows opened after launch need no allocation.
- **After that, the pool grows to the window count and never shrinks.** Tiles past the list keep no image
  or window (`TilesView.fillTiles` releases them), so a large pool left over from a busy moment is cheap.

## Test scenarios

`TilePoolTests.swift`

### A. Before the UI
- **testNoTileIsBuiltBeforeTheSwitcherUi** — 1, 2, 20 or 35 windows known before the UI: no tile.

### B. The first pool
- **testFirstPoolHoldsTheMinimumWhenFewWindowsAreKnown** — 0 or 2 windows known: 20 tiles.
- **testFirstPoolCoversWindowsDiscoveredBeforeIt** — 35 windows known: 35 tiles.

### C. Growth
- **testPoolGrowsOneTileForEachWindowPastIt** — the 21st window adds one tile to a pool of 20.
- **testPoolThatCoversTheListAddsNothing** — 20 windows, 20 tiles: nothing added.
- **testPoolNeverShrinks** — 3 windows left in a pool of 40: nothing removed or added.

### D. A replayed launch
- **testReplayedLaunchBuildsEveryTileAfterTheUi** — 2 windows arrive during the permission check, the UI is
  built, 25 more arrive: 27 tiles, every one built after the UI.
