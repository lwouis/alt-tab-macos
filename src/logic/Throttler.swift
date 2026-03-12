import Cocoa

class Throttler {
    private let delayInNanoseconds: UInt64
    private var lastTimeInNanoseconds = DispatchTime.now().uptimeNanoseconds
    private var nextScheduled = false

    init(delayInMs: Int) {
        self.delayInNanoseconds = UInt64(delayInMs) * 1_000_000
    }

    func throttleOrProceed(_ block: @escaping () -> Void) {
        let now = DispatchTime.now().uptimeNanoseconds
        let (elapsed, overflow) = now.subtractingReportingOverflow(lastTimeInNanoseconds)
        if !overflow, elapsed >= delayInNanoseconds {
            lastTimeInNanoseconds = now
            block()
            return
        }
        guard !nextScheduled else { return }
        nextScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(delayInNanoseconds) + 10_000_000)) { [self] in
            nextScheduled = false
            throttleOrProceed(block)
        }
    }
}

class ThrottlerWithKey {
    private let delayInNanoseconds: UInt64
    private let map = ConcurrentMap<String, ThrottleState>()

    private struct ThrottleState {
        let time: UInt64
        var tailScheduled: Bool
    }

    init(delayInMs: Int) {
        self.delayInNanoseconds = UInt64(delayInMs) * 1_000_000
    }

    func removeEntry(withKey key: String) {
        map.withLock { $0[key] = nil }
    }

    func removeEntries(withSuffix suffix: String) {
        map.withLock { map in
            for key in map.keys where key.hasSuffix(suffix) {
                map[key] = nil
            }
        }
    }

    func throttleOrProceed(key: String, queue: LabeledOperationQueue? = nil, _ block: @escaping () -> Void) {
        let shouldThrottle = map.withLock { map in
            let now = DispatchTime.now().uptimeNanoseconds
            if let state = map[key] {
                let elapsed = now >= state.time ? (now - state.time) : delayInNanoseconds
                if elapsed < delayInNanoseconds {
                    if !state.tailScheduled {
                        map[key] = ThrottleState(time: state.time, tailScheduled: true)
                        let remaining = delayInNanoseconds - elapsed
                        let tailBlock = {
                            let shouldExecute = self.map.withLock { map -> Bool in
                                guard let state = map[key], state.tailScheduled else { return false }
                                map[key] = ThrottleState(time: DispatchTime.now().uptimeNanoseconds, tailScheduled: false)
                                return true
                            }
                            if shouldExecute { block() }
                        }
                        if let queue {
                            queue.addOperationAfter(deadline: .now() + .nanoseconds(Int(remaining)), block: tailBlock)
                        } else {
                            let callerQueue = OperationQueue.current?.underlyingQueue ?? DispatchQueue.main
                            callerQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(remaining)), execute: tailBlock)
                        }
                    }
                    return true
                }
            }
            map[key] = ThrottleState(time: now, tailScheduled: false)
            return false
        }
        if !shouldThrottle {
            if let queue {
                queue.addOperation(block)
            } else {
                block()
            }
        }
    }
}

final class ConcurrentMap<K: Hashable, V> {
    private var map = [K: V]()
    private let lock = NSLock()

    @discardableResult
    func withLock<T>(_ block: (inout [K: V]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block(&map)
    }
}
