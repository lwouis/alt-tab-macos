import Foundation

struct CaptureDiscoveryKey: Hashable {
    let wid: UInt32
    let fullRes: Bool
}

/// Caller holds the discovery lock. A snapshot covers the keys present when its request started.
/// Missing late arrivals stay queued for one newer snapshot; missing covered keys are drained, so absent
/// windows cannot keep discovery running without new requests. Capacity includes both generations.
struct CaptureDiscovery<Value> {
    private struct Entry {
        let value: Value
        let prioritized: Bool
    }

    private let capacity: Int
    private var pending = [CaptureDiscoveryKey: Entry]()
    private var covered: Set<CaptureDiscoveryKey>?
    private(set) var generation: UInt64 = 0

    init(capacity: Int) {
        self.capacity = capacity
    }

    /// Returns how many requests were dropped, including a displaced lower-priority request.
    mutating func insert(_ key: CaptureDiscoveryKey, _ value: Value, prioritized: Bool,
                         merge: (Value, Value) -> Value) -> Int {
        if let previous = pending[key] {
            pending[key] = Entry(value: merge(previous.value, value), prioritized: previous.prioritized || prioritized)
            return 0
        }
        var dropped = 0
        if pending.count >= capacity {
            guard prioritized, let victim = pending.first(where: { !$0.value.prioritized })?.key else { return 1 }
            pending[victim] = nil
            dropped = 1
        }
        pending[key] = Entry(value: value, prioritized: prioritized)
        return dropped
    }

    mutating func begin() -> UInt64? {
        guard covered == nil, !pending.isEmpty else { return nil }
        generation &+= 1
        covered = Set(pending.keys)
        return generation
    }

    /// Drains ready requests and covered misses. A timeout finishes with no available windows. A stale
    /// completion returns nil and must not publish its snapshot or finish a newer request.
    mutating func finish(generation: UInt64, contains: (CaptureDiscoveryKey) -> Bool) -> [CaptureDiscoveryKey: Value]? {
        guard generation == self.generation, let covered else { return nil }
        var drained = [CaptureDiscoveryKey: Value]()
        for (key, entry) in pending where covered.contains(key) || contains(key) {
            drained[key] = entry.value
        }
        for key in drained.keys { pending[key] = nil }
        self.covered = nil
        return drained
    }
}
