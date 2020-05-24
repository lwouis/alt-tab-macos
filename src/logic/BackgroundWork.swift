import Foundation

// queues and dedicated threads to observe background events such as keyboard inputs, or accessibility events
class BackgroundWork {
    static let uiDisplayQueue = DispatchQueue.globalConcurrent("mainQueueConcurrentWork", .userInteractive)
    static let accessibilityCommandsQueue = DispatchQueue.globalConcurrent("accessibilityCommands", .userInteractive)
    static let accessibilityEventsThread = BackgroundThreadWithRunLoop("accessibilityEvents")
    static let keyboardEventsThread = BackgroundThreadWithRunLoop("keyboardEvents")

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
            }
        }
        thread!.name = name
        thread!.start()
    }
}
