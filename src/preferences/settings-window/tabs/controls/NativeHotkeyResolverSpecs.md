# NativeHotkeyResolver — Specs

## Summary

AltTab triggers its switcher via a Carbon `RegisterEventHotKey`. A native macOS symbolic hotkey
(⌘⇥ / ⌘⇧⇥ / ⌘`), when enabled, is consumed by the Dock/WindowServer **before** any app-level
Carbon hotkey — so binding ⌘⇥ to AltTab requires disabling the corresponding native one.

`NativeHotkeyResolver.resolve` is the pure kernel for that decision: given the configured shortcuts
(as `ShortcutSnapshot` value records) and the modifier flags of the active hold-shortcuts, it
returns disjoint `disable` / `enable` sets over `CGSSymbolicHotKey`. `ControlsTab.toggleNativeCommandTabIfNeeded`
is a thin adapter that builds the inputs from `ControlsTab.shortcuts` and applies the result via
`setNativeCommandTabEnabled`.

The kernel encodes one invariant the previous in-place code got wrong (issue #5653): **a single
shortcut can overlap multiple native predicates and must contribute to all of them.** ⌘⇥ matches
`.commandTab` exactly *and* `.commandShiftTab` via `combinedModifiersMatch` whenever a hold-shortcut
carries shift (the user's second-shortcut scenario). The previous `.first { … }` over a dictionary
of predicates picked one and dropped the others, with the pick varying per process (Swift dictionary
iteration order isn't stable across launches) — leaving native ⌘⇥ enabled for whole sessions.

## Behavior & edge cases

- **Collect, don't pick.** Every native predicate a shortcut matches contributes to `disable`; nothing
  is dropped. The `enable` set is the complement over `CGSSymbolicHotKey.allCases`.
- **⌘⇥ pairing.** Disabling `.commandTab` implicitly disables `.commandShiftTab` too, so the native
  reverse switcher doesn't fire while AltTab owns ⌘⇥.
- **No globals.** `combinedModifiersMatch` previously read `ControlsTab.shortcuts` to find the hold
  modifiers; the kernel takes them as an explicit `holdShortcutModifiers: [UInt32]` parameter, so the
  resolver is independent of any global state.
- **Primitive value record.** `ShortcutSnapshot` uses `UInt32` for both modifiers and keycode (no
  ShortcutRecorder / `Shortcut` types) so the kernel file compiles in the unit-tests target.

## Test scenarios

Mirrors `NativeHotkeyResolverTests.swift` 1:1.

### A. Issue #5653 — overlapping ⌘⇥ + ⌘⇧⇥ + hold ⌘ + ⌘⇧
- **testCommandTabAndCommandShiftTabBothDisableNativeSwitchers** — the user's stuck-session
  config; both `.commandTab` and `.commandShiftTab` must end up disabled, regardless of which
  predicate the ⌘⇥ snapshot was visited under first.
- **testResolutionIsDeterministicAcrossRepeatedCalls** — repeated calls on the same inputs always
  return the same sets (no dependence on map iteration order).

### B. Single ⌘⇥ — still pairs with ⌘⇧⇥
- **testCommandTabAloneAlsoDisablesReverseSwitcher** — binding ⌘⇥ alone still suppresses native
  ⌘⇧⇥ via the pairing rule.

### C. ⌘` alone — disables only that hotkey
- **testCommandKeyAboveTabAloneDisablesOnlyThatHotkey** — no cross-talk between Tab and grave-key
  predicates; only `.commandKeyAboveTab` is disabled.

### D. Default option config — no native switcher overlap
- **testOptionTabDoesNotOverrideNativeSwitchers** — AltTab's default ⌥⇥ / hold ⌥ doesn't overlap
  any native command-tab hotkey, so every native hotkey stays enabled.

### E. Empty config — nothing to override
- **testEmptyConfigReleasesAllNativeHotkeys** — defensive: no shortcuts ⇒ no native hotkey disabled.
