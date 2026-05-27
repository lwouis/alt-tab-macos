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
**only when the short-circuit reaches it** (an invisible / hidden / windowless window never triggers an
`isOnScreen` computation). The other two derived facts (exception match, visible-space membership) are
pure expressions over the inputs, evaluated inline inside the same short-circuit chain so they're cheap
to keep eager. This makes the "why is/isn't this window showing?" logic — easily the most combinatorially
fiddly part of the app — fully unit-testable *without* losing the original boolean's laziness.

## Behavior & edge cases

The predicate, in order:

1. **Invisible** windows are always excluded (unconditional, first).
2. Windows matching a **hide-exception** (by bundle-id prefix + the exception's hide rule) are excluded.
3. **App scope** (`appsToShow`): `.active` keeps only the frontmost app's windows; `.nonActive` excludes them.
4. **Hidden apps** (⌘H): excluded when the "hide hidden" dropdown is set.
5. **Windowless apps** (placeholder rows for apps with no open window): shown unless hidden — and they
   **bypass** the window-only filters below (space/screen/fullscreen/minimized/tab), since those only
   make sense for real windows.
6. For **real windows**: also exclude fullscreen / minimized (when set), windows not in a visible space
   (`.visible`) or in a visible space (`.nonVisible`), windows off the preferred screen
   (`.showingAltTab`), and non-frontmost native **tabs** (unless tabs are shown as separate windows).

Precedence matters: `isInvisible` wins over everything (even a would-be-shown windowless row).

## Test scenarios

Mirrors `WindowFilterResolverTests.swift` 1:1. Each test flips one knob from an all-permissive baseline.

### A. Defaults & always-excluded
- **testDefaultsShowARealWindow** — a plain visible window with no filters shows.
- **testInvisibleIsHidden** — invisible → hidden.
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

### H. Screens
- **testOnlyPreferredScreenHidesOffScreenWindow** / **testOnlyPreferredScreenShowsOnScreenWindow** — `.showingAltTab` keeps only windows on the preferred screen.

### I. Tabs (macOS native tabs)
- **testNonFrontmostTabHiddenWhenGrouping** — a non-frontmost tab is hidden when tabs are grouped.
- **testTabbedShownWhenSeparateTabs** — shown when "tabs as separate windows" is set.

### J. Combinations
- **testAllFiltersOnAndWindowPassesEachShows** — every filter on, a window that satisfies all of them shows.
- **testInvisibleBeatsWindowlessShow** — `isInvisible` overrides the windowless "show" path.
