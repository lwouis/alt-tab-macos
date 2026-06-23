# DragAndDropResolver — Specs

## Summary

`DragAndDropResolver` is the pure decision layer for drag-and-drop over the switcher: what a drag-over of
the tiles should do (`dragOver`), when the auto-select timer (re)arms (`movedBeyondResetRadius`), whether
the global mouse tap must yield the drop's mouse-up (`passesThroughMouseUp`), and whether a drop is valid
(`canDrop`). It holds no state and touches no AppKit drag session, timer, or event tap — `TilesDocumentView`
(the `NSDraggingDestination`) and `CursorEvents` (the global tap) turn its decisions into real
`NSDragOperation`s, timers, and tap pass-through (same pattern as `AxQueryRouting`).

## Behavior & edge cases

- **Two owners, one boundary.** AppKit's `NSDraggingDestination` owns the drag (hover highlight, the `.link`
  operation, the auto-select timer); the global mouse tap owns ordinary clicks. They conflict only on the
  one event that ends a drag — the `leftMouseUp`. A file drag over the switcher can only have started in
  another app BEFORE the switcher showed (the tap swallows any `leftMouseDown` outside the panel, and tiles
  aren't drag sources), so the tap never saw that drag's `leftMouseDown`. `passesThroughMouseUp` keys off
  exactly that: yield any up whose down the tap didn't see, so AppKit / the source app concludes the drop
  instead of the tap swallowing it and leaving the file glued to the cursor. This holds wherever the release
  lands — on a tile, on the padding around the tiles, or outside the panel — because none of those are a
  down the tap saw. A normal click's down IS seen, so clicks route normally. This is the #5350-regression fix.
- **No grab on appear + deadzone.** A drag already in flight when the switcher shows must not select a
  window on the first stray pixel. `dragOver` reports `.inDeadzone` (still a valid `.link` drop, but no
  selection and no timer) until the pointer clears the same movement deadzone mouse hover uses.
- **The inter-tile gap targets like hover.** Targeting reuses hover's `findTarget`, which expands each tile
  by 1px so the 1px gap between tiles still resolves to a tile. The kernel only sees `hasTarget`; it never
  returns `.noTarget` while the cursor is over the grid.
- **The auto-select timer always runs for a drag.** Hover gates the 2s auto-select timer on a preference;
  dragging is a stronger intent, so it always arms the timer when past the deadzone. The timer (re)arms on a
  target change or once the pointer leaves the reset radius (`movedBeyondResetRadius`, inclusive at the
  radius); a sub-radius jitter within the same tile lets the running timer fire. A `nil` anchor (timer not
  armed yet) counts as "re-arm".
- **A drop opens files with the tile's app**, so it needs a target tile, that tile's window, the app's
  bundle URL, and at least one URL; a non-URL drag (text/image) or any missing piece is rejected (the drag
  snaps back).

## Test scenarios

Mirrors `DragAndDropResolverTests.swift` 1:1.

### A. Drag-over operation (deadzone, targeting, always-on timer)
- **testNoTargetReportsNoDrop** — off the grid (no tile) → `.noTarget`.
- **testTargetInDeadzoneLinksWithoutSelecting** — tile present but deadzone not cleared → `.inDeadzone` (no grab on appear).
- **testTargetChangeArmsTimer** — moving onto a different tile → `.track(restartTimer: true)`, regardless of distance.
- **testSameTargetWithinRadiusKeepsTimerRunning** — same tile, sub-radius jitter → `.track(restartTimer: false)`.
- **testSameTargetBeyondRadiusRearmsTimer** — same tile, left the radius → `.track(restartTimer: true)`.

### B. Auto-select timer reset radius (the 5px rule)
- **testNoAnchorAlwaysRearms** — `nil` anchor → re-arm.
- **testWithinResetRadiusDoesNotRearm** — moved 4px (radius 5) → no re-arm.
- **testAtResetRadiusRearms** — moved exactly 5px, and the 3-4-5 diagonal → re-arm (inclusive boundary).
- **testBeyondResetRadiusRearms** — moved 10px → re-arm.

### C. Mouse-up pass-through (the regression fix)
- **testPassesThroughMouseUpForUnseenDown** — a drag's down was never seen → yield the up (don't swallow the drop).
- **testSwallowsMouseUpForSeenDown** — a click's down was seen → route normally (not yielded).

### D. Drop validity
- **testDropNeedsTargetWindowBundleAndUrls** — target + window + bundle URL + ≥1 URL → drop.
- **testNoTargetRejectsDrop** — no target → reject.
- **testNoWindowRejectsDrop** — target without a window → reject.
- **testNoBundleUrlRejectsDrop** — app without a bundle URL → reject.
- **testNoUrlsRejectsDrop** — non-URL drag / empty pasteboard (0 URLs) → reject.

### E. Use-case integration (the discussed scenarios as decision sequences)
- **testUseCaseDragPresentWhenSwitcherAppears** — drag present on show → `.inDeadzone`; after clearing the deadzone → `.track`.
- **testUseCaseDropOnTileConcludes** — the regression: the tap yields the up (down unseen), and a valid target drops.
- **testUseCaseReleaseOnPaddingEndsDragWithoutOpening** — release on the padding / outside the panel: the up is yielded so the drag ends, but no target means nothing opens.
- **testUseCaseBetweenTilesStillTargets** — the 1px gap resolves to a tile upstream, so the kernel keeps tracking (never `.noTarget` over the grid).
- **testUseCaseAutoSelectTimerSurvivesJitterButRearmsOnMove** — jitter keeps the timer; a real move re-arms it.
