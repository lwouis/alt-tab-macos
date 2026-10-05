# WindowEventReducer — phantom-pass effects — Specs

## Summary

Covers the effects `WindowEventReducer.cgsWindowListsRead` emits when the CGS phantom pass flips a
window's DERIVED phantom. Specs + Tests without a same-named kernel (like `RealWorldScenarios`): the
subject is the reducer's effect emission, not a pure function of its own.

Driven through `WindowEventReducer.reduce` directly rather than the replay harness, because
`.removeWindowlessPlaceholder` is a display-side effect that `TestReducerRunner` deliberately swallows
(it has no model content) — so a scenario replay cannot observe it.

## Why this exists (#5849)

An app whose only window looks phantom is indistinguishable from an app with no windows, so a windowless
placeholder tile is added for it. When the window later un-phantoms, that placeholder is stale and must be
dropped. Four sites did this, all of them Space paths (`applySpaceMembershipDelta`, `applyWindowSpaces`).

The CGS-list pass, which owns the authoritative verdict and is the path that actually clears an Electron
app's latch, did not. So Slack ended up with a real tile AND a windowless tile, permanently: "it appears
twice in the list and won't change even if I wait or switch windows".

The same capture showed the second half of the bug. Slack, reopened from the Dock, keeps its window tagged
invisible by CGS for seconds after it is already composited. The WindowServer ordered-in bit states that
physical fact directly, so the weak CGS tag cannot flag an on-screen surface. This no longer depends on MRU
or app-frontmost guesses.

---

## Test scenarios

Mirrors `WindowEventReducerPhantomTests.swift` 1:1.

### Snapshot scope

The two CGS lists are a bulk answer about the wid set captured when the scan was issued. A window appended
while the calls are in flight was never queried, so its absence is silence rather than the strong phantom
signal. Positive list membership may still apply outside the captured set. The scan also carries an issue
sequence, and an older whole answer is dropped before it can replace a newer one or erase targeted inventory
updates.

- **testSnapshotSilenceDoesNotJudgeAWindowCreatedAfterIssue** — an absent wid outside `queried` keeps its
  existing verdict.

### A. Un-phantoming drops the app's stale windowless placeholder
- **testUnphantomingEmitsRemoveWindowlessPlaceholder** — a latched-phantom window seen in both CGS lists
  clears its verdict and emits `.removeWindowlessPlaceholder`. The regression guard for the duplicate tile.
- **testBecomingPhantomDoesNotEmitRemoveWindowlessPlaceholder** — the reverse flip (real → phantom) emits
  nothing: the app is becoming windowless, which is exactly when the placeholder is legitimate.
- **testNoFlipEmitsNothing** — a steady-state pass emits nothing, so repeated CGS reads don't churn the list.

### B. An on-screen window is never a phantom
- **testOnScreenWindowSurvivesTheOrderedOutSignal** — the window is ordered in while CGS still tags it
  invisible and reports no Space (Slack reopened from the Dock, #5849) → not a phantom. This replaced a
  FOCUS exemption, which made the verdict depend on MRU order.
- **testOrderedOutWindowIsFlaggedEvenWhenItsAppIsFrontmost** — the same window while the WindowServer is not
  showing it → phantom, frontmost or not.
- **testOrderedOutWindowOfBackgroundAppIsFlagged** — and with the app in the background, so both halves of
  the former focus rule stay pinned.
- **testOrderInUnphantomsAndDropsThePlaceholder** — the un-phantom edge now rides the WindowServer order-in,
  ~250ms before the CGS pass would run, so the placeholder must be dropped from there.
- **testOrderOutAloneDoesNotPhantomAWindowThatStillHoldsASpace** — the reverse is deliberately NOT symmetric:
  going off screen is not evidence on its own (a minimize, a Space move and an app-hide all look like it),
  so only the authoritative pass may latch a phantom.

### C. Attention clears a stale verdict immediately

The exemption in B is only consulted when the CGS pass runs, and that pass runs on a show, landing a beat
AFTER the switcher appears. So it does not cover the fast path the reporter actually hit: open Slack, tap
the shortcut straight away, and the switcher is built while the stale verdict still hides the window that
was just focused. A committed attention decision is proof the window is real, so the verdict is cleared at
that moment instead of waiting for a pass (`TrackedWindowState.clearPhantomOnFocus`).

- **testAttentionRefreshesAlphaWithoutAssumingTheWindowIsOpaque** — attention on a window cached at alpha zero requests a fresh WindowServer read. It preserves the cached value until that read answers, so a genuinely transparent window stays phantom.
- **testAttentionClearsAStalePhantomLatch** — a latched-phantom window attention lands on is real
  immediately.
- **testAttentionUnphantomingEmitsRemoveWindowlessPlaceholder** — that un-phantoming also drops the app's
  stale placeholder, so the fast path doesn't trade the wrong-window bug for the duplicate-tile one.
- **testAttentionOnARealWindowEmitsNoPlaceholderRemoval** — an already-real window emits nothing, so
  ordinary switching doesn't churn.

### D. The same, for the window a reopened app comes back to (#5849, second report)

Reopening Slack from the Dock reaches the front through an activation that names only the process. The
attention model uses Slack's cached focused-window fact, or requests one bounded `kAXFocusedWindow` read if
no fact exists. While that answer used to bump MRU straight from the shell it bypassed the clear in C, so the
latch survived — the switcher summoned 130 ms later hid the window the user was looking at while it held slot
0, and the default pick skipped past it onto a third app. Every namer now reaches the model through
`.attentionCommitted`, so there is one path and one clear.

- **testTheReopenedWindowsLatchIsCleared** — the app's answer fronts the window, clears its latch, and drops
  the placeholder its app grew.

Which answers are worth anything is not decided here any more. `kAXFocusedWindow` reports "which window
WOULD take keys", which every app has at all times, so an answer from an app the user is not in is a fact
about that app rather than a bid for the front (#5785, a re-discovered QQ window offered as "the window you
were on before"). That gate lives in `AttentionModel` —
`testAnAnswerFromABackgroundAppIsRecordedAndMovesNothing` — and the reducer only sees what it committed.

### E. An app whose last window turns phantom gets its placeholder in the SAME pass

The other half of the placeholder's lifecycle had no owner. Adding it was left to the shell's per-app sweep,
which runs in the same block as the CGS fetch but BEFORE the verdicts are applied, so it judged "does this
app still have a real window?" against the previous latch. Closing Slack's window therefore gave three
different switchers in three consecutive summons: the corpse re-discovered as an open window, then nothing
at all for that app, then finally the closed-app icon.

- **testLastWindowTurningPhantomEmitsAddWindowlessPlaceholder** — the app is now windowless, so the verdict
  that made it so emits `.addWindowlessPlaceholder`.
- **testPhantomWithAnotherRealWindowLeftEmitsNoAdd** — one window of several turning phantom leaves the app
  something to show, so no placeholder (the duplicate tile, in the other direction).
- **testUnphantomingEmitsNoAdd** — the opposite edge never adds one.
