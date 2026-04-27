# Bug: Escape / Cmd+Escape does not close the AltTab overlay

**Labels**: bug
**Related**: #5018, #1835, #44
**Status**: FIXED (branch `alkjdla`)

---

## Describe the bug

Pressing Escape (or hold-modifier+Escape) while the AltTab overlay is open does nothing.
The overlay stays open.

Verified repro: hold shortcut = Cmd, shortcutStyle = searchOnRelease (overlay stays open after
releasing hold key):
1. Press Cmd+Tab — overlay opens
2. Release Tab — overlay stays open
3. Press Escape — nothing happens

Option+Escape (with Option as hold shortcut) works correctly on the same machine, ruling out
a generic Escape-handling problem.

## Root cause (confirmed via debug log)

`cancelShortcut` is registered as `.local` scope via `NSEvent.addLocalMonitorForEvents`. This
only fires when `TilesPanel` is the key window. The Cmd+Escape event never appeared in the
debug log — it was dropped before `handleKeyboardEvent` was ever called.

`TilesPanel` uses `.nonactivatingPanel`, so `makeKeyAndOrderFront` gives it key focus without
activating the app. macOS (or competing processes) can revoke that key status before Escape is
pressed, silently dropping the event before the local monitor sees it.

**Why AltTab's existing CGEventTap doesn't help**: It is `.listenOnly` and only subscribed to
`flagsChanged` (modifier keys only, not `keyDown`). It cannot intercept Escape.

## Fix (implemented)

Added a second `CGEventTap` (`localShortcutEventTap`) with `.defaultTap` (can absorb) on
`keyDown` events, installed at `.headInsertEventTap` on `.cgSessionEventTap`. While
`App.appIsBeingUsed`, it calls `handleKeyboardEvent(..., localOnly: true)`, which skips
shortcuts with `scope == .global` (nextWindowShortcut, holdShortcut — already handled by
`RegisterEventHotKey` + `KeyRepeatTimer`) and only handles `scope == .local` shortcuts
(cancelShortcut etc.).

The `localOnly` restriction was required to fix a secondary regression: without it, the tap
also fired for Tab/Cmd+Tab, double-triggering `nextWindowShortcut` alongside the Carbon hotkey
handler and `KeyRepeatTimer`, causing infinite window cycling.

Key files:
- `src/logic/events/KeyboardEvents.swift` — `addCgEventTapForLocalShortcuts()`, `cgEventKeyDownHandler`
- `src/logic/events/KeyboardEventsTestable.swift` — `localOnly` parameter on `handleKeyboardEvent` / `triggerMatchingShortcuts`

## Ruled out

- Contexts.app — reproduces without it, on clean machines
- 1Password / Secure Input — reproduces on machines with no password manager
- Rectangle, other window managers — not required
- GameOverlay — Game Center disabled, Option+Escape works fine
- Single machine fluke — reproduces on multiple laptops
- Code bug in shortcut matching — `modifiersMatch` correctly handles Cmd+Escape if event arrives

## Separate bug (to file later)

When AltTab shows a "conflicting shortcut" warning for GameOverlay (Cmd+Escape), it opens
System Settings → Keyboard → Modifier Keys — the wrong pane. Also a false positive since
Game Center is disabled.

## Your environment

* AltTab version: 10.12.0
* macOS version: 15.x (Sequoia)
* Hold shortcut: Cmd
* Reproduces on: multiple machines, no competing apps needed
