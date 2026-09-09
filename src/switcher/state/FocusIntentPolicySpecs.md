# Focus intent — Specs

The rule that decides which of several in-flight focus operations may still touch the screen, and what a
superseded one owes when it already did. Pure: requests and step reports in, a verdict and an optional
repair out. `Window.focus()` owns the queue and the private APIs, and calls this.

## Why it exists

Focusing a window across apps takes two kinds of call, and only one of them fronts the process:

- `_SLPSSetFrontProcessWithOptions` sets the front process — the menu bar — *and* raises the target window
- `makeKeyWindow` and `kAXRaiseAction` only move a window in the global z-order

`Window.focus()` runs all of them in one operation on the shared 4-wide `accessibilityCommandsQueue`, and
returns without waiting. Two alt-tabs in quick succession are therefore two operations running concurrently:
they start in order and finish in any order. `raiseWindow` is a raw `AXUIElementPerformAction` against a
foreign app, bounded only by the process-wide 1s messaging timeout, and the stale-element retry behind it
(#5586) costs up to 1.25s more — so an operation can stay in flight for seconds against a re-switch the user
performs in ~200ms.

When the older operation's z-order call lands after the newer one's front-switch, the menu bar names the new
app while the old app's window sits on top. That split is only reachable because the two kinds of call can
interleave; nothing else in `focus()` moves them apart.

## The rule

- a request supersedes every earlier one, and only the newest may act — an operation checks before each step,
  so one blocked in the AX timeout stops at the next boundary instead of spending its retry budget
- a superseded operation that already moved the z-order owes a **repair**: the current intent is re-asserted
  so the newest switch, not the stale one, is what the user ends up looking at. The z-order call is a post to
  another process, which cannot be recalled, so bailing alone leaves the screen wrong
- an operation that bailed before touching anything owes nothing, so a bail never costs a redundant re-front
- a repair is refused once the current intent is older than `repairHorizon`, so a very late operation cannot
  yank a front the user has since chosen themselves
- one repair per intent, not one per stale operation: a repair issued after a stale operation's last z-order
  touch already covers it
- a repair runs under the intent it repairs and allocates no generation, so it cannot supersede that intent
  or provoke a further repair

Fronting is what `_SLPSSetFrontProcessWithOptions` does, so a superseded operation that got that far must
still run the cross-Space origin repair (#4507). That step is gated on having fronted, never on being
current — bailing out of it would leak the clobber it exists to undo.

## Test scenarios

- **testANewerRequestSupersedesTheOlderOne** — the fast alt-tab, in one line: two requests, and only the
  second may act.
- **testTheNewestRequestAlwaysProceeds** — after any number of requests only the last proceeds, so a backlog
  collapses rather than replaying.
- **testASupersededOpThatAlreadyReorderedAsksForARepair** — the case a bail alone misses: the older
  operation's raise already landed, so the newest intent has to be re-asserted.
- **testASupersededOpThatNeverReorderedAsksForNoRepair** — it stopped before touching the screen, so there is
  nothing to undo and AltTab does not re-front for free.
- **testTheCurrentOpAsksForNoRepair** — the ordinary single switch emits nothing.
- **testARepairIsRefusedOnceTheIntentIsStale** — past `repairHorizon` the user has moved on, and a repair
  would take the front away from them.
- **testTwoStaleOpsProduceOneRepair** — the first repair already re-asserted the intent both of them
  clobbered.
- **testARepairDoesNotCascade** — an operation reports its outcome once, so the re-assert cannot start
  another round.
- **testARepeatedFocusOfTheSameWindowStillSupersedes** — the generation is per request, not per window; the
  older operation bails even when both name the same target.
