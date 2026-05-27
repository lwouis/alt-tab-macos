# CustomRecorderControl (shortcut acceptance) — Specs

> **Line coverage:** `CustomRecorderControlTestable.swift` 78% · _refreshed 2026-05-27 by `/coverage-explore`_

## Summary

When the user records a shortcut in Settings, `CustomRecorderControlTestable.isShortcutAcceptable`
decides whether the recorded combination is allowed. It rejects unusable or conflicting combinations
before they're persisted, so the user can't bind something that won't work or that collides with an
existing AltTab shortcut or a macOS-reserved one.

## Behavior & edge cases

- A normal key+modifier combo is **accepted**.
- A "modifiers only" recording is rejected — *unless* it actually carries a keycode (the
  modifiers-only-but-contains-keycode case is accepted).
- A combo that **conflicts** with an already-bound AltTab shortcut is rejected.
- A combo **reserved by macOS** is rejected.
- Regression (#5585): a Cmd-based hold shortcut is **no longer blocked** by the macOS 26 Game Overlay
  reservation — that specific over-broad rejection was removed.

## Test scenarios

Mirrors `CustomRecorderControlTests.swift` 1:1.

- **testIsShortcutAcceptable_accepted** — a valid key+modifier combo is accepted.
- **testIsShortcutAcceptable_modifiersOnlyButContainsKeycode** — modifiers-only flags but with a real keycode → accepted.
- **testIsShortcutAcceptable_conflictWithExistingShortcut** — collides with an existing shortcut → rejected.
- **testIsShortcutAcceptable_reservedByMacos** — a macOS-reserved combo → rejected.
- **testIsShortcutAcceptable_cmdHoldShortcutNoLongerBlockedByGameOverlay** — regression #5585: a Cmd hold shortcut is accepted (Game Overlay no longer blocks it).
