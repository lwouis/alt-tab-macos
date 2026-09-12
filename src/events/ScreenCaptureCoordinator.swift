import Foundation

final class ScreenCaptureCoordinator {
    enum Priority {
        case normal
        case focusedPreview
    }

    private enum Stage {
        case checkingPermission
        case submitted
    }

    typealias Completion = () -> Void
    typealias Operation = (@escaping Completion) -> Void
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void

    static let shared = ScreenCaptureCoordinator(submissionQueue: DispatchQueue(
        label: "com.lwouis.alt-tab-macos.capture-submission", qos: .userInitiated
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
    private var activeStages = [UUID: Stage]()
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
        return activeStages.count + timedOutIds.count
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
        let next = enqueueNextLocked()
        lock.unlock()
        if let next {
            start(next)
        }
    }

    private func enqueueNextLocked() -> ActiveOperation? {
        guard let next = reserveNextLocked() else { return nil }
        guard let submissionQueue else { return next }
        // Enqueue in reservation order, even when two OS callbacks release slots concurrently.
        submissionQueue.async { self.start(next) }
        return nil
    }

    private func reserveNextLocked() -> ActiveOperation? {
        guard !circuitOpen, activeStages.count + timedOutIds.count < maximumInFlight,
              !pending.isEmpty else { return nil }
        let index = pending.firstIndex { $0.priority == .focusedPreview } ?? pending.startIndex
        let pendingOperation = pending.remove(at: index)
        let id = UUID()
        activeStages[id] = .checkingPermission
        return ActiveOperation(id: id, operation: pendingOperation.operation,
                               shouldStart: pendingOperation.shouldStart)
    }

    private func start(_ active: ActiveOperation) {
        guard !isCircuitOpen else { completed(active.id); return }
        schedule(watchdogSeconds) { [weak self] in
            self?.watchdogFired(active.id, stage: .checkingPermission)
        }
        guard active.shouldStart(), claimSubmission(active.id) else { completed(active.id); return }
        schedule(watchdogSeconds) { [weak self] in
            self?.watchdogFired(active.id, stage: .submitted)
        }
        active.operation { [weak self] in self?.completed(active.id) }
    }

    private func claimSubmission(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !circuitOpen, activeStages[id] == .checkingPermission else { return false }
        // This transition and preflight expiry share the same lock. Exactly one wins.
        activeStages[id] = .submitted
        return true
    }

    private func completed(_ id: UUID) {
        lock.lock()
        if timedOutIds.remove(id) != nil {
            circuitOpen = !timedOutIds.isEmpty
            lock.unlock()
            return
        }
        guard activeStages.removeValue(forKey: id) != nil else { lock.unlock(); return }
        let next = enqueueNextLocked()
        lock.unlock()
        if let next {
            start(next)
        }
    }

    private func watchdogFired(_ id: UUID, stage: Stage) {
        lock.lock()
        guard activeStages[id] == stage else { lock.unlock(); return }
        activeStages.removeValue(forKey: id)
        timedOutIds.insert(id)
        circuitOpen = true
        pending.removeAll()
        lock.unlock()
    }
}
