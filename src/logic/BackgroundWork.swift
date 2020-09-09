import Foundation

// queues and dedicated threads to observe background events such as keyboard inputs, or accessibility events
class BackgroundWork {
    static var mainQueueConcurrentWorkQueue: DispatchQueue!
    static var accessibilityCommandsQueue: DispatchQueue!
    static var axCallsQueue: DispatchQueue!
    static var crashReportsQueue: DispatchQueue!
    static var accessibilityEventsThread: BackgroundThreadWithRunLoop!
    static var mouseEventsThread: BackgroundThreadWithRunLoop!
    static var systemPermissionsThread: BackgroundThreadWithRunLoop!
    static var repeatingKeyThread: BackgroundThreadWithRunLoop!

    // we cap concurrent tasks to .processorCount to avoid thread explosion on the .global queue
    static let globalSemaphore = DispatchSemaphore(value: ProcessInfo.processInfo.processorCount)
    // Thread.start() is async; we use a semaphore to ensure threads are actually ready before we continue the launch sequence
    static let threadStartSemaphore = DispatchSemaphore(value: 0)

    // swift static variables are lazy; we artificially force the threads to init
    static func start() {
        mainQueueConcurrentWorkQueue = DispatchQueue.globalConcurrent("mainQueueConcurrentWorkQueue", .userInteractive)
        accessibilityCommandsQueue = DispatchQueue.globalConcurrent("accessibilityCommandsQueue", .userInteractive)
        axCallsQueue = DispatchQueue.globalConcurrent("axCallsQueue", .userInteractive)
        crashReportsQueue = DispatchQueue.globalConcurrent("crashReportsQueue", .utility)
        accessibilityEventsThread = BackgroundThreadWithRunLoop("accessibilityEventsThread", .userInteractive)
        mouseEventsThread = BackgroundThreadWithRunLoop("mouseEventsThread", .userInteractive)
        repeatingKeyThread = BackgroundThreadWithRunLoop("repeatingKeyThread", .userInteractive)
    }

    static func startSystemPermissionThread() {
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
    var hasSentSemaphoreSignal = false

    init(_ name: String, _ qos: DispatchQoS) {
        thread = Thread {
            self.runLoop = CFRunLoopGetCurrent()
            while !self.thread!.isCancelled {
                if !self.hasSentSemaphoreSignal {
                    BackgroundWork.threadStartSemaphore.signal()
                    self.hasSentSemaphoreSignal = true
                }
                CFRunLoopRun()
                // avoid tight loop while waiting for the first runloop source to be added
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        thread!.name = name
        thread!.qualityOfService = qos.toQualityOfService()
        thread!.start()
        BackgroundWork.threadStartSemaphore.wait()
    }
}
