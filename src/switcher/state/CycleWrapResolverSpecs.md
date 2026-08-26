# CycleWrapResolver — Specs

## Summary

`CycleWrapResolver.blocksWrap` is the pure decision for "may this selection advance wrap around the end
of the list?". `Windows.cycleSelectedWindowIndex` (index cycling) and `TilesView.nextRow` (row
navigation) both ask it; the rule used to be written out twice, once in each, and neither copy was
covered by a test.

## The rule

An advance is refused only when it would actually wrap, AND one of:

1. the caller forbids wrapping (`allowWrap: false` — row-bounded navigation),
2. the OS marked the driving key event as an auto-repeat (`NSEvent.isARepeat`),
3. the advance is one of `KeyRepeatTimer`'s synthesized ticks.

2 and 3 are the same intent from two sources: **holding** a key walks to the end and stops there, rather
than looping under the user's fingers. Everything else — every discrete press — wraps.

## Why the repeat signal is per-advance, not per-session

The obvious signal for 3 is "does `KeyRepeatTimer` currently have a timer armed?" (`!timerIsSuspended`).
It is wrong, and it broke backwards cycling.

`KeyRepeatTimer` synthesizes repeats for shortcuts with **no keycode of their own**, which get no OS
key-repeat. The default `previousWindowShortcut` is exactly that: the bare modifier `⇧`. A modifier-only
shortcut's `state` is decided by `ATShortcut.matches` from the event's modifiers alone, so it stays
`.down` for as long as ⇧ is physically held — `stopRepeatIfUp` never fires, and the timer stays armed for
the whole hold.

So during a ⇧ hold, "a timer is armed" is true for *every* backwards advance, including real ⌥⇧+⇥
presses. Those presses were read as repeats and refused a wrap: backwards cycling dead-ended on the first
tile, and the only way to get one more wrap was to release ⇧ and press it again.

Forward cycling had no equivalent dead-end, which is what made the asymmetry visible. `nextWindowShortcut`
carries a real keycode, so the local monitor reports `keyCode: nil` on key-up, `matches` flips its state
to `.up`, and each ⇥ release suspends the timer — leaving it suspended when the next tap is handled.

Armed-ness is a fact about the session. Being a repeat is a fact about a single advance, so
`KeyRepeatTimer.isFiringArtificialRepeat` is set only for the duration of a tick's `block()` call.

Note that the config lwouis recommends in #5924 / #5914 — rebinding *Select previous window* from `⇧` to
`⇧⇥` — never hit this: a shortcut with a keycode gets real OS key-repeat, so
`startRepeatingKeyPreviousWindow` declines to arm a timer at all.

---

## Test scenarios

Mirrors `CycleWrapResolverTests.swift` 1:1.

- **testADiscretePressWrapsWhileAHeldModifierKeepsTheRepeatTimerArmed** — the bug: a press is not a
  repeat, whatever the timer is doing.
- **testASynthesizedRepeatStopsAtTheEndInsteadOfWrapping** — hold-to-cycle still stops at the end.
- **testAnOsKeyRepeatStopsAtTheEndInsteadOfWrapping** — same, for shortcuts that get real OS repeats.
- **testAnAdvanceThatDoesNotReachTheEndIsNeverBlocked** — the rule only ever suppresses a wrap.
- **testWrapIsRefusedWhenTheCallerForbidsIt** — `allowWrap: false` (row-bounded navigation).
