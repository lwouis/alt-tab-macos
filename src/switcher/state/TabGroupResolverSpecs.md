# TabGroupResolver — Specs

## Summary

`TabGroupResolver` holds the pure decisions behind macOS **OS-tab** detection — deciding which windows are
inactive tabs of one tabbed window, given the facts AltTab can read. macOS exposes no public API that maps
an inactive tab to its window: `_AXUIElementGetWindow` on an AXTabButton returns the *parent* window's WID,
not the tab's own, so tabs must be matched to windows **by title** (full investigation:
`TabbedWindowDetection.swift`). Inactive tabs also appear in no CGS list, so the WindowServer-driven
discovery never sees them until the user focuses one. Extracted as a pure kernel from `TabGroup` (which
keeps the `Windows.list` reads/writes and the AX/CGS side effects) so the brittle matching is unit-testable
without the `Window` graph. Operates on the flat `TabWindow` record — the tab analogue of `WindowState`,
carrying the `pid` / `wid` / `size` / `position` / `tabbedSiblingWids` that grouping needs and `WindowState`
omits.

Two independent signals locate tabs, used at different times:

- **AX titles** (`matchSiblings`) — authoritative but only available for the *active* tab (an inactive tab
  reports no AXTabGroup), read at discovery and on each show. Matches by title, so it's fragile when titles
  are dynamic (Terminal renames tabs by cwd/command) or drift between the tab-button title and the window's
  own title.
