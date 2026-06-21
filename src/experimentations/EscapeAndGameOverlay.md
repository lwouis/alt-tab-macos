# Escape key delivery & macOS 26 Game Overlay (issue [#5585](https://github.com/lwouis/alt-tab-macos/issues/5585))

## Problem

Reports of the cancel shortcut (`⎋`) being unreliable when AltTab's switcher is open, especially with `⌘`-based hold shortcuts. macOS 26 introduced "Game Overlay", which uses `⌘⎋` system-wide. We needed to know:

1. Which keyboard-listening API actually receives `⎋` (alone or with each modifier combo) on macOS 26.
2. Whether absorbing the event in our tap suppresses Game Overlay, or whether GO fires anyway.

The answer drives both the fix (which API we listen on) and a related cleanup (whether we still need a UI dialog warning users away from `⌘⎋` bindings).

## Method

Built a debug-only harness that installed seven listeners in parallel, each tagged with a unique label and logging keyCode + modifiers + whether the event was absorbed:

| Label | API | Notes |
|---|---|---|
| `nsLocal` | `NSEvent.addLocalMonitorForEvents(matching: [.keyDown])` | |
| `nsGlobal` | `NSEvent.addGlobalMonitorForEvents(matching: [.keyDown])` | Observe-only |
| `cgSession.head.default` | `CGEvent.tapCreate(.cgSessionEventTap, .headInsertEventTap, .defaultTap)` | Can absorb |
| `cgSession.head.listen` | same, `.listenOnly` | |
| `cgSession.tail.default` | `.tailAppendEventTap`, `.defaultTap` | After other taps |
| `cgAnnotated.head.default` | `.cgAnnotatedSessionEventTap`, `.headInsertEventTap`, `.defaultTap` | |
| `cghid.head.default` | `.cghidEventTap`, `.headInsertEventTap`, `.defaultTap` | Pre-WindowServer |

Plus a separate dumper that walked `CGSGetSymbolicHotKeyValue(0..<300)` to identify Game Overlay's symbolic hotkey ID by toggling GO on/off and seeing which ID flipped.

Tested on macOS 26.3.1 with multiple combos (`⎋`, `⌥⎋`, `⌘⎋`, `⇧⎋`), with the AltTab switcher open and closed, and with Game Overlay both enabled and disabled. For each `*.default` tap, both pass-through and absorb modes were tested.

## Findings

### Game Overlay's symbolic hotkey ID

On macOS 26.3.1: **id 260** is Game Overlay (`keyCode=53 modifiers=⌘`). Toggling GO in System Settings flipped only id 260 from disabled→enabled. ID 259 has the same key/mods but stays disabled regardless of the GO setting — likely a paired/legacy slot. If we ever needed to disable GO programmatically, we'd toggle both 259 and 260 via `CGSSetSymbolicHotKeyEnabled` to be safe.

### API reception (`⌘⎋` with switcher open, GO enabled, absorb OFF)

Only the following fired:

```
[exp] cghid.head.default ⌘+key=53 absorbed=false
[exp] cgSession.head.listen ⌘+key=53 absorbed=false
[exp] cgSession.head.default ⌘+key=53 absorbed=false
[exp] cgSession.tail.default ⌘+key=53 absorbed=false
```

**Did not fire:** `cgAnnotated.head.default`, `nsLocal-altTab` (instrumented inside `KeyboardEvents.addLocalMonitorForKeyDownAndKeyUp` to log before any absorb decision), `nsGlobal`, the experiment's own `nsLocal`.

This places Game Overlay's hook somewhere between the `cgSession` taps and `cgAnnotated`/WindowServer/app delivery. Once GO consumes the event, none of the user-facing event paths see it. AltTab's existing `addLocalMonitorForEvents`-based flow (which is downstream of GO) cannot bind `⌘⎋` no matter what — that's the original bug.

### Absorption at `cghid` suppresses everything downstream

With absorb mode ON at `cghid.head.default` (returning `nil` from a `.defaultTap`), only the cghid tap itself fired:

```
[exp] cghid.head.default ⌘+key=53 absorbed=true
```

All downstream taps (cgSession, cgAnnotated), the local/global NSEvent monitors, and Game Overlay all silent. `cghidEventTap` runs ahead of WindowServer and ahead of GO's hook, so absorbing there beats GO without needing to disable GO via private `CGSSetSymbolicHotKeyEnabled` calls.

### Other combos (`⎋`, `⌥⎋`, `⇧⎋`)

