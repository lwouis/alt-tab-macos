import Foundation

// queues and dedicated threads to observe background events such as keyboard inputs, or accessibility events
class BackgroundWork {
    // we use Threads when the APIs we observe require a RunLoop (e.g. CGEvent.tapCreate, AXObserverGetRunLoopSource, CFMessagePortCreateRunLoopSource)
    // when possible, we prefer OperationQueues
    static var accessibilityEventsThread: BackgroundThreadWithRunLoop!
    static var keyboardAndMouseAndTrackpadEventsThread: BackgroundThreadWithRunLoop!
    static var missionControlThread: BackgroundThreadWithRunLoop!
    static var cliEventsThread: BackgroundThreadWithRunLoop!

    // we use an OperationQueue for most tasks, especially when we need to call blocking APIs in parallel
    static var repeatingKeyQueue: LabeledOperationQueue!
    static var screenshotsQueue: LabeledOperationQueue!
    static var accessibilityCommandsQueue: LabeledOperationQueue!
    static var axCallsFirstAttemptQueue: LabeledOperationQueue!
    static var axCallsRetriesQueue: LabeledOperationQueue!
    static var axCallsManualDiscoveryQueue: LabeledOperationQueue!
    static var crashReportsQueue: LabeledOperationQueue!
    static var permissionsCheckOnTimerQueue: LabeledOperationQueue!
    static var permissionsSystemCallsQueue: LabeledOperationQueue!

    private static var debugMenu: DebugMenu!
    private static var totalPotentialThreadCount = 0

    static func preStart() {
        // we make calls to the system permissions API to know if permissions are granted. We do this on a timer
        permissionsCheckOnTimerQueue = LabeledOperationQueue("permissionsCheckOnTimer", .userInteractive, 1)
        // if macOS is overwhelmed, let's reduce the pressure on it by calling permission APIs one at a time
        permissionsSystemCallsQueue = LabeledOperationQueue("permissionsSystemCalls", .userInteractive, 1)
    }

    static func start() {
        screenshotsQueue = LabeledOperationQueue("screenshots", .userInteractive, 8)
        // calls to focus/close/minimize/etc windows
        // They are tried once and if they timeout we don't retry. The OS seems to still execute them even if the call timed out
        accessibilityCommandsQueue = LabeledOperationQueue("axCommands", .userInteractive, 4)
        // calls to the AX APIs can block for a long time (e.g. if an app is unresponsive)
        // We first try the AX calls on axCallsFirstAttemptQueue. If we get a timeout, we move to axCallsRetriesQueue and retry there for a while
        axCallsFirstAttemptQueue = LabeledOperationQueue("axCallsFirst", .userInteractive, 8)
        axCallsRetriesQueue = LabeledOperationQueue("axCallsRetry", .userInteractive, 8)
        // we separate calls to manuallyUpdateWindows since those can be very heavy and numerous
        axCallsManualDiscoveryQueue = LabeledOperationQueue("axCallsManual", .userInteractive, 8)
        // we time key repeat on a background queue. We handle their consequence on the main-thread
        repeatingKeyQueue = LabeledOperationQueue("repeatingKey", .userInteractive, 1)
        // we observe app and windows notifications. They arrive on this thread, and are handled off the main thread initially
        accessibilityEventsThread = BackgroundThreadWithRunLoop("axEvents", .userInteractive)
        // we listen to as any keyboard events as possible on a background thread, as it's more available/reliable than the main thread
        keyboardAndMouseAndTrackpadEventsThread = BackgroundThreadWithRunLoop("inputDevices", .userInteractive)
        // we main Mission Control state on a background thread. We protect reads from main-thread with an NSLock
        missionControlThread = BackgroundThreadWithRunLoop("missionControl", .userInteractive)
        // we listen to CLI commands (CFMessagePort events)
        cliEventsThread = BackgroundThreadWithRunLoop("cliMessages", .userInteractive)
       // logThreadsAndQueuesOnRepeat()
    }

    static func startCrashReportsQueue() {
        if crashReportsQueue == nil {
            // crash reports can be sent off the main thread
            crashReportsQueue = LabeledOperationQueue("crashReports", .utility, 1)
        }
    }

    static func addPotentialThreadCount(_ additionalCount: Int) {
        totalPotentialThreadCount += additionalCount
        // a macos process has a soft limit of 64 threads. We need to be careful to don't spawn too many threads through DispatchQueues
        assert(totalPotentialThreadCount <= 45)
    }

    // useful during development to inspect how many threads are used by AltTab
    private static func logThreadsAndQueuesOnRepeat() {
        // if Logger.decideLevel() == .debug {
            debugMenu = DebugMenu([screenshotsQueue, accessibilityCommandsQueue, axCallsFirstAttemptQueue, axCallsRetriesQueue, axCallsManualDiscoveryQueue])
            debugMenu.orderFront(nil)
            debugMenu.start()
            // Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            //     logThreads()
            //     logQueues()
            // }
        // }
    }

    private static func logQueues() -> Void {
        let queues = [screenshotsQueue, accessibilityCommandsQueue, axCallsFirstAttemptQueue, axCallsRetriesQueue, crashReportsQueue].compactMap { $0 }
        var map = [String:Int]()
        for queue in queues {
            map[queue.underlyingQueue!.label] = queue.operations.reduce(0) { $1.isExecuting ? $0 + 1 : $0 }
        }
        let prettyPrintMap = map.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        Logger.debug { prettyPrintMap }
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
        Logger.info { "\(namedThreads.count) named threads:\(namedThreads.sorted())" }
        Logger.info { "\(unnamedThreadsCount) unnamed threads (e.g. from GCD queues)" }
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
            Logger.debug { "Thread ready" }
            // the RunLoop is lazy; calling this initializes it
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
}

class LabeledOperationQueue: OperationQueue, @unchecked Sendable {
    let strongUnderlyingQueue: DispatchQueue
    private var _activeCallbacks: Int32 = 0
    var activeCallbacks: Int {
        Int(OSAtomicAdd32(0, &_activeCallbacks))
    }

    init(_ label: String, _ qos: DispatchQoS, _ maxConcurrentOperationCount: Int) {
        strongUnderlyingQueue = DispatchQueue(label: label, attributes: [.concurrent])
        super.init()
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
        BackgroundWork.addPotentialThreadCount(maxConcurrentOperationCount)
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

extension LabeledOperationQueue {
    @inline(__always)
    func trackCallbacks<T>(_ body: () throws -> T) rethrows -> T {
        OSAtomicIncrement32(&_activeCallbacks)
        defer { OSAtomicDecrement32(&_activeCallbacks) }
        return try body()
    }
}
