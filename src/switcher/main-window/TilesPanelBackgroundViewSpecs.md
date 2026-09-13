# Switcher panel background — Specs

No unit tests: `NSGlassEffectView` needs macOS 26 at runtime, and CI runs on macOS 15.

## Summary

The switcher panel's background is one of three effect views, picked by `requiredEffectViewKind()`:
frosted (macOS 25 and earlier), regular glass, or the private clear-glass variant used by App Icons.
`TilesView` caches one instance per kind and calls `updateAppearance()` on reuse, so anything that
varies with style or size has to be re-applied there rather than at construction.

## Manual scenarios

- **Glass corners clip to the glass shape** — the backing layer clips to the same continuous corner
  radius as `NSGlassEffectView`, which bounds the rectangular corner artifacts of
  [#5757](https://github.com/lwouis/alt-tab-macos/issues/5757). Summon and dismiss Titles and Thumbnails
  repeatedly, switch between those styles (23pt and 43pt corners), and change App Icons sizes
  (50pt, 55pt, 75pt corners). Inspect all four corners in light and dark appearances, including against
  contrasting backgrounds. Selection, scrolling and search stay usable.
- **Recheck on later macOS builds** — this works around a rendering bug rather than identifying it.
  Disabling the window shadow, allowing glass layout, and clipping to a rectangle all failed to fix it.
  Confirm the artifact is still there before keeping the rounded clip.