For combos GO doesn't intercept (`⎋`, `⌥⎋`, `⇧⎋`), all five CG taps fired in pass-through. AltTab's existing local monitor catches these fine. The `nsLocal` lines in the experiment trace looked absent because *AltTab's* local monitor (registered at app launch, ahead of the experiment's monitor in the chain) absorbs Esc events that match the cancel shortcut and returns `nil`, which short-circuits subsequent monitors. That's expected NSEvent monitor-chain behaviour, not the OS dropping the event.

## Decision

Use a single `cghidEventTap` + `.headInsertEventTap` + `.defaultTap` listening to both `.flagsChanged` and `.keyDown`, replacing the previous separate `cgSessionEventTap` + `.listenOnly` for flags. The shared callback in [`src/events/KeyboardEvents.swift`](../events/KeyboardEvents.swift) handles both event types: flag changes always pass through, Esc keyDowns are absorbed when `KeyboardEvents.anyShortcutUsesEscape && SwitcherSession.isActive`, and everything else passes through unchanged. `ControlsTab.recomputeEscapeAbsorption()` toggles the flag whenever the configured shortcuts change.

This makes binding `⌘⎋` work cleanly with Game Overlay enabled — no warning dialog, no private-API toggle of GO. The Force-Quit chords (`⌘⌥⎋`, `⌘⌥⇧⎋`, `⌘⌥⇧⌃⎋`) remain blocked at the recorder level because the OS hard-reserves them and we cannot intercept them this way.

The promotion from `.listenOnly` to `.defaultTap` is required for absorption; both options need only the Accessibility permission AltTab already has, and SecureInput continues to filter `.keyDown` (passwords aren't observed) while leaving `.flagsChanged` visible.

### Update (#5766): the keyDown tap must be session-gated, and the flags tap stays on cgSession

The first implementation merged everything into one always-on `cghidEventTap` + `.defaultTap` listening to `.flagsChanged` and `.keyDown`. That put an active HID-level keyDown tap (pre-WindowServer, ahead of input methods) in the path during all typing, for every user (Esc is the default cancel binding, so `anyShortcutUsesEscape` is true out of the box). It corrupted third-party input methods that run their own low-level keyboard tap; the Vietnamese IME EVKey mangled normal typing ([#5766](https://github.com/lwouis/alt-tab-macos/issues/5766)).

Reverted to two taps:
- Flags tap: back to the pre-11.0 `cgSessionEventTap` + `.listenOnly` (it never absorbs and modifiers aren't composed by IMEs, so it's harmless).
- Esc tap (`escapeEventTap`): `cghidEventTap` + `.defaultTap` + `.keyDown`, created disabled, enabled only while `anyShortcutUsesEscape && SwitcherSession.isActive` via `KeyboardEvents.updateEscapeAbsorptionTap()`. That gate is driven from `App.showUiOrCycleSelection` (open) and `App.hideUi` (close), plus `ControlsTab.recomputeEscapeAbsorption()` when bindings change. (The call lives in `App`, not a `SwitcherSession` `didSet`, because the `unit-tests` target compiles `SwitcherSession.swift` but not `KeyboardEvents.swift`.)

Esc absorption only ever mattered while the switcher is open, so this preserves #5585 exactly. During normal typing the keyboard tapping is now byte-identical to v10 (flags on cgSession+listenOnly, no active keyDown tap). Note: as of this writing the regression could not be reproduced on macOS 26.5; it reproduces on the reporter's macOS 15.7.7, so this build is what confirms whether the keyboard tap is the cause.

## Notes for future investigations

- `cghidEventTap` requires Accessibility permission (which AltTab already has). It does *not* require the separate Input Monitoring permission for the absorption case observed here.
- `NSEvent.addLocalMonitorForEvents` callbacks form a chain in registration order. Returning `nil` from any link stops the rest of the chain. When debugging, log inside the *first* registered handler (or temporarily register your debug monitor before everything else) — a second monitor cannot observe events the first one absorbed.
- The CG tap callback runs on a background thread (we put it on `BackgroundWork.keyboardAndMouseAndTrackpadEventsThread.runLoop`). The absorb decision must be synchronous; the matcher action itself can be dispatched async to main.
- One CG tap can listen to multiple event types. Adding `.keyDown` to an existing `.flagsChanged` tap is essentially free — the system fires the same callback with different `CGEventType` values, and we branch in the callback. There's no benefit to maintaining separate taps unless they need different placement (`.headInsertEventTap` vs `.tailAppendEventTap`) or different options (`.defaultTap` vs `.listenOnly`).
