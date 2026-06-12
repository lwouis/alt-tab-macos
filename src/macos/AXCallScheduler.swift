import Foundation

/// Pure executor for outgoing AX calls. Two jobs, on purpose nothing else:
///   1. don't explode threads — calls run on bounded pools (a blocked AX call ties a worker for the 1s
///      messaging timeout, and the process has a ~64-thread hard limit).
///   2. don't hang on unresponsive apps — a call that times out is retried with backoff on a quarantine
///      pool, so one beach-balling app can't starve calls to the responsive ones.
///
/// It does NOT throttle/coalesce. Coalescing self-flooding inputs (resize/move/title) is the job of an
/// explicit `Throttler` at the call site (e.g. `Applications.windowAttributesThrottler`). The only
/// dedup here is per-key in-flight: a second call for a key already running is held as `pendingBlock`
/// and run once the current one finishes — never two concurrent calls for the same key.
class AXCallScheduler {
    static let shared = AXCallScheduler()

    // first-try: event-driven reads · scan: the bursty periodic inventory, isolated · retry: quarantine for timed-out apps
    let axQueryFirstTryQueue: LabeledOperationQueue
    let axQueryScanQueue: LabeledOperationQueue
    let axQueryRetryQueue: LabeledOperationQueue

    private let lock = NSLock()
    private var keyStates = [String: KeyState]()
    private var unresponsivePids = Set<pid_t>()

    private enum Phase {
        case idle
        case executing
        case retrying
    }

    private struct KeyState {
        var phase: Phase = .idle
        var retryCount = 0
        var scan = false
        var pendingBlock: (() throws -> Void)?
        var pendingPid: pid_t?
        var pendingContext: String?
        var pendingScan = false
        var cancelRetries = false
    }

    private init() {
        axQueryFirstTryQueue = LabeledOperationQueue("axQueryFirstTry", .userInteractive, 10)
        axQueryScanQueue = LabeledOperationQueue("axQueryScan", .userInteractive, 6)
        axQueryRetryQueue = LabeledOperationQueue("axQueryRetry", .userInteractive, 8)
    }

    /// Run an outgoing AX call, retrying with backoff if the app is unresponsive. `scan: true` routes the
    /// first attempt to the isolated scan pool so a bulk re-scan can't starve event-driven reads. No
    /// throttling — coalesce at the call site if the input self-floods.
    func schedule(key: String, file: String = #file, function: String = #function, line: Int = #line, context: String = "", pid: pid_t? = nil, scan: Bool = false, block: @escaping () throws -> Void) {
        lock.lock()
        var state = keyStates[key] ?? KeyState()
        switch state.phase {
        case .idle:
            state.phase = .executing
            state.scan = scan
            keyStates[key] = state
            lock.unlock()
            submitToQueue(key: key, pid: pid, scan: scan, file: file, function: function, line: line, context: context, block: block)
        case .executing, .retrying:
            // a call for this key is already in flight: hold the latest, run it when the current one finishes
            state.pendingBlock = block
            state.pendingPid = pid
            state.pendingContext = context
            state.pendingScan = scan
            if state.phase == .retrying { state.cancelRetries = true }
            keyStates[key] = state
            lock.unlock()
        }
    }

    /// `scan: true` routes to the isolated bursty-inventory pool instead of the event-read pool, so heavy
    /// off-main work (e.g. the per-Space `windowsInSpaces` fan-out in `Applications.syncSpacesState`) can't
    /// starve latency-critical focused-window reads.
    func submit(scan: Bool = false, _ block: @escaping () -> Void) {
        (scan ? axQueryScanQueue : axQueryFirstTryQueue).addOperation(block)
    }

    func removeEntry(key: String) {
        lock.lock()
        keyStates[key] = nil
        lock.unlock()
    }

    func removeEntries(withPrefix prefix: String) {
        lock.lock()
        for key in keyStates.keys where key.hasPrefix(prefix) {
            keyStates[key] = nil
        }
        lock.unlock()
    }

    func removeUnresponsivePid(_ pid: pid_t) {
        lock.lock()
        unresponsivePids.remove(pid)
        lock.unlock()
    }

