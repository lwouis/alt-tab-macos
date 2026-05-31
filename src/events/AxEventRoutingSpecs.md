# AxEventRouting — Specs

## Summary

`AxEventRouting` is the pure decision layer for incoming AX events: **which bounded pool** an outgoing
AX query runs on, **which events are coalesced** (throttled), whether an event takes the **prompt
MRU-order fast path**, and the **de-dup key** per event. It holds no state and touches no queues,
threads, or timing — `AccessibilityEvents` and `AXCallScheduler` turn its decisions into real
scheduling. Extracted so the routing/throttling design is unit-testable (same pattern as
`SelectionResolver`).

## Behavior

- **Pool**: an unresponsive app's call is quarantined to `retry`; otherwise the bursty periodic inventory
  is isolated on `scan`; everything else is an event-driven `firstTry`. `AXCallScheduler` has no throttle —
  it is a pure executor, so this is purely about *which lane*, never *when*.
- **Coalescing**: only resize / move / title self-flood (a live drag fires 60–120/s) and are coalesced to
  ≤1 attribute read per window. Every other event is edge-triggered and runs promptly.
- **Fast path**: focus / main / activation carry MRU-order info that can't be re-queried, so they update
  order on `focusOrderQueue` (IPC-free) rather than via an attribute read.
- **De-dup key**: `AXCallScheduler` de-dups in-flight calls per key, so non-interchangeable work must not
  share a key. App events split `activate` vs `visibility`; window events split `focus` / `geometry` /
  `generic`. The bare `pid-<n>` scan key is owned by `manuallyUpdateWindows` and never collides.

## Test scenarios

Mirrors `AxEventRoutingTests.swift` 1:1.

### A. Pool routing (queue selection)
- **testPoolFirstTryForResponsiveEvent** — responsive, non-scan → `firstTry`.
- **testPoolScanIsolatesBulkInventory** — scan work → `scan` (isolated from event reads).
- **testPoolUnresponsiveQuarantinesToRetry** — unresponsive → `retry`, even for scan work (unresponsive wins).

### B. Throttle scoping (which events coalesce)
- **testOnlyResizeMoveTitleCoalesce** — resize / move / title self-flood → coalesced.
- **testEdgeEventsAreNeverCoalesced** — focus / main / activation / created / destroyed / min / demin / hidden / shown run promptly.

### C. Fast-path classification (MRU order)
- **testFocusMainActivationTakeFastPath** — focus / main / activation update order via the fast path.
- **testNonOrderEventsDoNotTakeFastPath** — resize / created / hidden / title do not.

### D. De-dup keys (the collision fixes)
- **testWindowDedupKeysByBucket** — focus/main → `wid-…-focus`; resize/move → `wid-…-geometry`; title/created → `wid-…-generic`.
- **testAppDedupKeysSeparateActivationFromVisibility** — activation → `pid-…-activate`; hidden/shown → `pid-…-visibility`.
- **testActivationAndVisibilityNeverShareAKey** — activation ≠ hidden, and neither equals the bare `pid-<n>` scan key.
- **testFocusAndGeometryNeverShareAKey** — focus and resize on the same wid get different keys (#5492/#5580).

### E. Use-case integration (deterministic routing of the discussed scenarios)
- **testUseCaseManualRefreshIsolatesOnScanPool** — the 60-app inventory routes entirely to `scan`.
- **testUseCaseRapidFocusSwitchIsFastAndUncoalesced** — focus/main take the fast path and are never coalesced.
- **testUseCaseResizeDragCoalesces** — a resize drag coalesces, on `firstTry`.
- **testUseCaseUnresponsiveAppQuarantines** — calls to a beach-balling app (incl. its scan) land on `retry`.
