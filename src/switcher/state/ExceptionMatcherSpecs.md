# ExceptionMatcher — Specs

> **Line coverage:** `ExceptionMatcher.swift` 100% · _refreshed 2026-05-27 by `/coverage-explore`_

## Summary

The Exceptions tab lets the user add per-app rules. `ExceptionMatcher` answers the two questions those
rules drive, both pure:

- **`hidesWindow`** — should this window be hidden from the switcher? (the exception's `hide` rule)
- **`disablesShortcuts`** — should AltTab's global shortcuts be turned off while this app is frontmost?
  (the exception's `ignore` rule)

Both share a **bundle-id prefix gate**: an exception applies to an app iff the exception's
`bundleIdentifier` is non-empty and the app's bundle id *has it as a prefix* (so `com.foo` covers
`com.foo.bar`). It was extracted from `Windows.refreshIfWindowShouldBeShownToTheUser` (hide) and
`App.checkIfShortcutsShouldBeDisabled` (ignore).

## Behavior & edge cases

- **Hide rules**: `.none` never hides; `.always` always hides; `.whenNoOpenWindow` hides only the
  windowless placeholder row; `.windowTitleContains` hides when any non-empty pattern is a substring of
  the window title (nil / empty / empty-string patterns never match).
- **Active-app override (#5810)**: when `activeAppOverride` is set (filter is "Active app" and this is
  the active app), the blanket `.always` / `.whenNoOpenWindow` rules are ignored — the shortcut intent
  beats the Exceptions list. The narrower `.windowTitleContains` still fires (it hides only some windows).
- **Ignore rules**: `.always` disables shortcuts whenever the app is frontmost; `.whenFullscreen` only
  while the active window is fullscreen; `.none` never.
- **Gate guards**: an empty exception `bundleIdentifier` must not match every app; a nil app bundle-id
  never matches; any matching exception in the list is enough.

## Test scenarios

Mirrors `ExceptionMatcherTests.swift` 1:1.

### A. Per-exception hide rule (`hideMatches`)
- **testHideNoneNeverMatches** — `.none` → never.
- **testHideAlwaysMatches** — `.always` → always.
- **testHideWhenNoOpenWindowMatchesWindowlessOnly** — `.whenNoOpenWindow` matches only the windowless row.
- **testHideWindowTitleContainsMatchesSubstring** — pattern is a substring of the title → matches.
- **testHideWindowTitleContainsNoMatch** — pattern not in title → no match.
- **testHideWindowTitleContainsNilOrEmptyPatternsNeverMatch** — nil / empty list / empty-string patterns → never.
- **testHideAlwaysIgnoredWithActiveAppOverride** — `.always` + `activeAppOverride` → no hide.
- **testHideWhenNoOpenWindowIgnoredWithActiveAppOverride** — `.whenNoOpenWindow` + `activeAppOverride` → no hide.
- **testHideWindowTitleContainsStillFiresWithActiveAppOverride** — `.windowTitleContains` still fires under override.

### B. `hidesWindow` (bundle-id prefix gate + hide rule)
- **testHidesWindowWhenPrefixMatchesAndRuleFires** — `com.foo` exception hides `com.foo.bar` (prefix).
- **testDoesNotHideWhenPrefixDiffers** — non-matching prefix → no hide.
- **testDoesNotHideWhenBundleIdentifierEmpty** — empty exception bundle-id never matches.
- **testDoesNotHideWhenAppBundleIdNil** — nil app bundle-id → no hide.
- **testHidesWindowMatchesAnyExceptionInList** — any matching exception in the list suffices.
- **testDoesNotHideWhenRuleIsNoneEvenIfPrefixMatches** — prefix matches but `hide == .none` → no hide.
- **testActiveAppOverrideIgnoresAlwaysHide** — prefix matches `.always` but `activeAppOverride` → no hide.
- **testActiveAppOverrideStillHidesByWindowTitle** — `.windowTitleContains` hides even under `activeAppOverride`.

### C. `disablesShortcuts` (bundle-id prefix gate + ignore rule)
- **testDisablesShortcutsWhenIgnoreAlways** — `.always` → disabled.
- **testDisablesShortcutsWhenFullscreenAndFullscreen** — `.whenFullscreen` + fullscreen → disabled.
- **testDoesNotDisableWhenFullscreenRuleButNotFullscreen** — `.whenFullscreen` + not fullscreen → enabled.
- **testDoesNotDisableWhenIgnoreNone** — `.none` → enabled.
- **testDoesNotDisableWhenPrefixDiffers** — non-matching prefix → enabled.
- **testDoesNotDisableWhenAppBundleIdNil** — nil app bundle-id → enabled.
