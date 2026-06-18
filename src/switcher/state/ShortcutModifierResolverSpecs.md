# ShortcutModifierResolver — Specs

## Summary

`ShortcutModifierResolver` is the pure decision kernel for `ATShortcut.modifiersMatch`: given a
keyboard event's modifier set and a configured shortcut's modifiers, does the event match the
shortcut? Extracted from `ATShortcut` so its branch order is unit-tested (same rationale as
`NativeHotkeyResolver`, #5653). `ATShortcut` is the thin adapter that gathers the inputs from
`SwitcherSession` (is a session active, which hold modifiers apply), `ControlsTab`, and `TilesView`
(is the search field being edited), then calls this kernel.

All modifier arguments are *cleaned* Carbon bitmasks (`CarbonModifierFlags.cleaned()`). The kernel
only compares bits, so tests use opaque bit values.

## Branch order (matters — tested)

1. **holdShortcut** — the event must contain *at least* the shortcut's modifiers (`event == event | shortcut`).
   This is the "is the activation modifier held" check, so extra modifiers don't disqualify it.
2. **nextWindowShortcut while a session is active** — also match the base key with the hold modifiers
   stripped (`event == shortcut & ~hold`), so a configured ⌥⇥ keeps cycling on bare ⇥ once the switcher
   is already showing. Only consulted when `sessionActive`; falls through otherwise.
3. **search-editing gate for modifier-only shortcuts** — while editing the search field, a bare
   modifier-only shortcut (e.g. the default `previousWindow = ⇧`) is uppercasing input, not a command,
   so it must not fire on its own; it is routed through `SearchModeResolver.editingShortcutMatch`
   (`isPrintable: true`), which requires the hold modifiers (⌥⇧). This closes the #5781 gap: modifier-only
   shortcuts arrive as `flagsChanged` (no keyDown), so they bypass `TilesView.handleSearchEditingKeyDown`
   and would otherwise fire on the bare modifier, making capitals untypeable in search. The gate is
   **editing-only** and **modifier-only**: key shortcuts (close = W, etc.) keep default matching here
   because they're already gated upstream in `routeKey`.
4. **default** — exact match, or exact + hold (`event == shortcut || event == shortcut | hold`).

---

## Test scenarios

Mirrors `ShortcutModifierResolverTests.swift` 1:1.

### A. holdShortcut ("contains at least")
- **testHoldShortcutMatchesWhenEventContainsItsModifiers** — shortcut ⌥, event ⌥⌘ → matches (extra modifier allowed).
- **testHoldShortcutFailsWhenEventMissingItsModifiers** — shortcut ⌥, event ⌘ → no match.

### B. nextWindowShortcut base key (hold stripped) while a session is active
- **testNextWindowMatchesBaseKeyWithoutHoldDuringSession** — shortcut ⌘⌥, hold ⌥, event ⌘ → matches the base key.
- **testNextWindowBaseKeyNotMatchedWithoutSession** — same inputs, no session → falls through to default → no match.

### C. Search-editing gate for modifier-only shortcuts (previousWindow = ⇧, #5781)
- **testModifierOnlyBareDoesNotMatchWhileEditing** — modifier-only, editing, bare ⇧ → does NOT match (types a capital). The regression guard.
- **testModifierOnlyWithHoldMatchesWhileEditing** — modifier-only, editing, ⌥⇧ → matches (navigates).
- **testModifierOnlyBareMatchesWhenNotEditing** — modifier-only, not editing, bare ⇧ → matches (normal session navigates).

### D. Default matching (exact, or exact + hold)
- **testKeyShortcutMatchesExactModifiers** — shortcut ⌘, event ⌘ → matches.
- **testKeyShortcutMatchesShortcutPlusHold** — shortcut none, event ⌥ (e.g. closeWindow = W as ⌥W) → matches.
- **testKeyShortcutFailsWithExtraModifier** — shortcut ⌘, event ⌘⇧ → no match.
- **testKeyShortcutNotGatedWhileEditing** — key shortcut (not modifier-only) while editing → default matching still applies (gated upstream in `routeKey`, not here).
