import Foundation

final class ScreenCaptureCoordinator {
    enum Priority {
        case normal
        case focusedPreview
    }

    typealias Completion = () -> Void
    typealias Operation = (@escaping Completion) -> Void
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void

    static let shared = ScreenCaptureCoordinator(submissionQueue: DispatchQueue(
        label: "com.lwouis.alt-tab-macos.capture-submission", qos: .userInitiated, attributes: .concurrent
    ))

    private struct PendingOperation {
        let operation: Operation
        let shouldStart: () -> Bool
        let priority: Priority
    }

    private struct ActiveOperation {
        let id: UUID
        let operation: Operation
        let shouldStart: () -> Bool
    }

    private let maximumInFlight: Int
    private let watchdogSeconds: TimeInterval
    private let schedule: Scheduler
    private let submissionQueue: DispatchQueue?
    private let lock = NSLock()
    private var activeIds = Set<UUID>()
    private var timedOutIds = Set<UUID>()
    private var pending = [PendingOperation]()
    private var circuitOpen = false

    init(maximumInFlight: Int = 2, watchdogSeconds: TimeInterval = 10,
         submissionQueue: DispatchQueue? = nil,
         schedule: @escaping Scheduler = { delay, action in
             DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay, execute: action)
         }) {
        precondition(maximumInFlight > 0)
        self.maximumInFlight = maximumInFlight
        self.watchdogSeconds = watchdogSeconds
        self.schedule = schedule
        self.submissionQueue = submissionQueue
    }

    var inFlightCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeIds.count + timedOutIds.count
    }

    var isCircuitOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return circuitOpen
    }

    func submit(priority: Priority = .normal,
                if shouldStart: @escaping () -> Bool = { true },
                _ operation: @escaping Operation) {
        lock.lock()
        guard !circuitOpen else {
            lock.unlock()
            return
        }
        pending.append(PendingOperation(operation: operation,
                                        shouldStart: shouldStart, priority: priority))
        let next = reserveNextLocked()
        lock.unlock()
        if let next {
            start(next)
        }
    }

    private func reserveNextLocked() -> ActiveOperation? {
        guard !circuitOpen, activeIds.count + timedOutIds.count < maximumInFlight,
              !pending.isEmpty else { return nil }
        let index = pending.firstIndex { $0.priority == .focusedPreview } ?? pending.startIndex
        let pendingOperation = pending.remove(at: index)
        let id = UUID()
        activeIds.insert(id)
        return ActiveOperation(id: id, operation: pendingOperation.operation,
                               shouldStart: pendingOperation.shouldStart)
    }

    private func start(_ active: ActiveOperation) {
        let submit = { [self] in
            guard !isCircuitOpen else { completed(active.id); return }
            schedule(watchdogSeconds) { [weak self] in self?.watchdogFired(active.id) }
            guard active.shouldStart(), !isCircuitOpen else { completed(active.id); return }
            active.operation { [weak self] in self?.completed(active.id) }
        }
        if let queue = submissionQueue {
            queue.async(execute: submit)
        } else {
            submit()
        }
    }

    private func completed(_ id: UUID) {
        lock.lock()
        if timedOutIds.remove(id) != nil {
            circuitOpen = !timedOutIds.isEmpty
            lock.unlock()
            return
        }
        guard activeIds.remove(id) != nil else { lock.unlock(); return }
        let next = reserveNextLocked()
        lock.unlock()
        if let next {
            start(next)
        }
    }

    private func watchdogFired(_ id: UUID) {
        lock.lock()
        guard activeIds.remove(id) != nil else { lock.unlock(); return }
        timedOutIds.insert(id)
        circuitOpen = true
        pending.removeAll()
        lock.unlock()
    }
}
