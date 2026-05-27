# SelectionResolver — Specs

> **Line coverage:** `SelectionResolver.swift` 93% · _refreshed 2026-05-27 by `/coverage-explore`_

## Summary

`SelectionResolver` decides **which tile is highlighted** while the switcher is open. Every time the
window list changes (a window opens/closes, an app steals focus, a search query filters the list), the
switcher calls `SelectionResolver.decide(_:)` with a snapshot of the current state and gets back a
`SelectionDecision` enum; the wrapper (`Windows`) turns that into highlight redraws, scroll-to-visible,
target bookkeeping, and the preview. Pure data in, `Equatable` decision out — no globals, no AppKit.

### The core idea: a stable "target"

Once the user moves the highlight, the selected window's id is remembered as the **target**. On every
refresh the resolver tries to keep the highlight on that same window even as the list reorders — this is
the #5665 fix (before it, a background app finishing launch could yank the highlight away mid-pick).

## Behavior & edge cases (decision priority order)

1. **Search-clear** (`restoreDefaultOnSearchClear`) takes precedence — re-runs the initial pick even with no visible windows.
2. **Empty visible list** → `clearTargetAndHover`.
3. **Search best-match** (`bestMatchOnSearchChange`) → jump to the first visible (best-scored) window.
4. **No target yet** (`selectedTarget == nil`, first refresh) → "from scratch" initial pick.
5. **Target still present** → follow it to its new index (`selectAt`).
6. **Target gone** → adapt to the closest visible window.

Initial-pick rules: with the last-focused rule, pick the visible non-windowless window with the lowest
`lastFocusOrder`; the both-top-minimized edge lands on index 0; otherwise cycle from 0 to the next
visible. Windowless app entries and invisible windows are skipped when scanning. `findTarget` only
matches a target id that is currently visible.

## Test scenarios

Mirrors `SelectionResolverTests.swift` 1:1. Groups: A initial pick · B preserve target (#5665) ·
C target removed · D search mode · E edge cases · plus direct helper-kernel checks.

### A. Initial pick (`selectedTarget == nil`)
- **testInitialPickEmptyList** — no windows → `clearTargetAndHover`.
- **testInitialPickSingleVisible** — one window → `resetThenSelect(0)`.
- **testInitialPickTwoVisibleDefaultRules** — default Cmd-Tab cycles to slot 1.
- **testInitialPickTopTwoMinimized** — both top windows minimized → land on index 0, not cycle past.
- **testInitialPickUseLastFocusedRule** — alpha/space ordering → pick lowest `lastFocusOrder`.
- **testInitialPickAllInvisible** — everything filtered out → `clearTargetAndHover`.
- **testInitialPickSkipsWindowlessInLastFocusedRule** — windowless entries skipped when scanning.

### B. Preserve target across reorders (the #5665 regression cluster)
- **testPreserveTargetSameIndex** — target still at its index → `selectAt` unchanged.
- **testPreserveTargetMovedToHigherIndexAfterPhotoshopLaunch** — an app launches and reorders the list; highlight follows the target to its new slot (not a re-pick).
- **testPreserveTargetMovedToLowerIndex** — a window closed above the target; highlight follows down.
- **testPreserveTargetIndexUnchangedByCoincidence** — churn that lands the target at the same index.
- **testPreserveTargetNewWindowAppended** — new window appended at the end; target slot unchanged.
- **testPreserveTargetAcrossMultipleReorders** — repeated focus-stealing; target tracked every refresh.

### C. Target removed / no longer visible
- **testTargetRemovedAdaptToClosestBelow** — target closed; backfill the target to the window now at that index.
- **testTargetRemovedSelectedIndexOutOfBounds** — list shrank below `selectedIndex` → closest visible below.
- **testTargetBecameInvisible** — target filtered out (search/space) → closest visible below.
- **testTargetRemovedAndListEmptied** — nothing left → `clearTargetAndHover`.
- **testTargetRemovedOnlyOneLeft** — one window remains → select it and backfill the target.

### D. Search-mode interactions
- **testSearchBestMatchOnSearchChange** — new query produces a best match → jump to first visible.
- **testSearchRestoreDefaultOnClear** — cleared query → restore the default initial pick.
- **testTargetPreservedInSearchMode** — target preservation works the same with search active.
- **testSearchTargetFilteredOutWithOthersMatching** — target filtered but others match → adapt to closest.

### E. Edge cases
- **testEdgeSingleWindowBecomesInvisible** — the only window goes invisible → clear selection.
- **testEdgeNewWindowPushesTargetDown** — a window inserts ahead → highlight follows the target down.
- **testEdgeStaleSelectedTarget** — target id never existed (corrupt/stale) → adapt + backfill.

### Helper kernels (direct)
- **testGetLastFocusedOrderWindowIndexIgnoresWindowlessAndInvisible** — scan ignores windowless + invisible.
- **testCycleFromZeroBehavior** — empty / single-visible (wraps to 0) / multi / skip-invisible.
- **testFindTargetSkipsInvisibleMatches** — finds visible id; nil for invisible/missing/nil id.
