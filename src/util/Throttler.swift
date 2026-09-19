import Cocoa

class Throttler {
    private let delayInNanoseconds: UInt64
    /// Starts with no last run, so the FIRST call is a leading edge rather than one throttled against the
    /// instant this object happened to be built. Swift builds a static lazily, i.e. inside the first call
    /// itself, so `now` there meant the first call always paid the whole delay: the launch window inventory
    /// could not run in AltTab's first second however early it was asked for, and a summon at +0.4s drew an
    /// empty switcher and filled it 1.3s later.
    private var slot = ThrottleSlot<() -> Void>()

    init(delayInMs: Int) {
        self.delayInNanoseconds = UInt64(delayInMs) * 1_000_000
    }

    func throttleOrProceed(_ block: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        switch slot.offer(block, nowNs: DispatchTime.now().uptimeNanoseconds, delayNs: delayInNanoseconds) {
            case .runNow: block()
            case .coalesce: break
            case .scheduleTail(let remainingNs):
                DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(remainingNs))) { [self] in
                    slot.takeTail(nowNs: DispatchTime.now().uptimeNanoseconds)?()
                }
        }
    }
}

class ThrottlerWithKey {
    private let delayInNanoseconds: UInt64
    private let map = ConcurrentMap<String, ThrottleSlot<() -> Void>>()

    init(delayInMs: Int) {
        self.delayInNanoseconds = UInt64(delayInMs) * 1_000_000
    }

    /// Also cancels a pending tail: it finds no slot and runs nothing.
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
        let decision = map.withLock { map in
            map[key, default: ThrottleSlot()].offer(block, nowNs: DispatchTime.now().uptimeNanoseconds, delayNs: delayInNanoseconds)
        }
        switch decision {
            case .runNow: run(block, queue, priority)
            case .coalesce: break
            case .scheduleTail(let remaining): scheduleTail(key, remaining, queue, priority)
        }
    }

    private func scheduleTail(_ key: String, _ remaining: UInt64, _ queue: LabeledOperationQueue?, _ priority: Operation.QueuePriority) {
        let tailBlock = {
            let latest = self.map.withLock { $0[key]?.takeTail(nowNs: DispatchTime.now().uptimeNanoseconds) }
            latest?()
        }
        guard let queue else {
            let callerQueue = OperationQueue.current?.underlyingQueue ?? DispatchQueue.main
            return callerQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(remaining)), execute: tailBlock)
        }
        queue.strongUnderlyingQueue.asyncAfter(deadline: .now() + .nanoseconds(Int(remaining))) { [weak queue] in
            guard let queue else { return }
            self.run(tailBlock, queue, priority)
        }
    }

    private func run(_ block: @escaping () -> Void, _ queue: LabeledOperationQueue?, _ priority: Operation.QueuePriority) {
        guard let queue else { return block() }
        let op = BlockOperation(block: block)
        op.queuePriority = priority
        queue.addOperation(op)
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
