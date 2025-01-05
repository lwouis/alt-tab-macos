import Foundation

// queues and dedicated threads to observe background events such as keyboard inputs, or accessibility events
class BackgroundWork {
    static var screenshotsQueue: DispatchQueue!
    static var accessibilityCommandsQueue: DispatchQueue!
    static var axCallsQueue: DispatchQueue!
    static var crashReportsQueue: DispatchQueue!
    static var accessibilityEventsThread: BackgroundThreadWithRunLoop!
    static var keyboardEventsThread: BackgroundThreadWithRunLoop!
    static var systemPermissionsThread: BackgroundThreadWithRunLoop!
    static var repeatingKeyThread: BackgroundThreadWithRunLoop!
    static var missionControlThread: BackgroundThreadWithRunLoop!
    static var cliEventsThread: BackgroundThreadWithRunLoop!
    static let screenshotsDispatchGroup = DispatchGroup()

    // swift static variables are lazy; we artificially force the threads to init
    static func start() {
        // screenshots are taken off the main thread, concurrently
        screenshotsQueue = DispatchQueue.globalConcurrent("screenshotsQueue", .userInteractive)
        // calls to act on windows (e.g. AXUIElementSetAttributeValue, AXUIElementPerformAction) are done off the main thread
        accessibilityCommandsQueue = DispatchQueue.globalConcurrent("accessibilityCommandsQueue", .userInteractive)
        // calls to the AX APIs are blocking. We dispatch those on a globalConcurrent queue
        axCallsQueue = DispatchQueue.globalConcurrent("axCallsQueue", .userInteractive)
        // we observe app and windows notifications. They arrive on this thread, and are handled off the main thread initially
        accessibilityEventsThread = BackgroundThreadWithRunLoop("accessibilityEventsThread", .userInteractive)
        // we listen to as any keyboard events as possible on a background thread, as it's more available/reliable than the main thread
        keyboardEventsThread = BackgroundThreadWithRunLoop("keyboardEventsThread", .userInteractive)
        // we time key repeat on a background thread for precision. We handle their consequence on the main-thread
        repeatingKeyThread = BackgroundThreadWithRunLoop("repeatingKeyThread", .userInteractive)
        // we main Mission Control state on a background thread. We protect reads from main-thread with an NSLock
        missionControlThread = BackgroundThreadWithRunLoop("missionControlThread", .userInteractive)
        // we listen to CLI commands (CFMessagePort events)
        cliEventsThread = BackgroundThreadWithRunLoop("cliEventsThread", .userInteractive)
    }

    static func startCrashReportsQueue() {
        if crashReportsQueue == nil {
            // crash reports can be sent off the main thread
            crashReportsQueue = DispatchQueue.globalConcurrent("crashReportsQueue", .utility)
        }
    }

    static func startSystemPermissionThread() {
        // not 100% sure this shouldn't be on the main-thread; it doesn't do anything except dispatch to main.async
        systemPermissionsThread = BackgroundThreadWithRunLoop("systemPermissionsThread", .utility)
    }

    class BackgroundThreadWithRunLoop: Thread {
        var runLoop: CFRunLoop?
        // Thread.start() is async; we use a semaphore to make the init() sync
        private let threadStartSemaphore = DispatchSemaphore(value: 0)

        init(_ name: String, _ qos: DispatchQoS) {
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
}

// we cap concurrent tasks to .processorCount to avoid thread explosion on the .global queue
let backgroundWorkGlobalSemaphore = DispatchSemaphore(value: ProcessInfo.processInfo.processorCount)

extension DispatchQueue {
    static func globalConcurrent(_ label: String, _ qos: DispatchQoS) -> DispatchQueue {
        // label is not reflected in Instruments because the target is .global
        // if we want to see our custom labels, we need our private queue.
        // However, we want to be efficient and use the OS thread pool, so we use .global
        DispatchQueue(label: label, attributes: .concurrent, target: .global(qos: qos.qosClass))
    }

    func asyncWithCap(_ deadline: DispatchTime? = nil, _ fn: @escaping () -> Void) {
        let block = {
            fn()
            backgroundWorkGlobalSemaphore.signal()
        }
        backgroundWorkGlobalSemaphore.wait()
        if let deadline = deadline {
            asyncAfter(deadline: deadline, execute: block)
        } else {
            async(execute: block)
        }
    }
}
