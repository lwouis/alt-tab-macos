import Foundation

/// Pure executor for outgoing AX calls. Two jobs, on purpose nothing else:
///   1. don't explode threads — calls run on bounded pools (a blocked AX call ties a worker for the 1s
///      messaging timeout, and the process has a ~64-thread hard limit).
///   2. don't hang on unresponsive apps — a call that times out is retried with backoff on a quarantine
///      pool, so one beach-balling app can't starve calls to the responsive ones.
///
/// It does not delay calls against a guessed interval. Its per-key in-flight backpressure lets one call run
/// while retaining only the latest pending request, so a slow target naturally admits fewer calls without
/// making a responsive target wait — never two concurrent calls for the same key.
///
/// **Per-key dedup is not enough to keep one app off a whole lane**, because keys are per-window: an app
/// with 12 windows has 12 keys, and one wedged app could hold every worker of a 6-wide lane for the full 1s
/// messaging timeout each, so every OTHER app's reads waited behind it. `maxInFlightPerPid` bounds that
/// directly; the overflow waits in `waitingByPid` instead of on a worker.
class AXCallScheduler {
    static let shared = AXCallScheduler()

    // first-try: event-driven reads · scan: the bursty periodic inventory · retry: quarantine for timed-out
    // apps. Isolated from each other by width AND by QoS; see `init`.
    let axQueryFirstTryQueue: LabeledOperationQueue
    let axQueryScanQueue: LabeledOperationQueue
    let axQueryRetryQueue: LabeledOperationQueue

    /// How many calls to ONE process may be in flight at once, across all lanes. Half the narrowest lane
    /// (6), so a single app can never take more than half of any pool and at least three workers stay
    /// available to everyone else. Not lower: event-driven reads still arrive per window, and serializing a
    /// healthy app's legitimate focus/title/action burst too hard makes discovery visibly slow. Periodic
    /// inventory acquisition is separately grouped into one brute-force traversal per process.
    private static let maxInFlightPerPid = 3

    private let lock = NSLock()
    private var keyStates = [String: KeyState]()
    private var nextGeneration: UInt64 = 0
    private var unresponsivePids = Set<pid_t>()
    private var inFlightByPid = [pid_t: Int]()
    private var waitingByPid = [pid_t: [() -> Void]]()

    private enum Phase {
        case executing
        case retrying
    }

    private struct KeyState {
        let generation: UInt64
        var phase: Phase = .executing
        var retryCount = 0
        var pendingBlock: (() throws -> Void)?
        var pendingPid: pid_t?
        var pendingContext: String?
        var pendingScan = false
        var cancelRetries = false
    }

    /// **The three lanes are separated by QoS, not only by width.** An AX call is a synchronous Mach send,
    /// and macOS donates the caller's QoS to the receiving process for the duration — so the QoS here does
    /// not just order our own workers, it decides how fast the app on the other end answers us. Equal QoS
    /// across the lanes therefore did NOT give the first-try lane the isolation its width implies: a bulk
    /// scan asked every app to answer at the same priority as the read a summon was waiting on.
    private init() {
        // WindowServer now owns geometry/visibility/space reads (moved off these pools), so the event-read
        // first-try lane carries far less now (focus reads + element acquires); 8 is ample (was 10).
        // The only lane a user is ever waiting on, and the donation is working FOR us here.
        axQueryFirstTryQueue = LabeledOperationQueue("axQueryFirstTry", .userInteractive, 8)
        // The bursty periodic inventory: below the event-read lane on purpose, which is what actually keeps
        // it from starving a summon's reads.
        axQueryScanQueue = LabeledOperationQueue("axQueryScan", .userInitiated, 6)
        // ...and the unresponsive-app retry lane sees fewer queries too; 6 is ample. Freed budget funds the
        // wider cgsCall lane (B6). `.utility` because every call on it is a retry against an app that has
        // already blown the 1s messaging timeout, on a 200ms-5s backoff: nobody is waiting on any one of
        // them, and donating user-interactive to a wedged app only asks it to beach-ball at high priority.
        axQueryRetryQueue = LabeledOperationQueue("axQueryRetry", .utility, 6)
    }

