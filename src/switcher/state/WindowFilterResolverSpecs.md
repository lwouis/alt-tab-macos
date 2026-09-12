# WindowFilterResolver — Specs

> **Line coverage:** `WindowFilterResolver.swift` 100% · _refreshed 2026-05-27 by `/coverage-explore`_

## Summary

`WindowFilterResolver.shouldShow` decides whether a single window appears in the switcher for the
current shortcut. It's the per-window predicate behind `Windows.refreshIfWindowShouldBeShownToTheUser`,
extracted as a pure kernel. The caller passes the window's `WindowState`, the owning app's
`ApplicationState`, the per-shortcut dropdown booleans + the runtime context (frontmost pid, visible
space ids, exceptions list) as labeled parameters with `false` / `nil` / `[]` defaults — so each test
spells out only the knob it exercises. The only comparatively expensive fact — `isOnScreen` (multi-
screen quartz / `Spaces.screenSpacesMap`) — is passed as `@autoclosure` so the kernel evaluates it
**only when the short-circuit reaches it** (a phantom / hidden / windowless window never triggers an
`isOnScreen` computation). The other two derived facts (exception match, visible-space membership) are
pure expressions over the inputs, evaluated inline inside the same short-circuit chain so they're cheap
to keep eager. This makes the "why is/isn't this window showing?" logic — easily the most combinatorially
fiddly part of the app — fully unit-testable *without* losing the original boolean's laziness.

## Behavior & edge cases

The predicate, in order:

1. **Phantom** windows are always excluded (unconditional, first).
2. Windows matching a **hide-exception** (by bundle-id prefix + the exception's hide rule) are excluded.
3. **App scope** (`appsToShow`): `.active` keeps only the frontmost app's windows; `.nonActive` excludes them;
   `.underCursor` keeps only the windows whose frame contains the cursor (see 7).
4. **Hidden apps** (⌘H): excluded when the "hide hidden" dropdown is set.
5. **Windowless apps** (placeholder rows for apps with no open window): shown unless hidden — and they
   **bypass** the window-only filters below (space/screen/fullscreen/minimized/tab), since those only
   make sense for real windows.
6. For **real windows**: also exclude fullscreen / minimized (when set), windows not in a visible space
   (`.visible`) or in a visible space (`.nonVisible`), windows off the preferred screen
   (`.showingAltTab`), and non-frontmost native **tabs** (unless tabs are shown as separate windows).
7. **Under the cursor** (`appsToShow == .underCursor`): only windows whose frame contains the cursor, read
   once per show (`Windows.updatesBeforeShowing`) and passed as the lazy `isUnderCursor`. The frame must be
   drawn there, so a minimized window, a hidden app's window, a window on a non-visible Space, and a
   windowless placeholder are excluded even when their stored frame contains the point. A held tab counts as
   on the visible Space, as for the Space gates. The other dropdowns still apply on top.

Precedence matters: `isPhantom` wins over everything (even a would-be-shown windowless row).

**A HELD tab counts as "on the visible Space and on the preferred screen"** (`isHeldVisibleForTab`). A tab
kept visible through the new-tab discovery gap is Space-less — its 1326 has landed — yet it just backgrounded
on the CURRENT Space and belongs on screen for the length of the swap. `isPhantom` already exempts it, but
these Space and screen gates are SEPARATE and hid it anyway: that is the FIRST-tab vanish (2026-07-24), where
no group exists yet to borrow the tab a Space, so the hold was defeated by the very filter it had no reason
to meet. It is fixed HERE, at the display layer, and deliberately not by lending the model a Space — that was
tried and broke reducer idempotence. So: shown under `.visible`, hidden under `.nonVisible` (it IS on the
visible Space, so the mirror must agree), and never dropped by the preferred-screen gate.

## Test scenarios

Mirrors `WindowFilterResolverTests.swift` 1:1. Each test flips one knob from an all-permissive baseline.

### A. Defaults & always-excluded
- **testDefaultsShowARealWindow** — a plain visible window with no filters shows.
- **testPhantomIsHidden** — phantom → hidden.
- **testHiddenByExceptionIsHidden** — a hide-exception match → hidden.

### B. App scope (`appsToShow`)
- **testOnlyFrontmostAppHidesNonFrontmost** / **testOnlyFrontmostAppShowsFrontmost** — `.active` keeps only the frontmost app.
- **testExcludeFrontmostAppHidesFrontmost** / **testExcludeFrontmostAppShowsNonFrontmost** — `.nonActive` excludes the frontmost app.

### C. Hidden apps
- **testHideHiddenHidesHiddenApp** — hidden app excluded when "hide hidden" is set.
- **testHiddenAppShownWhenNotHiding** — otherwise shown.

### D. Windowless apps
- **testWindowlessShownByDefault** — windowless row shows by default.
- **testHideWindowlessHidesIt** — hidden when "hide windowless" is set.
- **testWindowlessBypassesWindowOnlyFilters** — shows even under space/screen filters that would hide a real window.

### E. Fullscreen
- **testHideFullscreenHidesFullscreen** / **testFullscreenShownWhenNotHiding**

### F. Minimized
- **testHideMinimizedHidesMinimized** / **testMinimizedShownWhenNotHiding**

### G. Spaces
- **testOnlyVisibleSpacesHidesWindowNotInVisibleSpace** / **testOnlyVisibleSpacesShowsWindowInVisibleSpace** — `.visible` keeps only windows in a visible space.
- **testOnlyNonVisibleSpacesHidesWindowInVisibleSpace** — `.nonVisible` excludes windows in a visible space.
- **testOnlyVisibleSpacesShowsSpacelessHeldTab** — the first-tab vanish: a held tab is Space-less but just
  backgrounded on the current Space, so `.visible` must still show it.
- **testOnlyNonVisibleSpacesHidesHeldTab** — the mirror, so the exemption can't show the same tab under both
  settings.

### H. Screens
- **testOnlyPreferredScreenHidesOffScreenWindow** / **testOnlyPreferredScreenShowsOnScreenWindow** — `.showingAltTab` keeps only windows on the preferred screen.
- **testOnlyPreferredScreenShowsHeldTab** — a held tab is never dropped by the screen gate either (same
  fix, third gate: the Space-less tab has no Space to resolve a screen from).

### I. Tabs (macOS native tabs)
- **testNonFrontmostTabHiddenWhenGrouping** — a non-frontmost tab is hidden when tabs are grouped.
- **testTabbedShownWhenSeparateTabs** — shown when "tabs as separate windows" is set.

### J. Combinations
- **testAllFiltersOnAndWindowPassesEachShows** — every filter on, a window that satisfies all of them shows.
- **testPhantomBeatsWindowlessShow** — `isPhantom` overrides the windowless "show" path.

### K. Under the cursor (`appsToShow == .underCursor`)
- **testOnlyUnderCursorHidesWindowNotUnderCursor** / **testOnlyUnderCursorShowsWindowUnderCursor** — the frame test decides.
- **testOnlyUnderCursorHidesMinimizedWindowUnderCursor** / **testOnlyUnderCursorHidesHiddenAppWindowUnderCursor** /
  **testOnlyUnderCursorHidesWindowOnNonVisibleSpace** — a frame that contains the point but isn't drawn there doesn't count.
- **testOnlyUnderCursorHidesWindowlessApp** — a placeholder has no frame.
- **testOnlyUnderCursorShowsHeldTabUnderCursor** — a held tab is on the visible Space.
- **testOnlyUnderCursorStillHonoursOtherFilters** — the other dropdowns still apply.
