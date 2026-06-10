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
- A press (`nextWindowShortcut`) candidate is checked against the local shortcuts (arrow keys, vim
  keys, statics like Space) combined with its **own** hold — not just the other shortcuts' holds.
  A press edit replaces only the press, so the same-index hold's combinations stay in the "old"
  set; only a hold candidate excludes the hold it replaces.
- A combo **reserved by macOS** is rejected.
- Regression (#5585): a Cmd-based hold shortcut is **no longer blocked** by the macOS 26 Game Overlay
  reservation — that specific over-broad rejection was removed.
- The `candidateId` handed in must be a **well-formed bound preference key** (`isWellFormedCandidateId`):
  a `holdShortcut`/`nextWindowShortcut` id has to resolve to an in-range shortcut index. The recycled
  `ShortcutEditor` regression fed a frozen placeholder (`"nextWindowShortcut0"`, index -1) that matched
  nothing and silently returned `.accepted`, so the conflict dialog stopped appearing. A `#if DEBUG`
  assert now trips loudly if a malformed id ever reaches the check.

## Test scenarios

Mirrors `CustomRecorderControlTests.swift` 1:1.

### isShortcutAcceptable
- **testIsShortcutAcceptable_accepted** — a valid key+modifier combo is accepted.
- **testIsShortcutAcceptable_modifiersOnlyButContainsKeycode** — modifiers-only flags but with a real keycode → accepted.
- **testIsShortcutAcceptable_conflictWithExistingShortcut** — collides with an existing shortcut → rejected.
- **testIsShortcutAcceptable_holdChangeStripsOldHoldFromCombinedNextWindow** — changing a shortcut's hold (e.g. ⌘→⌥) so its chord now duplicates another shortcut is detected; the same-index nextWindow is stored COMBINED with the old hold, so the old hold is stripped before applying the new one (else ⌥⌘+Tab is compared instead of ⌥+Tab and the conflict is missed).
- **testIsShortcutAcceptable_pressConflictsWithLocalShortcutsUnderItsOwnHold** — recording a press that collides with a local shortcut (arrow keys, statics like Space) under the SAME shortcut's hold is rejected. Regression: the old-combos exclusion dropped the candidate's own hold, so the collision was only caught when another shortcut happened to share the same hold modifiers — the default double-⌥ holds masked the bug (⌥+→ flagged by luck), while ⌃+→ recorded with no conflict dialog after the arrow-keys toggle had unassigned it.
- **testIsShortcutAcceptable_reservedByMacos** — a macOS-reserved combo → rejected.
- **testIsShortcutAcceptable_cmdHoldShortcutNoLongerBlockedByGameOverlay** — regression #5585: a Cmd hold shortcut is accepted (Game Overlay no longer blocks it).

### isWellFormedCandidateId
Guards the recycled-`ShortcutEditor` regression where a stale recorder id (id/identifier drift) reached the conflict check and silently suppressed the dialog.
- **testIsWellFormedCandidateId** — hold/next ids must resolve to an in-range index; the `"…Shortcut0"` placeholders (index -1) and out-of-range ids are rejected; static/arrow/vim ids are always well-formed.

### combinedModifiersMatch
Used by the keyboard matcher to recognize a chord whose modifiers are physically split between the configured `holdShortcut` and a local shortcut (e.g. commandShiftTab = ⌘⌥-hold + ⇧).
- **testCombinedModifiersMatchEqualToItself** — a modifier set matches itself (trivial union).
- **testCombinedModifiersMatchUnifiesWhenHoldModifiersDominate** — two different inputs that produce the same union with the configured hold modifiers match.
- **testCombinedModifiersMatchRejectsDisjointModifiers** — modifier sets that can't be unified by any holdShortcut union don't match.
- **testCombinedModifiersMatchReturnsFalseWhenNoHoldShortcuts** — no holdShortcut configured at any slot → no union possible → false.

### Not tested: `Shortcut.keyEquivalent` (in `CustomRecorderControlTestable.swift`)
This getter is used in production by `ControlsTab.shortcutSummary` (to render the Settings sidebar row summary) — not "for testing only" as the older comment in the source incorrectly claimed (now fixed). It's effectively untestable from the `unit-tests` target: it calls ShortcutRecorder's `readableStringRepresentation(isASCII:)`, which throws `NSInternalInconsistencyException: Unable to find bundle with resources` when the framework's bundle isn't loaded (the case for unit tests). Testing it would need either bundle-loading test setup or extracting the formatting logic away from `readableStringRepresentation`. Left alone for now; recorded here so the 0% line coverage on this getter isn't mistaken for a forgotten gap.
