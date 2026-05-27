# ProBadgeView (segment overlay) — Specs

> **Line coverage:** `ProBadgeView.swift` 50% · _refreshed 2026-05-27 by `/coverage-explore`_ (an AppKit view; the draw/`layout` paths a unit test can reach are covered, the rest is rendering glue).

## Summary

`ProBadgeView` overlays a small "Pro" badge onto a segment of a Settings `NSSegmentedControl` (the
Appearance style/size segments that are Pro-gated). It must blend in with AppKit's native segment
rendering — same widths, same system-resolved colors across appearance/selection/key-window states — and
stay correct when built lazily off-window. The suite pins the layout, color-provider, icon-templating,
and selection-sync behavior, with explicit regression coverage for two real bugs.

## Behavior & edge cases

- **Widths unchanged**: the badge must not widen its segment (the overlay label truncates *before* the
  badge); all segments keep their native width.
- **Colors are AppKit-driven, never hard-coded**: the icon/label use a `colorProvider` closure so AppKit
  re-resolves the system color token every draw — selected+key → `.alternateSelectedControlTextColor`,
  otherwise `.controlTextColor` (which AppKit fades for inactive/disabled/dark automatically). No
  `NSColor(red:green:blue:)` tuples.
- **Icon is a template image**: `isTemplate = true` strips SF Symbols' intrinsic multicolor so the glyph
  respects our tint (matching AppKit's monochrome segment rendering).
- **Selection sync**: the badge reflects the segment's selected state on init and on refresh, and marks
  icon/label for redraw.
- **Enabled state untouched**: attaching the badge never changes the segment's or control's enabled state.
- **Regressions pinned**: (1) `layout()` sizes the three gradient sublayers + sets `borderMask.path` /
  `textMask.frame` — if suppressed, the badge renders as the "faded" 10%-alpha fill; (2)
  `viewDidMoveToWindow` calls `updateColors()` so a badge created off-window (lazy Appearance pane while
  Settings is already key) resyncs instead of staying stuck in its `init`-time not-key colors.

## Test scenarios

Mirrors `ProBadgeViewSegmentTests.swift` 1:1.

### Width: Pro segment must not grow
- **testProSegmentWidthUnchanged** — the Pro segment keeps its native width (label truncates before the badge).
- **testNonProSegmentWidthsUnchanged** — other segments are unaffected.

### Overlay subviews
- **testAttachReturnsBadgeIconAndLabel** — attaching produces the badge icon + label.
- **testAttachClearsNativeLabel** — the segment's native label is cleared (the overlay owns it).
- **testAttachClearsNativeImage** — the segment's native image is cleared.

### Colors: AppKit-driven, never hard-coded
- **testIconHasColorProvider** / **testLabelHasColorProvider** — icon + label use a `colorProvider` closure.
- **testColorProviderSelectedAndKey** — selected + key window → `.alternateSelectedControlTextColor`.
- **testColorProviderUnselected** — unselected → `.controlTextColor`.
- **testColorProviderSelectedButNotInWindow** — selected but window not key → `.controlTextColor`.
- **testAttachDoesNotHardcodeIconTint** / **testAttachDoesNotHardcodeLabelColor** — no hard-coded color tuples.

### Icon rendering
- **testIconIsTemplateImage** — the symbol is a template image so it respects the tint.

### Selection sync
- **testBadgeReflectsInitialUnselectedState** / **testBadgeReflectsInitialSelectedState** — initial state matches the segment.
- **testRefreshSelectionSyncsBadge** / **testRefreshSelectionSyncsBadgeOnDeselection** — refresh syncs selection both ways.
- **testRefreshSelectionMarksIconAndLabelForRedraw** — refresh marks icon + label for redraw.

### Enabled state (AppKit-driven, we don't touch)
- **testAttachDoesNotChangeSegmentEnabledState** / **testAttachDoesNotChangeControlEnabledState** — enabled state untouched.

### Badge selection mechanics
- **testBadgeSelectedStateWorksBeforeWindowAttach** — selection state is correct even before the view has a window.

### Layout / viewDidMoveToWindow (regression coverage)
- **testLayoutConfiguresGradientSublayerFrames** — `layout()` sizes the gradient sublayers + masks (guards the "faded badge" bug).
- **testViewDidMoveToWindowResyncsColors** — entering a window re-runs `updateColors()` (guards the "faded badge in a lazily-built pane" bug).