    private func queueForPid(_ pid: pid_t?, scan: Bool) -> LabeledOperationQueue {
        let unresponsive = pid.map { unresponsivePids.contains($0) } ?? false
        switch AxEventRouting.pool(unresponsive: unresponsive, scan: scan) {
            case .firstTry: return axQueryFirstTryQueue
            case .scan: return axQueryScanQueue
            case .retry: return axQueryRetryQueue
        }
    }

    private func submitToQueue(key: String, pid: pid_t?, scan: Bool, file: String, function: String, line: Int, context: String, block: @escaping () throws -> Void) {
        let queue = queueForPid(pid, scan: scan)
        queue.addOperation { [self] in
            attemptBlock(key: key, pid: pid, file: file, function: function, line: line, context: context, retryStartTime: DispatchTime.now().uptimeNanoseconds, block: block)
        }
    }

    private func attemptBlock(key: String, pid: pid_t?, file: String, function: String, line: Int, context: String, retryStartTime: UInt64, block: @escaping () throws -> Void) {
        // check if cancelled by a newer request
        lock.lock()
        if let state = keyStates[key], state.cancelRetries {
            lock.unlock()
            drainPending(key: key, file: file, function: function, line: line)
            return
        }
        lock.unlock()

        if (try? block()) != nil {
            // success
            if let pid {
                lock.lock()
                unresponsivePids.remove(pid)
                lock.unlock()
            }
            onComplete(key: key, file: file, function: function, line: line)
            return
        }

        // failure
        if let pid {
            lock.lock()
            unresponsivePids.insert(pid)
            lock.unlock()
        }

        if RetryPolicy.shouldGiveUp(elapsedSinceStartNs: DispatchTime.now().uptimeNanoseconds - retryStartTime) {
            Logger.info { "AX call timed out after \(RetryPolicy.giveUpAfterNs / 1_000_000_000)s. \(Self.logContext(file, function, line, context))" }
            if let pid {
                lock.lock()
                unresponsivePids.remove(pid)
                lock.unlock()
            }
            onComplete(key: key, file: file, function: function, line: line)
            return
        }

        // schedule retry with backoff: 200ms, 1s, 2s, 5s, 5s, ...
        let delayNs: UInt64
        lock.lock()
        if var state = keyStates[key] {
            state.phase = .retrying
            delayNs = RetryPolicy.backoffDelayNs(retryCount: state.retryCount)
            state.retryCount += 1
            keyStates[key] = state
        } else {
            delayNs = RetryPolicy.backoffDelayNs(retryCount: 0)
        }
        lock.unlock()

        Logger.debug { "Retrying AX call in \(delayNs / 1_000_000)ms. \(Self.logContext(file, function, line, context))" }
        axQueryRetryQueue.addOperationAfter(deadline: .now() + .nanoseconds(Int(delayNs))) { [self] in
            attemptBlock(key: key, pid: pid, file: file, function: function, line: line, context: context, retryStartTime: retryStartTime, block: block)
        }
    }

    private func onComplete(key: String, file: String, function: String, line: Int) {
        lock.lock()
        if var state = keyStates[key] {
            state.phase = .idle
            state.cancelRetries = false
            state.retryCount = 0
            keyStates[key] = state
        }
        lock.unlock()
        drainPending(key: key, file: file, function: function, line: line)
    }

    private func drainPending(key: String, file: String, function: String, line: Int) {
        lock.lock()
        guard var state = keyStates[key], let block = state.pendingBlock else {
            if var state = keyStates[key] {
                state.cancelRetries = false
                state.phase = .idle
                keyStates[key] = state
            }
            lock.unlock()
            return
        }
        let pid = state.pendingPid
        let context = state.pendingContext ?? ""
        let scan = state.pendingScan
        state.pendingBlock = nil
        state.pendingPid = nil
        state.pendingContext = nil
        state.pendingScan = false
        state.cancelRetries = false
        state.phase = .executing
        state.scan = scan
        keyStates[key] = state
        lock.unlock()
        submitToQueue(key: key, pid: pid, scan: scan, file: file, function: function, line: line, context: context, block: block)
    }

    private static func logContext(_ file: String, _ function: String, _ line: Int, _ context: String) -> String {
        "\((file as NSString).lastPathComponent):\(line) \(function) \(context)"
    }
}
