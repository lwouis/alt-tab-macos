# ScreenCaptureCoordinator — Specs

## Summary

The coordinator limits all active ScreenCaptureKit requests in the process. It queues excess work and
protects the queue from a system request that never calls its completion handler.

## Behavior

- At most two requests can be active.
- A request gets a slot before it calls ScreenCaptureKit.
- Eligibility is checked again on the submission queue after a slot is available. Ineligible work releases its reserved slot without calling a capture API.
- The shared coordinator submits on a serial worker queue. Permission preflight and capture submission must not block the main UI thread. Slot reservation and enqueue share a lock, so concurrent completions cannot reorder queued work. Asynchronous OS requests can still overlap, up to the two-request limit.
- Window captures read switcher visibility, preferences, and lock state on main before and after the non-prompting preflight. A closed switcher drops pending work when background capture is disabled.
- A ten-second watchdog starts before preflight. A check that returns after its timeout releases the slot without starting a late capture.
- Submission is claimed atomically against preflight expiry. An accepted submission has its own ten-second completion watchdog; its old preflight deadline no longer applies.
- The normal completion handler releases the slot.
- A completion handler can release its slot only one time.
- A ten-second watchdog opens a circuit and drops queued work when ScreenCaptureKit loses a completion.
- A timed-out request still counts as physically active, so no replacement request can exceed the limit.
- A late completion closes the circuit. A request submitted after that can start.
- If completion never arrives, the menu shows a passive restart action. Only the user's action restarts AltTab; permissions are not reset. A restart releases the old process and its outstanding requests.
- Thumbnail and focused-preview requests use the same process-wide coordinator.
- A queued focused preview starts before queued thumbnails when a slot becomes available. It does not cancel a request already submitted to the OS.

## Test scenarios

- `testMaximumOfTwoCapturesCanRun`
- `testWatchdogOpensCircuitUntilLateCompletion`
- `testCompletionCanReleaseOnlyOneSlot`
- `testQueuedCaptureIsDroppedWhenEligibilityChanges`
- `testLostCompletionsKeepCircuitClosedToNewWork`
- `testFocusedPreviewStartsBeforeQueuedThumbnails`
- `testSharedCoordinatorSubmitsOutsideMainQueue`
- `testWatchdogCoversPreflightWithoutStartingLateCapture`
- `testFocusedPreviewSubmissionIsNotOvertaken`
- `testPreflightDeadlineCannotExpireSubmittedCapture`
