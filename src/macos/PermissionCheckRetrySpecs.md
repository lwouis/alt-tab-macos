# Permission check recovery

Permission changes trigger one read. A capture check that exceeds six seconds is unknown,
not a denial: retain the last known status and retry after 1, 2 and 4 seconds. Stop after
three retries, or immediately after a known grant, denial or skip. A new notification or
user choice replaces the pending retry and starts a new budget. There is no idle polling.

## Test scenarios

- **testTimeoutRetriesAreBounded** — timed-out reads retry after 1, 2 and 4 seconds, then stop.
- **testAnAnswerCancelsThePendingRetry** — a known answer ends the budget and invalidates the retry
  already scheduled.
- **testANewerPermissionEventReplacesTheRetryBudget** — a new notification or user choice starts a fresh
  budget, even after the old one ran out.
- **testAKnownDenialDoesNotPoll** — a denial is an answer: nothing is scheduled.
