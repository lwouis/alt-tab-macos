# SchedulingPolicy — Specs

## Summary

`SchedulingPolicy` holds the pure timing decisions behind the AX scheduling layer, extracted so they're
testable without real clocks or queues (same pattern as `SelectionResolver` / `AxQueryRouting`):

- **`ThrottleDecision`** — for one `throttleOrProceed` call: run on the leading edge, or (within the
  window) schedule a single trailing run and coalesce the rest. Used by `Throttler` and `ThrottlerWithKey`.
- **`RetryPolicy`** — backoff schedule (200ms → 1s → 2s → 5s, then 5s) and the 60s give-up, for retrying
  an AX call against an unresponsive app. Used by `AXCallScheduler`.
- **`SurfaceAcquisitionPolicy`** — may the inventory sweep spend another brute-force acquisition on a
  WindowServer surface it has repeatedly failed to find an AX element for?
- **`InactiveTabScanPolicy`** — may we brute-force an app's AX tree for the inactive tabs its AXTabGroup named
  but we hold no window for, and WHERE should that sweep start? That walk is the ONLY way to adopt an inactive tab (it appears in no CGS list) and
  it is expensive, so it is gated per app on the SITUATION: the untracked titles plus the app's window count,
  which is what says whether anything has changed since we last looked. Used by
  `Applications.discoverInactiveTabs`.

## Test scenarios

Mirrors `SchedulingPolicyTests.swift` 1:1.

### A. ThrottleDecision
- **testThrottleFirstCallRunsNow** — no prior fire → `runNow`.
- **testThrottleAfterWindowRunsNow** — elapsed ≥ delay → `runNow` (window reset).
- **testThrottleWithinWindowSchedulesTail** — within window, no tail pending → `scheduleTail(remaining)`.
- **testThrottleWithinWindowWithPendingTailCoalesces** — within window, tail already pending → `coalesce`.
- **testThrottleClockGoingBackwardsRunsNow** — now < last (monotonic-clock guard) → `runNow`.
- **testThrottleBurstCoalescesAfterOneTail** — a burst yields one leading run, one `scheduleTail`, then `coalesce` for the rest.

### B. RetryPolicy
- **testRetryBackoffSequence** — retry 0/1/2/3/4… → 200ms / 1s / 2s / 5s / 5s.
- **testRetryBackoffClampsAndFloors** — counts past the last step clamp to 5s; negative counts floor to the first step.
- **testRetryGivesUpAtThreshold** — elapsed ≥ 60s → give up.
- **testRetryDoesNotGiveUpEarly** — elapsed < 60s → keep retrying.

### C. InactiveTabScanPolicy

The situation used to be recorded BEFORE the scan ran and then refused forever, so one fruitless attempt — the
app's AX tree not ready yet, the classic at launch — permanently gave up on it, with no retry and no later
trigger. Measured live (2026-07-30): 82 tab reads named untracked tabs and the scan adopted
NOTHING, against 57 adoptions in a run whose first attempt happened to land. So the outcome is what gets
recorded, and a situation gets a small budget instead of exactly one shot.

- **testFruitlessScanIsRetriedOnTheSameSituation** — the fix: three fruitless attempts on one situation are all
  permitted, where the first used to close the door.
- **testFruitlessScansStopAtTheCap** — and bounded, because fruitless is ORDINARY, not an error: Finder destroys
  a backgrounded tab's window, so its AXTabGroup routinely names tabs with no window to find
  (`testFinderTabsAllUntracked`) and no number of walks resolves them. Past the cap the tree is left alone.
- **testANewSituationIsAlwaysEligible** — any change to the app's window set (a tab adopted, opened or closed)
  moves the titles or the count, and makes the app eligible again however exhausted the last situation was.
- **testTheSweepStartsNearTheAppsOwnElementsNotAtZero** — WHERE the sweep begins is what decided whether it
  found anything. It walks AXUIElementIDs one by one under a wall-clock budget, so it covers a WINDOW of the
  id space and never the space; starting at 0 aimed that window at wherever the app was hours ago. Measured
  live: three attempts covered ids `0..<30000` (~9.7k per 250ms) and adopted nothing, while Finder's window
  elements sat at ~31000 — stopping just short, every time. A tab's window element is minted when the tab is,
  so an app's windows cluster in a narrow band and a window we already track names it; anchoring a margin
  below found them in a single attempt (the live cases went green, the slowest from 34s to 16s).
- **testARetryResumesWhereTheLastSweepStopped** — the cursor from a fruitless attempt beats the anchor, so
  retries climb the id space instead of re-walking what already failed.
- **testASuccessfulScanSpendsNoBudget** — a scan that adopted something made progress and the situation it
  leaves is new anyway; only a fruitless attempt consumes budget, and a fresh situation restarts it.
- **testACandidateLeftForAnotherWindowIsNotSteppedOver** — a sweep stops as soon as it has as many title
  matches as there are untracked tabs, and the caller drops the ones parked on another window of the same app:
  they are that window's tabs. Those are a find for a DIFFERENT requester, so stepping the shared cursor past
  them made two tab groups of one app permanently uncrossable — measured on a cold launch with Finder holding
  two 3-tab groups, each requester's sweep kept finding only the other's tabs and six tabs came back as the
  two that were active (measured live). A deferred candidate rewinds the cursor onto itself; the attempt budget
  above still bounds the whole thing.

### D. SurfaceAcquisitionPolicy

Sibling of `InactiveTabScanPolicy`: the same bounded, situation-keyed budget over the OTHER brute-force.

The inventory sweep acquires AX elements for WindowServer surfaces it holds none for. Other-Space acquisition
uses a remote-token sweep capped by WALL CLOCK; eligible surfaces of one process now share that 250ms
traversal, but an unresolved process set still does not fail fast and must have a finite retry budget.

**Measured live before process batching, 2026-08-28, on a 4-window desktop.** Twelve such surfaces existed
(Dock, Spotlight, Control Center, WallpaperAgent, BetterDisplay, CopyQ, a Chrome surface, PAH_Extension);
none was a window, yet each started an identical per-wid traversal. Six at a time on the 6-wide scan pool,
that was ~550ms per show and 82,167 of its 82,221 AX round trips. Process batching removes that multiplier;
this policy still bounds repeated batches whose unresolved members remain unchanged.

**Only the periodic sweep is gated.** A surface that changes state reaches `Applications.discoverWindow` on
its own event, and that path uses the cheap `kAXWindows` route with no brute-force, so refusing the sweep
cannot make a window undiscoverable.

- **testAFreshSurfaceIsAlwaysAttempted** — a surface with no failure on record is swept, as before.
- **testAFailedSurfaceIsRetriedWithinTheBudget** — a failure is not a verdict: the situation keeps its three
  attempts, because an app still building its accessibility tree at launch fails transiently.
- **testAFailedSurfaceStopsAtTheCap** — past the cap the sweep leaves it out of subsequent process batches.
- **testANewWindowSetMakesTheSurfaceEligibleAgain** — the app gaining or losing a window is what plausibly
  makes a previously-unreachable element reachable, so it restarts the budget however exhausted it was.
- **testAttemptsResetOnANewSituation** — the counter is per situation, not cumulative, so a long-lived app
  that churns windows never accumulates its way into a permanent refusal.
