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
- **`enable` means "release", not "switch on".** It is the set AltTab has no claim on, which is not the
  same as the set that should end up enabled — see the ownership section below.
- **⌘⇥ pairing.** Disabling `.commandTab` implicitly disables `.commandShiftTab` too, so the native
  reverse switcher doesn't fire while AltTab owns ⌘⇥.
- **No globals.** `combinedModifiersMatch` previously read `ControlsTab.shortcuts` to find the hold
  modifiers; the kernel takes them as an explicit `holdShortcutModifiers: [UInt32]` parameter, so the
  resolver is independent of any global state.
- **Primitive value record.** `ShortcutSnapshot` uses `UInt32` for both modifiers and keycode (no
  ShortcutRecorder / `Shortcut` types) so the kernel file compiles in the unit-tests target.

## Ownership — `NativeHotkeyOwnership`

Whether a symbolic hotkey is enabled is global state the user owns through System Settings > Keyboard
> Keyboard Shortcuts, and `CGSSetSymbolicHotKeyEnabled` persists it after AltTab quits. So the
resolver's `enable` set can only mean *"AltTab releases its claim on these"*; acting on it by calling
`CGSSetSymbolicHotKeyEnabled(_, true)` overwrites the user's own choice.

Issue #5455 is that overwrite: a user who had turned ⌘\` off got it switched back on by AltTab, after
which WindowServer consumed ⌘\` before either AltTab's Carbon hotkey or its shortcut recorder could
see it — so the shortcut looked unassignable, and reassigning it in System Settings didn't stick.

`NativeHotkeyOwnership` tracks which hotkeys AltTab itself switched off:

- **Claim before disabling.** A hotkey is claimed only if AltTab doesn't already own it *and*
  `CGSIsSymbolicHotKeyEnabled` reports it on. One the user had already turned off is never claimed, so
  AltTab will never turn it on.
- **Restore only what's owned.** `restoreNativeHotkeys` intersects its argument with the owned set, so
  a hotkey AltTab never disabled is never touched. This is what makes the default-argument call in
  `applicationWillTerminate` and `emergencyExit` safe.
- **Idempotent.** `toggleNativeCommandTabIfNeeded` runs on every shortcut edit; claiming an owned
  hotkey or releasing an unowned one is a no-op.
- **In-memory only.** Ownership doesn't survive a crash, so a hard kill can leave a hotkey off. The
  next launch re-disables it from the same config and restores it on a clean quit; only a crash
  followed by unbinding the shortcut leaks, and the user can flip it back in System Settings. Making
  this durable means persisting the set, which isn't worth the migration for that window.

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

### F. Issue #5455 — ownership (`NativeHotkeyOwnershipTests`)
- **testDoesNotEnableAHotkeyTheUserDisabled** — the regression: a hotkey the user had off is never
  claimed, and releasing everything leaves it off.
- **testRestoresOnlyWhatItDisabled** — the normal path: claim ⌘⇥, then restore exactly ⌘⇥.
- **testClaimingAnAlreadyOwnedHotkeyIsANoop** — repeated shortcut edits don't re-issue a claim.
- **testReleasingTwiceOnlyRestoresOnce** — quitting after settings already released restores nothing.
- **testPartialReleaseKeepsOtherHotkeysOwned** — dropping ⌘⇥ while ⌘\` stays bound keeps ⌘\` owned.
- **testClaimsOnlyTheHotkeysThatWereOn** — of two requested, only the one that was on is claimed.
