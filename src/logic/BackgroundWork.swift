import Foundation

// queues and dedicated threads to observe background events such as keyboard inputs, or accessibility events
class BackgroundWork {
    static var mainQueueConcurrentWorkQueue: DispatchQueue!
    static var accessibilityCommandsQueue: DispatchQueue!
    static var axCallsQueue: DispatchQueue!
    static var crashReportsQueue: DispatchQueue!
    static var accessibilityEventsThread: BackgroundThreadWithRunLoop!
    static var mouseEventsThread: BackgroundThreadWithRunLoop!
    static var keyboardEventsThread: BackgroundThreadWithRunLoop!
    static var systemPermissionsThread: BackgroundThreadWithRunLoop!
    static var repeatingKeyThread: BackgroundThreadWithRunLoop!
    static var missionControlThread: BackgroundThreadWithRunLoop!

    // we cap concurrent tasks to .processorCount to avoid thread explosion on the .global queue
    static let globalSemaphore = DispatchSemaphore(value: ProcessInfo.processInfo.processorCount)

    // swift static variables are lazy; we artificially force the threads to init
    static func start() {
        // TODO: clarify how this works
        mainQueueConcurrentWorkQueue = DispatchQueue.globalConcurrent("mainQueueConcurrentWorkQueue", .userInteractive)
        // calls to act on windows (e.g. AXUIElementSetAttributeValue, AXUIElementPerformAction) are done off the main thread
        accessibilityCommandsQueue = DispatchQueue.globalConcurrent("accessibilityCommandsQueue", .userInteractive)
        // calls to the AX APIs are blocking. We dispatch those on a globalConcurrent queue
        axCallsQueue = DispatchQueue.globalConcurrent("axCallsQueue", .userInteractive)
        // we observe app and windows notifications. They arrive on this thread, and are handled off the main thread initially
        accessibilityEventsThread = BackgroundThreadWithRunLoop("accessibilityEventsThread", .userInteractive)
        // we observe mouse clicks when thumbnailsPanel is open. They arrive on this thread, and are handled off the main thread initially
        mouseEventsThread = BackgroundThreadWithRunLoop("mouseEventsThread", .userInteractive)
        // some instances of events can be handled off the main thread; maybe not worth moving to a background thread
        keyboardEventsThread = BackgroundThreadWithRunLoop("keyboardEventsThread", .userInteractive)
        // not 100% sure this shouldn't be on the main-thread; it doesn't do anything except dispatch to main.async
        repeatingKeyThread = BackgroundThreadWithRunLoop("repeatingKeyThread", .userInteractive)
        // not 100% sure this shouldn't be on the main-thread; it doesn't do anything except dispatch to main.async
        missionControlThread = BackgroundThreadWithRunLoop("missionControlThread", .userInteractive)
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
}

extension DispatchQueue {
    static func globalConcurrent(_ label: String, _ qos: DispatchQoS) -> DispatchQueue {
        return DispatchQueue(label: label, attributes: .concurrent, target: .global(qos: qos.qosClass))
    }

    func asyncWithCap(_ deadline: DispatchTime? = nil, _ fn: @escaping () -> Void) {
        let block = {
            fn()
            BackgroundWork.globalSemaphore.signal()
        }
        BackgroundWork.globalSemaphore.wait()
        if let deadline = deadline {
            asyncAfter(deadline: deadline, execute: block)
        } else {
            async(execute: block)
        }
    }
}

class BackgroundThreadWithRunLoop {
    var thread: Thread?
    var runLoop: CFRunLoop?
    // Thread.start() is async; we use a semaphore to make the init() sync
    let threadStartSemaphore = DispatchSemaphore(value: 0)

    init(_ name: String, _ qos: DispatchQoS) {
        thread = Thread {
            logger.d(name)
            // the RunLoop is lazy; calling this initialize it
            self.runLoop = CFRunLoopGetCurrent()
            self.addDummySourceToPreventRunLoopTermination()
            self.threadStartSemaphore.signal()
            CFRunLoopRun()
        }
        thread!.name = name
        thread!.qualityOfService = qos.toQualityOfService()
        thread!.start()
        threadStartSemaphore.wait()
    }

    /// adding a no-op source keeps the RunLoop running until actual sources are added
    /// it would otherwise terminate on CFRunLoopRun()
    private func addDummySourceToPreventRunLoopTermination() {
        var context = CFRunLoopSourceContext()
        context.perform = { _ in }
        let source = CFRunLoopSourceCreate(nil, 0, &context)
        CFRunLoopAddSource(runLoop, source, .defaultMode)
    }
}
