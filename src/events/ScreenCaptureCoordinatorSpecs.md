# ScreenCaptureCoordinator — Specs

## Summary

The coordinator limits all active ScreenCaptureKit requests in the process. It queues excess work and
protects the queue from a system request that never calls its completion handler.

## Behavior

- At most two requests can be active.
- A request gets a slot before it calls ScreenCaptureKit.
- Eligibility is checked again on the submission queue after a slot is available. Ineligible work releases its reserved slot without starting a watchdog or calling the OS.
- Window captures submit on main, where switcher visibility, preferences, lock state, and non-prompting preflight are checked without a queue hop before the OS call.
- The normal completion handler releases the slot.
- A completion handler can release its slot only one time.
- A ten-second watchdog opens a circuit and drops queued work when ScreenCaptureKit loses a completion.
- A timed-out request still counts as physically active, so no replacement request can exceed the limit.
- A late completion closes the circuit. A request submitted after that can start.
- If completion never arrives, the menu shows a passive restart action. Only the user's action restarts AltTab; permissions are not reset. A restart releases the old process and its outstanding requests.
- Thumbnail and focused-preview requests use the same process-wide coordinator.

## Test scenarios

- `testMaximumOfTwoCapturesCanRun`
- `testWatchdogOpensCircuitUntilLateCompletion`
- `testCompletionCanReleaseOnlyOneSlot`
- `testQueuedCaptureIsDroppedWhenEligibilityChanges`
- `testLostCompletionsKeepCircuitClosedToNewWork`
