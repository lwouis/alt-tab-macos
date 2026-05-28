# OverrideClickResolver — Specs

> **Line coverage:** `OverrideClickResolver.swift` 93% · _refreshed 2026-05-27 by `/coverage-explore`_

## Summary

In Settings, each shortcut can **override** the global Appearance values (style / size / theme /
shortcut-style). A segmented control shows either the global value (no override) or the override value.
`OverrideClickResolver.decide` is the pure kernel for "what should a click on that segment do": given the
clicked index, whether an override is currently set, the stored override value, the current global index,
and a `valueAtIndex` encoder, it returns `.skip` (no change) or `.write(value:)` (set/update the override).

The key invariant it encodes (the rules the user stated): an override's **set/unset state** and its
**value** are independent. Clicking the currently-displayed value never changes state; clicking a
different value writes/updates the override; and the *only* way to unset an override is the link button
(never modeled as a click here).

## Behavior & edge cases

- **Displayed value is derived from `hasOverride` + `globalIndex`**, not from `UserDefaults`. This matters
  because the registered default for an override key can differ from the global — comparing against
  `UserDefaults` (the old bug) wrote/skipped incorrectly.
- A `.write` re-encodes the new index via `valueAtIndex` (the persisted string isn't assumed to equal the
  index).
- A malformed stored override (non-Int string) is treated as "displayed = -1", so a click still writes
  (corrupt defaults don't silently turn every click into a no-op).
- `nil` stored value with no override falls back to the global as the displayed value.

## Test scenarios

Mirrors `OverrideClickResolverTests.swift` 1:1.

### Rule 1 — clicking the displayed value is a no-op
- **testNoOpWhenClickingDisplayedGlobal** — override unset, click the displayed global → `.skip`.
- **testNoOpWhenClickingDisplayedOverride** — override set, click the displayed override value → `.skip`.
- **testOverrideStaysSetWhenItsValueMatchesGlobal** — override set to a value that *coincides* with the global; clicking it stays `.skip` (set-state survives; only the link button unsets).
- **testNoOpWhenRegisteredDefaultDiffersFromGlobal** — displayed = global even when the registered default differs → `.skip` (regression: don't compare against `UserDefaults`).

### Rule 2 — clicking a different value writes the override
- **testWriteOverrideOnClickAwayFromGlobal** — override unset, click a different value → `.write`.
- **testWriteOverrideOnClickAwayFromExistingOverride** — override set, click a different value → `.write` (still set, new value).
- **testWritesOverrideWhenClickValueEqualsRegisteredDefault** — new value equals the registered default but differs from global → `.write` (regression: previously skipped).
- **testWriteOverrideEvenWhenNewValueMatchesGlobal** — new value coincidentally equals the global but differs from the current override → `.write` (stays set).

### Encoding & defensive handling
- **testValueAtIndexEncoderIsHonored** — the persisted string comes from `valueAtIndex`, not the raw index.
- **testStoredOverrideMalformedFallsThroughToWrite** — corrupt stored value (non-Int) → treated as displayed -1 → `.write`.
- **testNilStoredOverrideWithMatchingGlobalIsSkip** — nil stored value, override unset, click the global → `.skip`.
- **testHasOverrideTrueWithNilStoredFallsThroughToWrite** — inconsistent state (override marked SET but stored value is nil) → treated as displayed -1 → `.write` (defensive: don't silently no-op).
