# UsageStats (Pro feature sessions) — Specs

> **Line coverage:** `UsageStatsTestable.swift` 93% · _refreshed 2026-05-27 by `/coverage-explore`_

## Summary

The Pro-transition prompts show "you've used Pro features N times." `UsageStatsTestable` computes that N
from raw timestamps: it collapses the per-trigger and per-feature timestamps recorded during a switcher
session into **distinct sessions**, so using several Pro features within one summon counts once, not
many times. It also formats large counts for display.

## Behavior & edge cases

- Multiple Pro features used in the **same** session collapse to a count of 1.
- A cycle-heavy single session still counts as 1.
- Two genuinely separate sessions count as 2.
- Feature timestamps are mapped back to the trigger session that owns them; a feature timestamp with no
  owning trigger (spurious) is intersected away.
- A search recorded before any trigger is skipped.
- Invariant: the session count never exceeds the number of triggers.
- `formatCount` inserts thousand separators for display.

## Test scenarios

Mirrors `UsageStatsMessageTests.swift` 1:1.

- **testEmpty_returnsZero** — no activity → 0.
- **testTriggersOnlyNoFeatures_returnsZero** — triggers but no Pro feature use → 0.
- **testAppIconsAndSearchInSameSession_countsOne** — two Pro features in one session → 1.
- **testCycleHeavySession_collapsesToOne** — lots of cycling in one session → 1.
- **testTwoDistinctSessionsWithDifferentFeatures** — two separate sessions → 2.
- **testSearchesMappedBackToOwningTriggers** — feature timestamps attributed to their owning trigger session.
- **testSpuriousFeatureTimestamp_intersectedAway** — a feature timestamp with no owning trigger is dropped.
- **testSearchBeforeAnyTrigger_skipped** — a search before any trigger doesn't count.
- **testSessionCountNeverExceedsTriggerCount** — the count is bounded by the number of triggers.
- **testFormatCount_thousandSeparator** — large counts render with thousand separators.
