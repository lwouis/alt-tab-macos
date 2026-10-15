# UsageStats (usage counts) — Specs

> **Line coverage:** `UsageStatsTestable.swift` 93% · _refreshed 2026-05-27 by `/coverage-explore`_

## Summary

The Pro windows and the switcher show usage counts ("Search uses during your trial: 1,234").
`UsageStatsTestable` formats those counts for display.

## Behavior & edge cases

- `formatCount` inserts thousand separators for display.

## Test scenarios

Mirrors `UsageStatsMessageTests.swift` 1:1.

- **testFormatCount_thousandSeparator** — large counts render with thousand separators.
