# Attention driver — Specs

Turns the reducer's input stream into `AttentionModel` inputs, holds the model's state, and allocates the
arrival sequences the model compares. Every decision belongs to the kernel; this decides only what each event
MEANS.

The translation is the architecture. The reducer's vocabulary is shaped by where an event came from; the
model's by what it says about the user. Four groups:

- **a plain activation names an app and nothing else** — `frontProcessChanged`, never a window. When AltTab
  asked that app for the switch and is still waiting to hear where focus landed, it is
  `frontProcessChangedAwaitingAnswer`: same app, and the app's cached answer is left out of it because it
  predates the switch
- **a namer names a window of one app** — the click, and the app answering about itself. AltTab's own switch
  is not a namer: it is heard through the activation and the app's answers, like any other switch
- **an app failing to answer names nothing, and says so** — the bounded read coming back empty is
  `focusedWindowUnknown`, which is a value rather than a silence
- **everything else names nothing** — the WindowServer's order and focus family, geometry, Spaces, discovery,
  tab reads. Physical lifecycle may invalidate a dead cached wid; no physical input can name attention, so
  the rest map to an empty list rather than to a rule that refuses them.

## Scenarios

### A. What is not attention

- **testPhysicalEventsAreNotAttention** — 808, 815, a system reshow and the z-order seed each move nothing and
  report `noInput`. This is the whole point of the vocabulary: physical ordering is not expressible as
  attention at all.
- **testSpaceAndDiscoveryInputsNameNothing** — the same for the Space, discovery and tab families.

### B. The two levels

- **testActivationWithNoFactAsksForARead** — activating an app nobody has answered for reports `needsRead`.
  Measured: a plain activation names no window from ANY source when the app's focused window did not change,
  and this is the one hole nothing else fills.
- **testRepeatedFactlessActivationDoesNotDuplicateTheRead** — while that bounded call is in flight, another
  activation for the same process shares it instead of spending another IPC or replacing its issue sequence.
- **testAnAppAnswerFrontsItsWindow** — the app's own answer fronts its window once that app is in front.
- **testAnAnswerFromABackgroundAppIsRecordedAndMovesNothing** — an answer from an app the user is not in is a
  fact about that app, not a bid for the front. It is recorded, not refused.
- **testTheRecordedFactIsWhatTheNextActivationLandsOn** — and it is not thrown away: activating that app later
  lands on the window it named, with no read needed.
- **testCachedFactUsesTheCurrentRepresentative** — the cached fact retains the wid the app named and resolves
  it through the current tab mapping on activation, rather than retaining a stale representative.
- **testAClickFrontsItsWindowWithoutWaitingForTheActivation** — the click names both levels at once, so it
  fronts a window of an app that has not activated yet. The only source that survives a wedged app.
- **testAFocusThatDidNotTakeLeavesTheFrontAlone** — #6055. AltTab's switch moves nothing by itself: when the
  focus did not take, the read of the target app afterwards is a fact about that app, and the front stays
  where the OS left it.
- **testAnActivationWeAreStillWaitingOnDoesNotFrontTheCachedWindow** — the activation AltTab's own switch
  provokes arrives before the app has answered. Its cached answer is the window being left, so it neither
  fronts it nor spends a read; the answer that follows is what moves the front.
- **testAnAnswerMapsThroughTheTabRepresentative** — an app answering with a background tab moves the tile that
  stands for it, while the wid the app actually named is reported alongside.
- **testAnAppThatCannotAnswerMovesNothing** — unknown is a value. The bounded read coming back empty is
  reported rather than dropped, and no guess is substituted from stacking.

### C. Process generations and ordering

- **testUnseenPidIsRegisteredBeforeItsEvent** — an app already running when AltTab started is activated
  normally (it asks for a read) rather than as a stale generation.
- **testRelaunchedPidDoesNotInheritTheDeadProcessesFact** — a relaunched pid starts with no fact, so its first
  activation asks for a read instead of landing on the dead process's window.
- **testTheBoundedReadLosesToAnAnswerThatOvertookIt** — the read's answer carries the sequence it was ISSUED
  at, not the one it arrived at. An app that spoke for itself in the meantime keeps the last word. This is the
  one place per-process monotonicity has teeth.
- **testAFailedReadDoesNotCauseAnotherReadAfterTheAppAnswers** — failure returns the issue sequence; once the
  app later supplies a fact, its next activation reuses that fact without another IPC.
- **testDestroyedCachedWindowMakesTheNextActivationReadAgain** — lifecycle invalidation clears a dead cached
  target, so the next activation reads rather than trying to resurrect an unknown wid.
- **testSemanticAnswerUsesTheProvidersPid** — the app observer's trusted pid is not re-inferred from a wid
  that may be untracked or recycled.

### D. Attribution

- **testEveryInputHasADistinctReasonCode** — every input maps to its own reason code, so nothing is ever
  attributed to "focus" in general.

## Seeding the front process

The model learns which app is in front from activations. An app that was already frontmost when AltTab
started produced none, so every answer it gave was about a process the model did not think was in front, and
Cmd+` inside it moved nothing. `syncFrontmost` reads the front app from the model of the world before
translating an answer, which is a correction rather than a claim about the user.
