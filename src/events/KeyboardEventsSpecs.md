# KeyboardEvents (sequencing) — Specs

> **Line coverage:** `KeyboardEventsTestable.swift` 65% · _refreshed 2026-05-27 by `/coverage-explore`_

## Summary

Global hotkey handling has to make sense of a *stream* of key-down / key-up / modifier events that the
OS doesn't always deliver cleanly. `KeyboardEventsTestable` is the state machine that interprets those
sequences — deciding when to summon the switcher, cycle, act on a window, or dismiss — and stays robust
when events are missing or arrive out of order. The suite feeds it canned event sequences and asserts
the resulting actions.

## Behavior & edge cases

- The common flows (hold modifier → press next-window key → release) resolve to the expected
  summon/cycle/focus actions.
- **Missing events**: when an expected event is dropped, the machine recovers where it safely can
  ("save the day") and otherwise degrades predictably ("can not save the day").
- **Out-of-order events** are tolerated.
- In-switcher shortcuts (close window) act on the selection.
- Release behavior depends on style: `doNothingOnRelease` doesn't focus; the search-on-release path does
  **not** focus the window on release (it enters search instead).
- Switching directly from one shortcut slot to another is handled.
- **Escape**: while the switcher is active (e.g. Option held), Escape fires the cancel shortcut; when the
  switcher is closed, Escape does nothing (AltTab doesn't swallow it).

## Test scenarios

Mirrors `KeyboardEventsTests.swift` 1:1.

- **testMostCommonSequence** — the canonical hold-modifier → next-window → release flow.
- **testSecondMostCommonSequence** / **testSecondMostCommonSequenceVariation** — the next most common flows resolve correctly.
- **testSequenceWithMissingEventAndWeCanSaveTheDay** — a dropped event the machine can recover from.
- **testSequenceWithMissingEventAndWeCanNotSaveTheDay** — a dropped event it can't recover from → predictable degradation.
- **testOutOfOrderEvents** — events arriving out of order are handled.
- **testLostHoldReleaseIsSettledBeforeTheNextSummonCycles** — a lost modifier-up is honoured on the tile the user saw, before the next summon's key-down cycles the selection.
- **testRecordedReleaseSettlesTheSessionOpenedByItsDelayedHotkey** — a Carbon hotkey delayed behind main-thread work still commits its own physically completed gesture.
- **testInputLogSeparatesTwoPairsButKeepsTwoTabsUnderOneHoldTogether** — two complete Option-Tab pairs remain two sessions, while two Tab taps under one held Option remain one session.
- **testInputLogDoesNotClaimAKeyDownFromBeforeRegistrationChanged** — input observed while a shortcut was unregistered cannot commit a later gesture.
- **testInputLogDoesNotLetALateKeyDownPoisonTheNextGesture** — a passive-tap key-down that arrives after Carbon claimed it is consumed instead of shifting every later pairing.
- **testInputLogIgnoresAutoRepeatsSoAHeldTabDoesNotShiftLaterPairs** — a held Tab's OS auto-repeats are not logged (Carbon never reports them), so two pairs delayed after the hold still each pair with their own release.
- **testInputLogDropsAnUnmatchedClaimAtTheGestureRelease** — if the passive tap never supplies a key-down, its unmatched Carbon claim expires with that physical gesture.
- **testInputLogRecordsOnlySwitchingChordsSoTypingCannotEvictADelayedHotkey** — key-downs that are not a registered switching chord are never recorded, so shifted typing during a stall neither fills the log nor evicts the hotkey's own key-down.
- **testInputLogMatchesTheChordWithCapsLockLit** — Caps Lock in the tap's flags does not stop a hotkey pairing with its physical key-down.
- **testCloseWindowShortcut** — the close-window shortcut acts on the selection mid-session.
- **testOnReleaseDoNothing** — `doNothingOnRelease` style: releasing the modifier doesn't focus.
- **testOnReleaseToggleSearchModeDoesNotFocus** — search-on-release: releasing enters search, doesn't focus the window.
- **testTransitionFromOneShortcutToAnother** — switching slots mid-stream is handled.
- **testEscapeFiresCancelShortcutWhileSwitcherActiveWithOptionHeld** — Escape → cancel while active.
- **testEscapeDoesNothingWhenSwitcherIsClosed** — Escape is a no-op when the switcher is closed.
