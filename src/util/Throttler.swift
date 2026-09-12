import Cocoa

class Throttler {
    private let delayInNanoseconds: UInt64
    /// nil until the first run, so the FIRST call is a leading edge rather than one throttled against the
    /// instant this object happened to be built. Swift builds a static lazily, i.e. inside the first call
    /// itself, so `now` there meant the first call always paid the whole delay: the launch window inventory
    /// could not run in AltTab's first second however early it was asked for, and a summon at +0.4s drew an
    /// empty switcher and filled it 1.3s later. `ThrottlerWithKey` has always started from no entry, and
    /// `ThrottleDecision` documents nil as a fresh leading edge; this makes the two agree.
    private var lastTimeInNanoseconds: UInt64?
    private var nextScheduled = false

    init(delayInMs: Int) {
        self.delayInNanoseconds = UInt64(delayInMs) * 1_000_000
    }

    func throttleOrProceed(_ block: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        let now = DispatchTime.now().uptimeNanoseconds
        switch ThrottleDecision.decide(lastFireNs: lastTimeInNanoseconds, nowNs: now, delayNs: delayInNanoseconds, tailScheduled: nextScheduled) {
            case .runNow:
                lastTimeInNanoseconds = now
                block()
            case .coalesce:
                break
            case .scheduleTail(let remainingNs):
                nextScheduled = true
                // `remaining`, not a whole fresh window. Scheduling `delay` from HERE made the tail land up
                // to twice as late as the throttle promises: a call arriving 190ms into a 200ms window ran
                // at ~400ms instead of ~200ms. `ThrottlerWithKey` has always used `remaining`; this makes
                // the two agree. The 10ms margin keeps the re-entrant `decide` from landing a hair early
                // and scheduling a second tail for the remainder.
                DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(remainingNs) + 10_000_000)) { [self] in
                    nextScheduled = false
                    throttleOrProceed(block)
                }
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

    func removeEntries(withPrefix prefix: String) {
        map.withLock { map in
            for key in map.keys where key.hasPrefix(prefix) {
                map[key] = nil
            }
        }
    }

    func throttleOrProceed(key: String, queue: LabeledOperationQueue? = nil, priority: Operation.QueuePriority = .normal, _ block: @escaping () -> Void) {
        let shouldThrottle = map.withLock { map -> Bool in
            let now = DispatchTime.now().uptimeNanoseconds
            switch ThrottleDecision.decide(lastFireNs: map[key]?.time, nowNs: now, delayNs: delayInNanoseconds, tailScheduled: map[key]?.tailScheduled ?? false) {
                case .runNow:
                    map[key] = ThrottleState(time: now, tailScheduled: false)
                    return false
                case .coalesce:
                    return true
                case .scheduleTail(let remaining):
                    map[key] = ThrottleState(time: map[key]!.time, tailScheduled: true)
                    let tailBlock = {
                        let shouldExecute = self.map.withLock { map -> Bool in
                            guard let state = map[key], state.tailScheduled else { return false }
                            map[key] = ThrottleState(time: DispatchTime.now().uptimeNanoseconds, tailScheduled: false)
                            return true
                        }
                        if shouldExecute { block() }
                    }
                    if let queue {
                        queue.strongUnderlyingQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(remaining))) { [weak queue] in
                            guard let queue else { return }
                            let op = BlockOperation(block: tailBlock)
                            op.queuePriority = priority
                            queue.addOperation(op)
                        }
                    } else {
                        let callerQueue = OperationQueue.current?.underlyingQueue ?? DispatchQueue.main
                        callerQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(remaining)), execute: tailBlock)
                    }
                    return true
            }
        }
        if !shouldThrottle {
            if let queue {
                let op = BlockOperation(block: block)
                op.queuePriority = priority
                queue.addOperation(op)
            } else {
                block()
            }
        }
    }
}

final class ConcurrentMap<K: Hashable, V>: @unchecked Sendable {
    private var map = [K: V]()
    // os_unfair_lock is ~10x lighter than NSLock on the uncontended path (single atomic CAS, no ObjC dispatch).
    // The hot path holds the lock for a dictionary lookup or assignment only; contention is rare.
    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    @discardableResult
    @inline(__always)
    func withLock<T>(_ block: (inout [K: V]) -> T) -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return block(&map)
    }
}

final class ConcurrentArray<T>: @unchecked Sendable {
    private var array: [T]
    private let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()

    init(_ initial: [T] = []) { self.array = initial }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    @discardableResult
    @inline(__always)
    func withLock<R>(_ block: (inout [T]) -> R) -> R {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return block(&array)
    }
}
