import Foundation

// queues and dedicated threads to observe background events such as keyboard inputs, or accessibility events
class BackgroundWork {
    // we use an OperationQueue tied to the global DispatchQueue to call blocking APIs in parallel
    static var screenshotsQueue: LabeledOperationQueue!
    static var accessibilityCommandsQueue: LabeledOperationQueue!
    static var axCallsFirstAttemptQueue: LabeledOperationQueue!
    static var axCallsRetriesQueue: LabeledOperationQueue!
    static var crashReportsQueue: LabeledOperationQueue!
    // we use Threads to observe events in sequence
    static var accessibilityEventsThread: BackgroundThreadWithRunLoop!
    static var keyboardAndTrackpadEventsThread: BackgroundThreadWithRunLoop!
    static var systemPermissionsThread: BackgroundThreadWithRunLoop!
    static var repeatingKeyThread: BackgroundThreadWithRunLoop!
    static var missionControlThread: BackgroundThreadWithRunLoop!
    static var cliEventsThread: BackgroundThreadWithRunLoop!

    private static var totalPotentialThreadCount = 0

    static func start() {
        // screenshots are taken on a serial DispatchQueue. They used to be taken on the .global() concurrent queue.
        // it could hang the app since the screenshot OS calls are slow. It would hang or crash with this error:
        // >Processes reached dispatch thread soft limit (64)
        screenshotsQueue = LabeledOperationQueue("screenshotsQueue", .userInteractive, 8)
        // calls to focus/close/minimize/etc windows
        // They are tried once and if they timeout we don't retry. The OS seems to still execute them even if the call timed out
        accessibilityCommandsQueue = LabeledOperationQueue("accessibilityCommandsQueue", .userInteractive, 4)
        // calls to the AX APIs can block for a long time (e.g. if an app is unresponsive)
        // We first try the AX calls on axCallsFirstAttemptQueue. If we get a timeout, we move to axCallsRetriesQueue and retry there for a while
        axCallsFirstAttemptQueue = LabeledOperationQueue("axCallsFirstAttemptQueue", .userInteractive, 8)
        axCallsRetriesQueue = LabeledOperationQueue("axCallsRetriesQueue", .userInteractive, 8)
        // we observe app and windows notifications. They arrive on this thread, and are handled off the main thread initially
        accessibilityEventsThread = BackgroundThreadWithRunLoop("accessibilityEventsThread", .userInteractive)
        // we listen to as any keyboard events as possible on a background thread, as it's more available/reliable than the main thread
        keyboardAndTrackpadEventsThread = BackgroundThreadWithRunLoop("keyboardAndTrackpadEventsThread", .userInteractive)
        // we time key repeat on a background thread for precision. We handle their consequence on the main-thread
        repeatingKeyThread = BackgroundThreadWithRunLoop("repeatingKeyThread", .userInteractive)
        // we main Mission Control state on a background thread. We protect reads from main-thread with an NSLock
        missionControlThread = BackgroundThreadWithRunLoop("missionControlThread", .userInteractive)
        // we listen to CLI commands (CFMessagePort events)
        cliEventsThread = BackgroundThreadWithRunLoop("cliEventsThread", .userInteractive)
//        logThreadsAndQueuesOnRepeat()
    }

    static func startCrashReportsQueue() {
        if crashReportsQueue == nil {
            // crash reports can be sent off the main thread
            crashReportsQueue = LabeledOperationQueue("crashReportsQueue", .utility, 1)
        }
    }

    static func startSystemPermissionThread() {
        // not 100% sure this shouldn't be on the main-thread; it doesn't do anything except dispatch to main.async
        systemPermissionsThread = BackgroundThreadWithRunLoop("systemPermissionsThread", .utility)
    }

    static func addPotentialThreadCount(_ additionalCount: Int) {
        totalPotentialThreadCount += additionalCount
        // a macos process has a soft limit of 64 threads. We need to be careful to don't spawn too many threads through DispatchQueues
        assert(totalPotentialThreadCount <= 36)
    }