- **Geometry** (`geometryGroups`) — reactive, AX-free: within one app, windows sharing an exact size where
  one holds a Space and the others are Space-less are a tabbed window and its background tabs. Catches the
  tab switch that AX missed (the "pop-in"), and fullscreen tabs that expose no readable AXTabGroup. Geometry
  alone does not **create** a group: it only fires when the visible window is fullscreen or was already
  AX-confirmed as tabbed (`tabbedSiblingWids != nil`). Otherwise separate windows of one app that share a
  default size and go briefly Space-less (a Space transition, a flaky CGS read) get collapsed into a phantom
  tab group, hiding real windows (#5830).

## Functions

- **`geometryGroups(windows) -> [GeometryGroup]`** — group same-app, same-**size** (not full-frame: a
  background tab's position goes stale while ordered out) candidates where exactly the visible tab holds a
  Space and ≥ 1 sibling is Space-less. Minimized / size-less windows are excluded. A separate real window
  is never Space-less, so two visible same-size windows are **not** collapsed. The visible tab must be
  fullscreen or already AX-confirmed tabbed (`tabbedSiblingWids != nil`) — geometry re-links and covers
  fullscreen, but never fabricates a group from unconfirmed same-size windows (#5830). Output sorted by
  `visibleWid`.
- **`matchSiblings(active, axTitles, sameAppWindows) -> SiblingMatch`** — resolve the active tab's AXTabGroup
  titles to tracked windows. The active title is removed once (duplicates allowed); each remaining title
  matches the first compatible, not-yet-matched same-app window. A window still tabbed into THIS group
  (`isTabbed` + `tabbedSiblingWids` ∋ active) is then **kept** even if no title named it, so a duplicate or
  renamed title can't flap an inactive tab out (#5830); each kept sibling also cancels one `untrackedTitle`.
  Returns the group's wids (active first), the matched+kept wids, `untrackedTitles` (titles with no window →
  inactive tabs to discover), and `toUntabWids` (windows that were in this group but are no longer tabbed).
- **`positionsCompatible(a, b) -> Bool`** — tabs share their parent's frame. An existing tab link wins (a
  stale position can't split an already-grouped pair). Unknown position or either fullscreen → title-only
  fallback (true). Otherwise within 50px on both axes.
- **`dissolution(siblingWids, leaving, presentWids) -> GroupDissolution`** — when a member leaves (destroyed,
  or active tab gone standalone), ≤ 1 still-tracked survivor ⇒ dissolve (a single window can't be a tab
  group); otherwise shrink the survivors' group to the remaining wids.

## Test scenarios

Mirrors `TabGroupResolverTests.swift` 1:1. Helpers build an all-default `TabWindow` and flip only the knobs
each test exercises.

### A. geometryGroups

- **testConfirmedVisiblePlusSpacelessIsAGroup** — same app + size, visible holds a Space and carries the
  group's `tabbedSiblingWids` (AX-confirmed), one sibling Space-less → grouped. The tab-switch re-link.
- **testFullscreenVisibleGroupsWithoutAxConfirmation** — visible is fullscreen (no `tabbedSiblingWids`, since
  AX can't read a fullscreen AXTabGroup) + one Space-less sibling → grouped via the fullscreen exemption.
- **testNormalUnconfirmedNotGrouped** — same app + size, visible is normal and never AX-confirmed, one sibling
  briefly Space-less → **not** grouped. The #5830 fix: geometry alone can't fabricate a group.
- **testTwoVisibleSameSizeNotGrouped** — same app + size but *both* hold a Space (two separate real windows)
  → no group. A real window is never Space-less, so it's never collapsed into a tab.
- **testDifferentSizesNotGrouped** — same app, different sizes → no group.
- **testDifferentAppsNotGrouped** — same size, different pid → no group.
- **testMinimizedSpacelessNotGrouped** — a Space-less *minimized* window is excluded from candidates.
- **testSizelessExcluded** — a window with no size is excluded from candidates.
- **testSingleCandidateNoGroup** — one candidate → no group.
- **testMultipleBackgroundTabsGroupUnderVisible** — one AX-confirmed visible + two Space-less, all same size
  → both backgrounds grouped under the one visible tab.

### B. matchSiblings

- **testMatchesInactiveSiblingByTitle** — active "git" with titles [git, lwouis] + a same-app window
  "lwouis" → matched; `siblingWids` = [active, lwouis].
- **testDuplicateTitleRemovedOnce** — titles [git, git] with the active titled "git" + one other "git"
  window → the active title is removed once, the other "git" is matched.
- **testUntrackedTitleReported** — a title with no tracked window → in `untrackedTitles` (to brute-force
  discover), not matched.
- **testStillTabbedSiblingKeptDespiteNoTitle** — a window still tabbed into this group (isTabbed +
  `tabbedSiblingWids` ∋ active) with no matching AX title → **kept** (the #5830 flap fix), not un-tabbed.
- **testDepartedSiblingUntabbedOnceNoLongerTabbed** — once that window's own read clears `isTabbed` (it went
  standalone), the next match un-tabs it (`toUntabWids`), clearing the stale link.
- **testOtherGroupTabsNotUntabbed** — a same-app window in a DIFFERENT group (`tabbedSiblingWids` lacks this
  active) is neither kept nor un-tabbed; coexisting groups of one app don't churn each other.
- **testNonTabbedUnmatchedNotUntabbed** — a same-app window with no tab state and an unmatched title is
  **not** in `toUntabWids` (only windows carrying stale tab state are cleared).
- **testFarPositionNotMatched** — a same-app window with the right title but a far-off position and no
  existing link → not matched; its title is reported untracked.
- **testDynamicTitleMismatchKeepsSibling** — the cause-B flap, now fixed: the active's AXTabGroup reports the
  inactive tab as "B2" (Terminal renamed it) but the tracked window still reads "B1". Title equality fails,
  but the sibling is still tabbed into this group, so it is **kept** (not shown as a separate window) and "B2"
  is **not** reported untracked (we already hold that tab). The #5830 stability fix.

### C. positionsCompatible

- **testExistingLinkBeatsFarPosition** — `b` already linked to `a` (its `tabbedSiblingWids` contains `a.wid`)
  → compatible even with far-apart positions.
- **testFullscreenFallsBackToTitle** — either window fullscreen → compatible (skip the position check).
- **testUnknownPositionFallsBack** — a missing position → compatible (title-only fallback).
- **testClosePositionsCompatible** — within 50px on both axes → compatible.
- **testFarPositionsIncompatible** — beyond 50px, both positioned, neither fullscreen, no link → not
  compatible.

### D. dissolution

- **testDissolveWhenOneSurvivor** — siblings [1, 2], 1 leaves, only 2 present → dissolve, apply to [2].
- **testShrinkWhenManySurvive** — siblings [1, 2, 3], 1 leaves, 2 and 3 present → shrink, remaining [2, 3],
  apply to [2, 3].
- **testAbsentSurvivorsNotCounted** — siblings [1, 2, 3], 1 leaves, but 3 already gone (present = {2}) → one
  survivor → dissolve, apply to [2].
