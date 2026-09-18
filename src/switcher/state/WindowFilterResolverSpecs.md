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
3. **App scope** (`appsToShow`): `.active` keeps only the frontmost app's windows; `.nonActive` excludes them.
4. **Hidden apps** (⌘H): excluded when the "hide hidden" dropdown is set.
5. **Windowless apps** (placeholder rows for apps with no open window): shown unless hidden — and they
   **bypass** the window-only filters below (space/screen/fullscreen/minimized/tab), since those only
   make sense for real windows.
6. For **real windows**: also exclude fullscreen / minimized (when set), windows not in a visible space
   (`.visible`) or in a visible space (`.nonVisible`), windows off the preferred screen
   (`.showingAltTab`), and non-frontmost native **tabs** (unless tabs are shown as separate windows).

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

## Running-app visibility identity

Application discovery retains the positive PID supplied by WindowServer even when
NSRunningApplication reports -1. Bulk discovery skips invalid PIDs. Workspace
hide, unhide and activation notifications with an invalid PID resolve against the
tracked running-app identity; termination cleanup uses the retained model PID.
This prevents duplicate model records and applying visibility to the wrong record.

Regression scenarios requiring the macOS running-app layer:
- Discover an app using a positive PID while its running-app PID is invalid.
  Repeated discovery must retain one record and its original positive PID.
- Hide and unhide that app. Its tracked windows follow the configured hidden-app
  filter, and activation updates the same tracked identity.
- Terminate it after its running-app PID becomes invalid. All per-PID inventory,
  observer and attention state for the retained PID must be removed.
- An unmatched invalid-PID notification does not create or update an app.
- Apps with ordinary positive PIDs continue using their existing notification path.

Device Hub on macOS 27 exposed this condition. Three hide/unhide cycles passed
in the original local candidate. Resolver unit tests exercise filtering and order,
but do not substitute for these Workspace notification integration scenarios.
