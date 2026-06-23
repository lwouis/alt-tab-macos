import Foundation

/// Pure scheduling decisions extracted from `Throttler` / `ThrottlerWithKey` and `AXCallScheduler`, so the
/// timing logic is unit-testable without real clocks or queues (same pattern as `SelectionResolver` /
/// `AxQueryRouting`). The owners keep the actual clock reads + queue dispatch; they just branch on these.

/// The coalescing decision for one `throttleOrProceed` call: leading-edge runs immediately; calls within
/// the window collapse to a single trailing run.
enum ThrottleDecision: Equatable {
    case runNow                            // leading edge (or window already elapsed): run now, (re)start the window
    case scheduleTail(remainingNs: UInt64) // within window, no trailing run pending yet: schedule one after `remaining`
    case coalesce                          // within window, a trailing run is already pending: drop (latest runs on the tail)

    static func decide(lastFireNs: UInt64?, nowNs: UInt64, delayNs: UInt64, tailScheduled: Bool) -> ThrottleDecision {
        // first call ever, or a (practically impossible) backwards clock → treat as a fresh leading edge
        guard let last = lastFireNs, nowNs >= last else { return .runNow }
        let elapsed = nowNs - last
        if elapsed >= delayNs { return .runNow }
        return tailScheduled ? .coalesce : .scheduleTail(remainingNs: delayNs - elapsed)
    }
}

/// Backoff + give-up policy for retrying an AX call against an unresponsive app.
enum RetryPolicy {
    static let backoffStepsNs: [UInt64] = [200_000_000, 1_000_000_000, 2_000_000_000, 5_000_000_000] // 200ms, 1s, 2s, 5s…
    static let giveUpAfterNs: UInt64 = 60_000_000_000 // 60s

    /// retry N uses step N, clamped to the last (so it stays at 5s); negative counts floor to the first step.
    static func backoffDelayNs(retryCount: Int) -> UInt64 {
        backoffStepsNs[min(max(0, retryCount), backoffStepsNs.count - 1)]
    }

    static func shouldGiveUp(elapsedSinceStartNs: UInt64) -> Bool {
        elapsedSinceStartNs >= giveUpAfterNs
    }
}
