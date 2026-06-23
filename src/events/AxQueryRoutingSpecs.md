# AxQueryRouting — Specs

## Summary

`AxQueryRouting` is the pure decision for **which bounded pool** an outgoing AX query runs on. It holds no
state and touches no queues, threads, or timing — `AXCallScheduler` turns the decision into real scheduling.
Extracted so the routing is unit-testable (same pattern as `SelectionResolver`).

The event-classification helpers that used to live here (coalescing, the MRU-order fast path, the de-dup
keys) were removed when the AX event pipeline was deleted: WindowServer now owns window-state routing
(see `src/windowserver/`).

## Behavior

- **Pool**: an unresponsive app's call is quarantined to `retry`; otherwise the bursty periodic inventory
  is isolated on `scan`; everything else is an event-driven `firstTry`. `AXCallScheduler` has no throttle —
  it is a pure executor, so this is purely about *which lane*, never *when*.

## Test scenarios

Mirrors `AxQueryRoutingTests.swift` 1:1.

### Pool routing (queue selection)
- **testPoolFirstTryForResponsiveEvent** — responsive, non-scan → `firstTry`.
- **testPoolScanIsolatesBulkInventory** — scan work → `scan` (isolated from event reads).
- **testPoolUnresponsiveQuarantinesToRetry** — unresponsive → `retry`, even for scan work (unresponsive wins).

### Use-case integration (deterministic routing of the discussed scenarios)
- **testUseCaseManualRefreshIsolatesOnScanPool** — the 60-app inventory routes entirely to `scan`.
- **testUseCaseUnresponsiveAppQuarantines** — calls to a beach-balling app (incl. its scan) land on `retry`.
