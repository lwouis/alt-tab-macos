# SettingsSearchHighlight — Specs

> **Line coverage:** `SettingsSearchHighlight.swift` 92% · _refreshed 2026-05-27 by `/coverage-explore`_

## Summary

The Settings window has its own search box that filters + highlights matching controls. Two pieces make
that work and are pinned here:

- **Highlight targets** — a matched row reports whether the query matches its label and, if so, paints
  the search-match color over the matched range (and clears back to plain when the query changes). Works
  for both `NSTextField` rows (sidebar) and `LightLabel` rows (rounded sections).
- **Inline index registration** — the row-title factory (`TableGroupView.makeText`) must, as a side
  effect of construction, register its string + a highlight target into the active
  `SettingsSearchIndex.Builder`. This push-based, scoped registration is the same contract
  `SidebarListRow` relies on; its absence was the sidebar-search regression these tests guard.

## Behavior & edge cases

- A target reports a match only when the label is non-empty and contains the query; an empty label
  yields a nil target.
- Highlighting applies the search color to exactly the matched range and fully reverts on clear.
- `makeText` registers into whatever builder is active; called **outside** an indexed scope (no active
  builder) it silently no-ops. Content rebuilt after the section's build scope (sidebar rows recreated
  by `refreshShortcutRows`) is therefore re-published through `SettingsWindow.refreshSectionSearchContent`,
  which re-opens an `indexed { ... }` scope — see [[SettingsSectionSearchContent]].

## Test scenarios

Mirrors `SettingsSearchHighlightTests.swift` 1:1.

### Tier A — NSTextField highlight target (sidebar rows)
- **testTextFieldTargetReportsMatch** — a matching field reports a match.
- **testTextFieldTargetIsNilForEmptyLabel** — an empty label yields no target.
- **testTextFieldHighlightAppliesSearchColorToMatchedRange** — the match color is applied to the matched range.
- **testTextFieldHighlightClearsBackToPlain** — clearing the query reverts the styling.

### Tier A — LightLabel highlight target (rounded-section rows)
- **testLightLabelTargetAppliesAndClearsRanges** — apply + clear highlight ranges on a `LightLabel`.

### Tier B — factory ⇄ index registration wiring
- **testMakeTextRegistersStringAndTargetInActiveBuilder** — `makeText` pushes its string + target into the active builder (the regression guard).
- **testMakeTextOutsideIndexedScopeDoesNotCrashOrLeak** — with no active builder, `makeText` silently no-ops.
