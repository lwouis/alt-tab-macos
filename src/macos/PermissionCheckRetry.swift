import Foundation

/// A timeout says nothing about the grant. Retry that read at most three times, and let a newer
/// permission event or user choice invalidate the old retry. Owned by the serial permissions queue.
struct PermissionCheckRetry {
    private(set) var generation = UInt64(0)
    private var attempt = 0

    mutating func begin() {
        generation += 1
        attempt = 0
    }

    mutating func nextDelay(unknown: Bool) -> TimeInterval? {
        guard unknown else { begin(); return nil }
        guard attempt < 3 else { return nil }
        let delay = TimeInterval(1 << attempt)
        attempt += 1
        return delay
    }
}
