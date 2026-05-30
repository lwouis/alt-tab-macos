# SettingsSectionSearchContent — Specs

## Summary

Holds a Settings section's searchable content as two parts:

- **base** — captured once during the section's build-time `SettingsSearchIndex.indexed { }` scope
  (section title, dropdowns, buttons, static labels). Immutable for the session.
- **dynamic** — content rebuilt while the section is live and re-published wholesale via `setDynamic`.
  This is where a section parks sidebar rows that get torn down and recreated after the initial build
  (ControlsTab's "Shortcut 1" / "Shortcut 2" rows). Those rows are deliberately skipped by the
  build-time walk so they live *only* here, and every rebuild swaps the dynamic part out completely.

This is the fix for the regression where typing "sho" stopped highlighting rebuilt shortcut rows:
the recreated rows' inline registration no-ops outside the build scope, and the base targets kept
pointing at the removed labels. Re-publishing the current rows into the dynamic part — replacing,
not appending — keeps highlight targets in sync with the live rows.

## Behavior & edge cases

- `matches` is true for an empty query, or when any base **or** dynamic string/target matches.
- `setDynamic` **replaces** the dynamic part: targets for removed rows are dropped (no stale
  targets), and newly-added rows become searchable immediately.
- `highlightMatches` / `clearHighlights` drive both base and dynamic targets.
- A section with no dynamic content behaves exactly like its base.

## Test scenarios

Mirrors `SettingsSectionSearchContentTests.swift` 1:1.

- **testEmptyQueryAlwaysMatches** — an empty/whitespace query matches regardless of content.
- **testBaseStringIsSearchable** — a base string drives a match.
- **testDynamicStringIsSearchable** — a string published via `setDynamic` drives a match.
- **testDynamicTargetReportsAndHighlightsMatch** — a dynamic highlight target both reports a match and gets highlighted by `highlightMatches`.
- **testSetDynamicReplacesAndDropsStaleTargets** — re-publishing recreated rows replaces the dynamic part: the new rows match and highlight, the previous rows are gone (the "rebuilt Shortcut N rows still highlight" regression).
- **testSetDynamicReplaceDoesNotAccumulate** — replacing dynamic content twice leaves only the latest set, never the union.
- **testClearHighlightsClearsDynamicTargets** — `clearHighlights` reverts dynamic targets too.
