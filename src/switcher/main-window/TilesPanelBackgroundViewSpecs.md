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
- **Clear glass is tinted and titles stay readable** — with Titles or App Icons on macOS 26+, open
  the switcher over a pure white page and over a busy photo, in light and dark appearances. The panel
  carries a light wash (white in light, black in dark) drawn by the content host, the titles are fully
  opaque with a soft opposite-color halo, and the glass is still visibly see-through. The selection
  highlight still reads as the accent color. Thumbnails (regular glass) shows no wash.
- **Tint follows a live appearance switch** — switch the system appearance while AltTab runs, then
  summon the switcher: the wash and title halo match the new appearance without a restart.
- **Tint with Reduce Transparency** — turn on Reduce Transparency and summon Titles once; the panel
  and titles still look intentional (no doubled-up dark slab).
- **Recheck on later macOS builds** — this works around a rendering bug rather than identifying it.
  Disabling the window shadow, allowing glass layout, and clipping to a rectangle all failed to fix it.
  Confirm the artifact is still there before keeping the rounded clip.
