import Foundation

/// Coalesces repaint requests onto a trailing edge, and backs off only as far as the last paint cost.
/// `RepaintCoalescingPolicy` holds the decisions and the evidence for them.
///
/// Ordinary requests never run the caller's block synchronously, so a burst delivered across several
/// runloop turns still merges into one paint. The block is re-entrant-safe: a paint that itself requests
/// another one schedules it, and the fire re-checks the floor rather than trusting the deadline it was
/// given.
class RepaintCoalescer {
    private var scheduled = false
    private var generation: UInt64 = 0
    private let now: () -> UInt64
    private let enqueue: (UInt64, @escaping () -> Void) -> Void
    /// The clock value before which the next paint may not start, written by the previous paint.
    private var notBeforeNs: UInt64 = 0

    init(now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
         enqueue: @escaping (UInt64, @escaping () -> Void) -> Void = { delay, work in
             DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(delay)), execute: work)
         }) {
        self.now = now
        self.enqueue = enqueue
    }

    func request(_ paint: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !scheduled else { return }
        schedule(now(), paint)
    }

    /// Attention changes the default selection as well as the pixels. It must settle before a queued
    /// modifier release can commit that selection; invalidate the redundant trailing repaint.
    func requestImmediately(_ paint: () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        generation &+= 1
        scheduled = false
        paintAndMeasure(paint)
    }

    #if DEBUG
    func deferRepaints(milliseconds: Int) {
        notBeforeNs = now() + UInt64(max(0, milliseconds)) * 1_000_000
    }
    #endif

    private func schedule(_ nowNs: UInt64, _ paint: @escaping () -> Void) {
        let delayNs = RepaintCoalescingPolicy.delayNs(nowNs: nowNs, notBeforeNs: notBeforeNs)
        scheduled = true
        generation &+= 1
        let ticket = generation
        enqueue(delayNs) { [self] in
            guard ticket == generation else { return }
            let firedAt = now()
            // The floor may have moved since this was scheduled (a paint requested during a paint), and the
            // queue may have run us early. Re-aim rather than paying the cost inside someone else's quiet.
            guard firedAt >= notBeforeNs else { return schedule(firedAt, paint) }
            scheduled = false
            paintAndMeasure(paint)
        }
    }

    private func paintAndMeasure(_ paint: () -> Void) {
        let startedAt = now()
        paint()
        let endedAt = now()
        notBeforeNs = endedAt &+ RepaintCoalescingPolicy.quietAfterNs(paintCostNs: endedAt &- startedAt)
    }
}

/// Main-thread batching with one outstanding operation. Requests during a read form the next batch,
/// but do not invalidate its answer: apply it before calling `finish`, so continuous input makes progress.
/// Semantic changes can explicitly invalidate individual keys without discarding the rest of a batch.
final class BatchCoalescer<Key: Hashable> {
    private var pending = Set<Key>()
    private var current = Set<Key>()
    private var scheduledOrRunning = false
    private let enqueue: (@escaping () -> Void) -> Void
    private let read: (Set<Key>, @escaping () -> Void) -> Void

    init(enqueue: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
         read: @escaping (Set<Key>, @escaping () -> Void) -> Void) {
        self.enqueue = enqueue
        self.read = read
    }

    func request(_ keys: Set<Key>) {
        dispatchPrecondition(condition: .onQueue(.main))
        pending.formUnion(keys)
        scheduleIfNeeded()
    }

    func invalidate(_ keys: Set<Key>) {
        dispatchPrecondition(condition: .onQueue(.main))
        current.subtract(keys)
    }

    /// Read before `finish`: a key is eligible only until a newer semantic event invalidates it.
    func accepts(_ key: Key) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return current.contains(key)
    }

    private func scheduleIfNeeded() {
        guard !scheduledOrRunning, !pending.isEmpty else { return }
        scheduledOrRunning = true
        enqueue { [self] in
            let batch = pending
            pending.removeAll(keepingCapacity: true)
            current = batch
            read(batch) { [self] in
                dispatchPrecondition(condition: .onQueue(.main))
                current.removeAll(keepingCapacity: true)
                scheduledOrRunning = false
                scheduleIfNeeded()
            }
        }
    }
}
