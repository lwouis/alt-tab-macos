import Foundation

// queues and dedicated threads to observe background events such as keyboard inputs, or accessibility events
class BackgroundWork {
    static let mainQueueConcurrentWorkQueue = DispatchQueue.globalConcurrent("mainQueueConcurrentWorkQueue", .userInteractive)
    static let accessibilityCommandsQueue = DispatchQueue.globalConcurrent("accessibilityCommandsQueue", .userInteractive)
    static let axCallsQueue = DispatchQueue.globalConcurrent("axCallsQueue", .userInteractive)
    static let accessibilityEventsThread = BackgroundThreadWithRunLoop("accessibilityEventsThread")
    static let keyboardEventsThread = BackgroundThreadWithRunLoop("keyboardEventsThread")

    // we cap concurrent tasks to .processorCount to avoid thread explosion on the .global queue
    static let globalSemaphore = DispatchSemaphore(value: ProcessInfo.processInfo.processorCount)

    // swift static variables are lazy; we artificially force the threads to init
    static func start() {
        _ = accessibilityEventsThread
        _ = keyboardEventsThread
    }
}

extension DispatchQueue {
    static func globalConcurrent(_ label: String, _ qos: DispatchQoS) -> DispatchQueue {
        return DispatchQueue(label: label, target: .global(qos: qos.qosClass))
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

    init(_ name: String) {
        thread = Thread {
            self.runLoop = CFRunLoopGetCurrent()
            while !self.thread!.isCancelled {
                CFRunLoopRun()
                // avoid tight loop while waiting for the first runloop source to be added
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        thread!.name = name
        thread!.start()
    }
}
