# Switcher panel background — Specs

No unit tests: `NSGlassEffectView` needs macOS 26 at runtime, and CI runs on macOS 15.

## Summary

The switcher panel's background is one of three effect views, picked by `requiredEffectViewKind()`:
frosted (macOS 25 and earlier), regular glass, or the private clear-glass variant used by App Icons and Titles.
`TilesView` caches one instance per kind and calls `updateAppearance()` on reuse, so anything that
varies with style or size has to be re-applied there rather than at construction.

## Manual scenarios

- **Glass corners clip to the glass shape** — the backing layer clips to the same continuous corner
  radius as `NSGlassEffectView`, which bounds the rectangular corner artifacts of
  [#5757](https://github.com/lwouis/alt-tab-macos/issues/5757). Summon and dismiss Titles (clear glass, 23pt corners) and Thumbnails
  repeatedly, switch between those styles (23pt and 43pt corners), and change App Icons sizes
  (50pt, 55pt, 75pt corners). Inspect all four corners in light and dark appearances, including against
  contrasting backgrounds. Selection, scrolling and search stay usable.
- **Titles uses clear glass, Thumbnails keeps regular glass** — on macOS 26+, summon Titles and the
  panel shows the clear-glass look (as App Icons does); switch to Thumbnails and it shows regular glass.
  With the private clear-glass look unavailable, Titles shows regular glass like App Icons.
- **No panel shadow under clear glass** — Titles and App Icons show no shadow around the panel;
  Thumbnails keeps its shadow. Switch between the styles and confirm the shadow follows the style.
- **Recheck on later macOS builds** — this works around a rendering bug rather than identifying it.
  Disabling the window shadow, allowing glass layout, and clipping to a rectangle all failed to fix it.
  Confirm the artifact is still there before keeping the rounded clip.