    // useful during development to inspect how many threads are used by AltTab
    private static func logThreadsAndQueuesOnRepeat() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            logThreads()
            logQueues()
        }
    }

    private static func logQueues() -> Void {
        let queues = [screenshotsQueue, accessibilityCommandsQueue, axCallsFirstAttemptQueue, axCallsRetriesQueue, crashReportsQueue].compactMap { $0 }
        var map = [String:Int]()
        for queue in queues {
            map[queue.underlyingQueue!.label] = queue.operations.reduce(0) { $1.isExecuting ? $0 + 1 : $0 }
        }
        let prettyPrintMap = map.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        Logger.debug(prettyPrintMap)
    }

    private static func logThreads() -> Void {
        var count: mach_msg_type_number_t = 0
        var threadList: thread_act_array_t?
        let kr = task_threads(mach_task_self_, &threadList, &count)
        guard kr == KERN_SUCCESS, let threads = threadList else { return }
        var namedThreads = [String]()
        var unnamedThreadsCount = 0
        for i in 0..<Int(count) {
            let thread = threads[i]
            if let pth = pthread_from_mach_thread_np(thread) {
                var nameBuffer = [CChar](repeating: 0, count: 64)
                if pthread_getname_np(pth, &nameBuffer, nameBuffer.count) == 0 {
                    let name = String(cString: nameBuffer)
                    if !name.isEmpty {
                        namedThreads.append(name)
                    } else {
                        unnamedThreadsCount += 1
                    }
                }
            }
        }
        vm_deallocate(mach_task_self_,
            vm_address_t(bitPattern: threads),
            vm_size_t(count) * vm_size_t(MemoryLayout<thread_t>.size))
        Logger.info(namedThreads.count, "Named threads:", namedThreads.sorted())
        Logger.info(unnamedThreadsCount, "Unnamed threads (e.g. from GCD queues)")
    }

    class BackgroundThreadWithRunLoop: Thread {
        var runLoop: CFRunLoop?
        // Thread.start() is async; we use a semaphore to make the init() sync
        private let threadStartSemaphore = DispatchSemaphore(value: 0)

        init(_ name: String, _ qos: DispatchQoS) {
            addPotentialThreadCount(1)
            super.init()
            self.name = name
            qualityOfService = qos.toQualityOfService()
            start()
            threadStartSemaphore.wait()
        }

        override func main() {
            Logger.debug(name)
            // the RunLoop is lazy; calling this initialize it
            runLoop = CFRunLoopGetCurrent()
            addDummySourceToPreventRunLoopTermination()
            threadStartSemaphore.signal()
            CFRunLoopRun()
        }

        /// Adding a no-op source keeps the RunLoop running until actual sources are added.
        /// Otherwise, it would terminate on `CFRunLoopRun()`.
        private func addDummySourceToPreventRunLoopTermination() {
            var context = CFRunLoopSourceContext()
            context.perform = { _ in }
            let source = CFRunLoopSourceCreate(nil, 0, &context)
            CFRunLoopAddSource(runLoop, source, .commonModes)
        }
    }

    class LabeledOperationQueue: OperationQueue, @unchecked Sendable {
        private let strongUnderlyingQueue: DispatchQueue

        init(_ label: String, _ qos: DispatchQoS, _ maxConcurrentOperationCount: Int) {
            strongUnderlyingQueue = DispatchQueue(label: label, attributes: [.concurrent])
            super.init()
            self.maxConcurrentOperationCount = maxConcurrentOperationCount
            addPotentialThreadCount(maxConcurrentOperationCount)
            self.underlyingQueue = strongUnderlyingQueue
        }

        override func addOperation(_ block: @escaping () -> ()) {
            super.addOperation(block)
        }

        func addOperationAfter(deadline: DispatchTime, block: @escaping @convention(block) () -> Void) {
            strongUnderlyingQueue.asyncAfter(deadline: deadline) { [weak self] in
                self?.addOperation(block)
            }
        }
    }
}
