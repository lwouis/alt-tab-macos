import Cocoa

/// Pure pool-selection for outgoing AX queries: which bounded queue (`AXCallScheduler`) a call runs on,
/// given whether the target app is unresponsive and whether the call is bulk-scan inventory work. Holds no
/// state and touches no queues, threads, or timing, so the lane decision stays unit-testable (same pattern
/// as `SelectionResolver`). The event-classification helpers that used to live here (coalescing, the MRU
/// fast path, de-dup keys) were removed with the AX event pipeline — WindowServer now owns window-state
/// routing (see `src/windowserver/`).
enum AxQueryRouting {
    /// the bounded pool an outgoing AX query runs on (see `AXCallScheduler`).
    enum Pool: Equatable { case firstTry, scan, retry }

    /// A timed-out (unresponsive) app is quarantined to `retry` regardless of caller; otherwise the bursty
    /// periodic inventory is isolated on `scan`, and everything else is an event-driven `firstTry`.
    static func pool(unresponsive: Bool, scan: Bool) -> Pool {
        if unresponsive { return .retry }
        return scan ? .scan : .firstTry
    }
}
