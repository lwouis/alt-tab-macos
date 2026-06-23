# SchedulingPolicy — Specs

## Summary

`SchedulingPolicy` holds the pure timing decisions behind the AX scheduling layer, extracted so they're
testable without real clocks or queues (same pattern as `SelectionResolver` / `AxQueryRouting`):

- **`ThrottleDecision`** — for one `throttleOrProceed` call: run on the leading edge, or (within the
  window) schedule a single trailing run and coalesce the rest. Used by `Throttler` and `ThrottlerWithKey`.
- **`RetryPolicy`** — backoff schedule (200ms → 1s → 2s → 5s, then 5s) and the 60s give-up, for retrying
  an AX call against an unresponsive app. Used by `AXCallScheduler`.

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
