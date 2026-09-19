# Attention model — Specs

The kernel behind `AttentionOrderSpecs.md`, which is the one-page statement of what may move the window
order. Attention as two levels: which app has it, and which of that app's windows has it. The two come from
different places and are never compared with each other.

    frontProcess             <- NSWorkspace, and the click's pid
    focusedWindow[process]   <- that app's own answer, the click's wid, one bounded read
    the visible front        == focusedWindow[frontProcess]

The measurement base is twelve focus scenarios recorded with all four signal sources on one clock.
Including follow-up N, Accessibility names the window in 10 of 12 scenarios
and is the earliest window-naming source in 8, so it is the primary rather than the fallback. The WindowServer
is never the best source in any scenario where anything else speaks and has no exclusive scenario at all, so
**no physical input can name attention** — 808 and 815 are not part of attention. A lifecycle invalidation
may erase a cached answer when its window ceases to exist; it never names or moves the front.

## Levels

- `frontProcess` is set by an app activation, and by the one namer that carries an app with it: the click.
  An app's own answer never changes which app is in front.
- `focusedWindow` is per process. Two apps holding different facts is not a conflict, it is the normal state.
- the visible front is the lookup, computed rather than stored
- an unknown front window is nil, and nil means "nobody has said" rather than "nothing is focused". The
  decision stream is the API; a consumer moves the order on `.front` and does nothing otherwise.

## Rules

- **per-process monotonicity, and nothing else is compared** — a lower sequence never overwrites a higher one
  for the same process. Across processes nothing is compared. Sequences are allocated on arrival, so this
  only bites the answer that carries an older sequence than its arrival: the bounded read, issued at the
  activation and landing after whatever the app said meanwhile.
- **every namer writes a fact, never a command** — a late answer from an app the user has already left
  updates that app's entry and moves nothing.
- **unknown is a value** — a read that came back empty does not move the front, and does not erase what the
  app said before it. No guess is substituted from stacking order.
- **one bounded read, one trigger** — activating a process with no fact at all emits `readFocusedWindow`, and
  that is the only thing that emits it. A plain activation names no window from any source when the app's
  focused window did not change; that is the one hole nothing else fills.
- an activation for a process with a cached app answer needs no read either
- **an answer already on its way beats the one already here** — the activation provoked by a switch AltTab
  asked for takes the front for that app and names no window: the app's cached answer is about the window the
  user is LEAVING, and fronting it walks that window to the top of the order. No read either, since the one
  that will answer this is already out. The answer then moves the front even when it names the cached window,
  because the activation did not move it
- **the app outranks the click** — not as a rule of its own, but because the app's answer arrives later and
  arrival is the sequence. The click is a prediction; the app's answer is the outcome.
- a settle taking the LAST answer per process is correct with no extra rule, and lives in the impure caller
  (`AttentionEngine.axSemanticFocus`). A raise burst produced four true answers inside 0.6 ms and
  ended on the window it started on; a deferred burst emits in generation order with the click's outcome
  last.

## Eligibility and identity

- a target enters as the window that stands for it in the switcher; a missing or cross-process representative
  is refused rather than guessed
- an event for a process generation that is not the live one is refused
- a relaunched pid forgets the previous generation's fact and its claim on the front
- a process exit forgets its fact and clears the front if it held it
- a window invalidation forgets any fact whose observed or representative window was that wid, so a later
  activation reads again instead of resurrecting a dead target

## Decisions

- `front` — the visible front moved to this window
- `recorded` — a fact landed and nothing visible moved: the process is not in front, or it named the window
  that already held the front
- `readFocusedWindow` — activation with no fact; fire one `kAXFocusedWindow` read, off-main, 250 ms timeout
- `ignored` — stale generation, stale sequence, or an ineligible target

## Test scenarios

- `testAnswerFromABackgroundAppRecordsAFactAndMovesNothing` — the two levels really are separate.
- `testActivationWithNoFactAsksForOneBoundedRead` — the one hole, and the one trigger.
- `testActivationWithAFactMovesTheFrontWithoutReading` — a known app costs no read.
- `testInvalidatedWindowMakesTheNextActivationReadAgain` — a dead cached window is not resurrected.
- `testClickCarriesBothLevels` — the click names the app and the window at once.
- `testAnAppAnswerNeverChangesWhichAppIsInFront` — a fact is never a command.
- `testTheAppCorrectsTheClickBecauseItArrivesLater` — the outcome beats the prediction, by arrival.
- `testTheBoundedReadCannotOverwriteAFresherAnswerFromItsOwnApp` — where per-process monotonicity bites.
- `testAcrossProcessesNothingIsCompared` — and where it deliberately does not.
- `testAnUnknownReadNeitherMovesNorErasesTheFront` — unknown is a value.
- `testTheVisibleFrontIsNilWhileTheFrontAppHasNotAnswered` — nil means nobody has said.
- `testTheRepresentativeIsWhatLandsInTheFact` — the switcher's stand-in window is the target.
- `testAnIneligibleTargetIsRefused` — a missing or cross-process representative is not guessed at.
- `testAStaleGenerationIsRefused` — a dead process's callback is not current.
- `testARelaunchedPidForgetsThePreviousGenerationsFact` — a reused pid inherits nothing.
- `testProcessExitForgetsItsFactAndReleasesTheFront` — an exit releases rather than hands over.
- `testARaiseBurstEndsWhereItStarted` — #5974's shape needs no guess made in advance and taken back later.
- `testNamingTheWindowThatAlreadyHoldsTheFrontMovesNothing` — a repeat is a fact, not a move.
- `testAStaleAnswerFlushedByAnUnwedgeLosesToTheClicksOutcome` — the measured race resolves on arrival order.
- `testAnActivationAwaitingAnAnswerNeitherFrontsNorReads` — the app's cached answer predates the switch that
  provoked this activation, and the read that will settle it is already out.
- `testTheAwaitedAnswerMovesTheFrontEvenNamingTheCachedWindow` — otherwise a switch back to the window an app
  was already on leaves the order with the app the user LEFT on top.
