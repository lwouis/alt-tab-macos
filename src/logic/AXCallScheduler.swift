import Foundation

class AXCallScheduler {
    static let shared = AXCallScheduler()

    let fastQueue: LabeledOperationQueue
    let retryQueue: LabeledOperationQueue

    private let lock = NSLock()
    private var keyStates = [String: KeyState]()
    private var unresponsivePids = Set<pid_t>()

    private static let throttleDelayNs: UInt64 = 200_000_000
    private static let giveUpAfterSeconds: Float = 60.0
    private static let backoffStepsNs: [UInt64] = [200_000_000, 1_000_000_000, 2_000_000_000, 5_000_000_000]

    private enum Phase {
        case idle
        case throttled
        case executing
        case retrying
    }

    private struct KeyState {
        var phase: Phase = .idle
        var lastExecutionTime: UInt64 = 0
        var retryStartTime: UInt64 = 0
        var retryCount = 0
        var pendingBlock: (() throws -> Void)?
        var pendingPid: pid_t?
        var pendingContext: String?
        var cancelRetries = false
    }

    private init() {
        fastQueue = LabeledOperationQueue("axCallsFast", .userInteractive, 16)
        retryQueue = LabeledOperationQueue("axCallsRetry", .userInteractive, 8)
    }

    func schedule(key: String, file: String = #file, function: String = #function, line: Int = #line, context: String = "", pid: pid_t? = nil, block: @escaping () throws -> Void) {
        lock.lock()
        var state = keyStates[key] ?? KeyState()
        switch state.phase {
        case .idle:
            let now = DispatchTime.now().uptimeNanoseconds
            let elapsed = now >= state.lastExecutionTime ? (now - state.lastExecutionTime) : Self.throttleDelayNs
            if elapsed >= Self.throttleDelayNs {
                state.phase = .executing
                keyStates[key] = state
                lock.unlock()
                submitToQueue(key: key, pid: pid, file: file, function: function, line: line, context: context, block: block)
            } else {
                state.phase = .throttled
                state.pendingBlock = block
                state.pendingPid = pid
                state.pendingContext = context
                keyStates[key] = state
                let remaining = Self.throttleDelayNs - elapsed
                lock.unlock()
                let queue = queueForPid(pid)
                queue.addOperationAfter(deadline: .now() + .nanoseconds(Int(remaining))) { [self] in
                    fireThrottled(key: key, file: file, function: function, line: line)
                }
            }
        case .throttled:
            state.pendingBlock = block
            state.pendingPid = pid
            state.pendingContext = context
            keyStates[key] = state
            lock.unlock()
        case .executing:
            state.pendingBlock = block
            state.pendingPid = pid
            state.pendingContext = context
            keyStates[key] = state
            lock.unlock()
        case .retrying:
            state.pendingBlock = block
            state.pendingPid = pid
            state.pendingContext = context
            state.cancelRetries = true
            keyStates[key] = state
            lock.unlock()
        }
    }

    func submit(_ block: @escaping () -> Void) {
        fastQueue.addOperation(block)
    }

    func removeEntry(key: String) {
        lock.lock()
        keyStates[key] = nil
        lock.unlock()
    }

    func removeUnresponsivePid(_ pid: pid_t) {
        lock.lock()
        unresponsivePids.remove(pid)
        lock.unlock()
    }

    private func queueForPid(_ pid: pid_t?) -> LabeledOperationQueue {
        if let pid, unresponsivePids.contains(pid) {
            return retryQueue
        }
        return fastQueue
    }

    private func fireThrottled(key: String, file: String, function: String, line: Int) {
        lock.lock()
        guard var state = keyStates[key], state.phase == .throttled, let block = state.pendingBlock else {
            lock.unlock()
            return
        }
        let pid = state.pendingPid
        let context = state.pendingContext ?? ""
        state.pendingBlock = nil
        state.pendingPid = nil
        state.pendingContext = nil
        state.phase = .executing
        keyStates[key] = state
        lock.unlock()
        attemptBlock(key: key, pid: pid, file: file, function: function, line: line, context: context, retryStartTime: DispatchTime.now().uptimeNanoseconds, block: block)
    }

    private func submitToQueue(key: String, pid: pid_t?, file: String, function: String, line: Int, context: String, block: @escaping () throws -> Void) {
        let queue = queueForPid(pid)
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

        let elapsed = Float(DispatchTime.now().uptimeNanoseconds - retryStartTime) / 1_000_000_000
        if elapsed >= Self.giveUpAfterSeconds {
            Logger.info { "AX call timed out after \(Int(Self.giveUpAfterSeconds))s. \(Self.logContext(file, function, line, context))" }
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
            let step = min(state.retryCount, Self.backoffStepsNs.count - 1)
            delayNs = Self.backoffStepsNs[step]
            state.retryCount += 1
            keyStates[key] = state
        } else {
            delayNs = Self.backoffStepsNs[0]
        }
        lock.unlock()

        Logger.debug { "Retrying AX call in \(delayNs / 1_000_000)ms. \(Self.logContext(file, function, line, context))" }
        retryQueue.addOperationAfter(deadline: .now() + .nanoseconds(Int(delayNs))) { [self] in
            attemptBlock(key: key, pid: pid, file: file, function: function, line: line, context: context, retryStartTime: retryStartTime, block: block)
        }
    }

    private func onComplete(key: String, file: String, function: String, line: Int) {
        lock.lock()
        if var state = keyStates[key] {
            state.lastExecutionTime = DispatchTime.now().uptimeNanoseconds
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
        state.pendingBlock = nil
        state.pendingPid = nil
        state.pendingContext = nil
        state.cancelRetries = false

        // apply throttle check before executing pending block
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now >= state.lastExecutionTime ? (now - state.lastExecutionTime) : Self.throttleDelayNs
        if elapsed >= Self.throttleDelayNs {
            state.phase = .executing
            keyStates[key] = state
            lock.unlock()
            let queue = queueForPid(pid)
            queue.addOperation { [self] in
                attemptBlock(key: key, pid: pid, file: file, function: function, line: line, context: context, retryStartTime: DispatchTime.now().uptimeNanoseconds, block: block)
            }
        } else {
            state.phase = .throttled
            state.pendingBlock = block
            state.pendingPid = pid
            state.pendingContext = context
            keyStates[key] = state
            let remaining = Self.throttleDelayNs - elapsed
            lock.unlock()
            let queue = queueForPid(pid)
            queue.addOperationAfter(deadline: .now() + .nanoseconds(Int(remaining))) { [self] in
                fireThrottled(key: key, file: file, function: function, line: line)
            }
        }
    }

    private static func logContext(_ file: String, _ function: String, _ line: Int, _ context: String) -> String {
        "\((file as NSString).lastPathComponent):\(line) \(function) \(context)"
    }
}