    /// Run an outgoing AX call, retrying with backoff if the app is unresponsive. `scan: true` routes the
    /// first attempt to the isolated scan pool so a bulk re-scan can't starve event-driven reads. No
    /// throttling — coalesce at the call site if the input self-floods.
    func schedule(key: String, file: String = #file, function: String = #function, line: Int = #line, context: String = "", pid: pid_t? = nil, scan: Bool = false, block: @escaping () throws -> Void) {
        lock.lock()
        guard var state = keyStates[key] else {
            nextGeneration += 1
            let state = KeyState(generation: nextGeneration)
            keyStates[key] = state
            lock.unlock()
            submitToQueue(key: key, generation: state.generation, pid: pid, scan: scan, file: file, function: function, line: line, context: context, block: block)
            return
        }
        state.pendingBlock = block
        state.pendingPid = pid
        state.pendingContext = context
        state.pendingScan = scan
        if state.phase == .retrying { state.cancelRetries = true }
        keyStates[key] = state
        lock.unlock()
    }

    /// Calls queued, parked for a slot, or running. A key backing off on an unresponsive app is left out: it can
    /// keep retrying for `RetryPolicy.giveUpAfterNs`, and a caller waiting for AltTab to go idle would wait that out.
    var pendingCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return keyStates.values.filter { $0.phase == .executing }.count
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
        inFlightByPid[pid] = nil
        waitingByPid[pid] = nil
        lock.unlock()
    }

    private func queueForPid(_ pid: pid_t?, scan: Bool) -> LabeledOperationQueue {
        // under the lock: `unresponsivePids` is mutated from worker threads on every call outcome, and an
        // unsynchronized read of a Set being mutated is a crash, not merely a stale answer
        lock.lock()
        let unresponsive = pid.map { unresponsivePids.contains($0) } ?? false
        lock.unlock()
        switch AxQueryRouting.pool(unresponsive: unresponsive, scan: scan) {
            case .firstTry: return axQueryFirstTryQueue
            case .scan: return axQueryScanQueue
            case .retry: return axQueryRetryQueue
        }
    }

    /// Take one of this pid's `maxInFlightPerPid` slots and run `submit`, or park `submit` until a slot frees.
    /// Parking here rather than inside the operation is the whole point: a queued closure costs nothing,
    /// whereas an operation that blocks waiting for a slot would be occupying the worker it is waiting for.
    /// A call with no pid is unattributable and is never capped.
    private func acquireSlot(_ pid: pid_t?, _ submit: @escaping () -> Void) {
        guard let pid else { return submit() }
        lock.lock()
        let inFlight = inFlightByPid[pid] ?? 0
        guard inFlight < Self.maxInFlightPerPid else {
            waitingByPid[pid, default: []].append(submit)
            lock.unlock()
            return
        }
        inFlightByPid[pid] = inFlight + 1
        lock.unlock()
        submit()
    }

    /// Give the slot back and start the next call waiting on it. Called on EVERY exit from an attempt,
    /// including the one that schedules a retry: a key in backoff must not hold a slot for its whole 60s
    /// budget, or one wedged app's retries would occupy the cap permanently and its other windows would
    /// never be read at all.
    private func releaseSlot(_ pid: pid_t?) {
        guard let pid else { return }
        lock.lock()
        let remaining = (inFlightByPid[pid] ?? 1) - 1
        inFlightByPid[pid] = remaining > 0 ? remaining : nil
        var next: (() -> Void)?
        if var waiting = waitingByPid[pid], !waiting.isEmpty {
            next = waiting.removeFirst()
            waitingByPid[pid] = waiting.isEmpty ? nil : waiting
            inFlightByPid[pid] = (inFlightByPid[pid] ?? 0) + 1
        }
        lock.unlock()
        next?()
    }

    private func submitToQueue(key: String, generation: UInt64, pid: pid_t?, scan: Bool, file: String, function: String, line: Int, context: String, block: @escaping () throws -> Void) {
        acquireSlot(pid) { [self] in
            queueForPid(pid, scan: scan).addOperation { [self] in
                attemptBlock(key: key, generation: generation, pid: pid, file: file, function: function, line: line, context: context, retryStartTime: DispatchTime.now().uptimeNanoseconds, block: block)
            }
        }
    }

    private func attemptBlock(key: String, generation: UInt64, pid: pid_t?, file: String, function: String, line: Int, context: String, retryStartTime: UInt64, block: @escaping () throws -> Void) {
        lock.lock()
        guard let initialState = keyStates[key], initialState.generation == generation else {
            lock.unlock()
            releaseSlot(pid)
            return
        }
        if initialState.cancelRetries {
            lock.unlock()
            releaseSlot(pid)
            onComplete(key: key, generation: generation, file: file, function: function, line: line, resetRetryCount: false)
            return
        }
        lock.unlock()
        var outcome: Error?
        do { try block() } catch { outcome = error }
        lock.lock()
        guard var state = keyStates[key], state.generation == generation else {
            lock.unlock()
            releaseSlot(pid)
            return
        }
        guard let failure = outcome else {
            if let pid { unresponsivePids.remove(pid) }
            lock.unlock()
            releaseSlot(pid)
            onComplete(key: key, generation: generation, file: file, function: function, line: line)
            return
        }
        // `.noAnswer` is permanent for this call — a dead element, an attribute the app does not implement,
        // an app refusing the API. Retrying re-asks a question that cannot be answered, and quarantining the
        // app for it would push a process that answers everything else onto the slow lane.
        if case AxError.noAnswer = failure {
            lock.unlock()
            releaseSlot(pid)
            onComplete(key: key, generation: generation, file: file, function: function, line: line)
            return
        }
        if let pid { unresponsivePids.insert(pid) }
        if RetryPolicy.shouldGiveUp(elapsedSinceStartNs: DispatchTime.now().uptimeNanoseconds - retryStartTime) {
            lock.unlock()
            Logger.warning { "AX call timed out after \(RetryPolicy.giveUpAfterNs / 1_000_000_000)s. \(Self.logContext(file, function, line, context))" }
            // **The quarantine is NOT lifted here.** Giving up on one call says nothing about the app except
            // that it spent 60s not answering; clearing the flag would declare a permanently-wedged app healthy
            // every 60s and send its next burst of reads back onto the shared lane, starving every other app.
            // Only a call that SUCCEEDS releases a pid; until then it stays on the quarantine lane, which
            // refuses nothing and costs a recovered app one slow call.
            releaseSlot(pid)
            onComplete(key: key, generation: generation, file: file, function: function, line: line)
            return
        }
        state.phase = .retrying
        let delayNs = RetryPolicy.backoffDelayNs(retryCount: state.retryCount)
        state.retryCount += 1
        keyStates[key] = state
        lock.unlock()
        Logger.debug { "Retrying AX call in \(delayNs / 1_000_000)ms. \(Self.logContext(file, function, line, context))" }
        // The slot goes back BEFORE the backoff, and the re-attempt takes one again when it fires: a key in
        // backoff holds nothing, so the app's other windows keep being read while this one waits.
        releaseSlot(pid)
        axQueryRetryQueue.addOperationAfter(deadline: .now() + .nanoseconds(Int(delayNs))) { [self] in
            acquireSlot(pid) { [self] in
                axQueryRetryQueue.addOperation { [self] in
                    attemptBlock(key: key, generation: generation, pid: pid, file: file, function: function, line: line, context: context, retryStartTime: retryStartTime, block: block)
                }
            }
        }
    }

    private func onComplete(key: String, generation: UInt64, file: String, function: String, line: Int, resetRetryCount: Bool = true) {
        lock.lock()
        guard var state = keyStates[key], state.generation == generation else {
            lock.unlock()
            return
        }
        guard let block = state.pendingBlock else {
            keyStates[key] = nil
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
        if resetRetryCount { state.retryCount = 0 }
        state.phase = .executing
        keyStates[key] = state
        lock.unlock()
        submitToQueue(key: key, generation: generation, pid: pid, scan: scan, file: file, function: function, line: line, context: context, block: block)
    }

    private static func logContext(_ file: String, _ function: String, _ line: Int, _ context: String) -> String {
        "\((file as NSString).lastPathComponent):\(line) \(function) \(context)"
    }
}
