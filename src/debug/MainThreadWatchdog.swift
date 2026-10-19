#if DEBUG
import Foundation

/// Samples the main thread's stack while it stays busy past `thresholdInMs`, and logs the samples once it is
/// free again. `MainThreadStall` only names functions that call `step()`; this covers the rest. Measured
/// 2026-10-18: during rapid alt-tabs, a ⌥ release reached the event tap on time, then waited 400ms for main,
/// and no instrumented step accounted for it.
///
/// "Busy" is the time between the run loop waking (`afterWaiting`) and going back to sleep (`beforeWaiting`),
/// so a nested run loop that never sleeps in a common mode counts too: main is not serving input either way.
/// A sample suspends main, reads its registers and walks its frame-pointer chain, then resumes it. Nothing
/// allocates or takes a lock while main is suspended: main may hold the malloc or dyld lock at that moment.
/// Frames are logged as `image+offset`; when a symbol is missing, `atos -o <image> -l <load address>`
/// resolves the address (load address = address minus offset, for the main executable add 0x100000000).
enum MainThreadWatchdog {
    static let thresholdInMs = 100.0
    private static let intervalInMs = 50
    private static let maxSamples = 20
    private static let maxFrames = 64
    private static let queue = DispatchQueue(label: "mainThreadWatchdog", qos: .userInteractive)
    private static var timer: DispatchSourceTimer?
    private static var observer: CFRunLoopObserver?
    private static var mainThread = thread_act_t(0)
    private static var stack = UInt(0)...UInt(0)
    private static let frameBuffer = UnsafeMutablePointer<UInt>.allocate(capacity: maxFrames)
    private static let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()
    // guarded by `lock`
    private static var busySince: Double?
    private static var lastBusy: (since: Double, until: Double)?
    // only touched on `queue`
    private static var stall: (since: Double, samples: [[UInt]])?

    /// Call once, on main.
    static func start() {
        guard Thread.isMainThread, timer == nil else { return }
        let thread = pthread_self()
        mainThread = pthread_mach_thread_np(thread)
        let top = UInt(bitPattern: pthread_get_stackaddr_np(thread))
        stack = (top - UInt(pthread_get_stacksize_np(thread)))...top
        // A static is initialized on first access, which may allocate: that must not happen while main is suspended.
        frameBuffer.initialize(repeating: 0, count: maxFrames)
        observeRunLoop()
        startTimer()
    }

    private static func observeRunLoop() {
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, 0) { _, activity in
            let now = ProcessInfo.processInfo.systemUptime
            os_unfair_lock_lock(lock)
            if activity == .afterWaiting {
                busySince = now
            } else if let since = busySince {
                // Only long periods: the short turns that drain the backlog right after a stall must not replace it.
                if (now - since) * 1000 >= thresholdInMs { lastBusy = (since, now) }
                busySince = nil
            }
            os_unfair_lock_unlock(lock)
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private static func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(intervalInMs), leeway: .milliseconds(10))
        timer.setEventHandler { tick() }
        timer.resume()
        self.timer = timer
    }

    private static func tick() {
        os_unfair_lock_lock(lock)
        let since = busySince
        let ended = lastBusy
        os_unfair_lock_unlock(lock)
        if let current = stall, current.since != since { report(current, ended) }
        guard let since, (ProcessInfo.processInfo.systemUptime - since) * 1000 >= thresholdInMs else { return }
        if stall?.since != since { stall = (since, []) }
        guard stall!.samples.count < maxSamples else { return }
        stall!.samples.append(sample())
    }

    private static func report(_ current: (since: Double, samples: [[UInt]]), _ ended: (since: Double, until: Double)?) {
        stall = nil
        let duration = ended.flatMap { $0.since == current.since ? $0.until - $0.since : nil }
        let length = duration.map { "\(Int(($0 * 1000).rounded()))ms" } ?? "over \(Int(thresholdInMs))ms"
        let stacks = grouped(current.samples).map { "\($0.count)x: " + $0.frames.map(symbol).joined(separator: " < ") }
        Logger.warning { "main was busy for \(length); \(current.samples.count) stack samples, innermost frame first:\n" + stacks.joined(separator: "\n") }
    }

    /// Consecutive identical samples are merged, so a single long call reads as one stack with a count.
    private static func grouped(_ samples: [[UInt]]) -> [(count: Int, frames: [UInt])] {
        samples.reduce(into: []) { groups, frames in
            if groups.last?.frames == frames { groups[groups.count - 1].count += 1 } else { groups.append((1, frames)) }
        }
    }

    private static func symbol(_ address: UInt) -> String {
        var info = Dl_info()
        guard dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0, let file = info.dli_fname else { return String(address, radix: 16) }
        let image = (String(cString: file) as NSString).lastPathComponent
        let offset = "+0x" + String(address - UInt(bitPattern: info.dli_fbase), radix: 16)
        return image + offset + (info.dli_sname.map { " " + String(cString: $0) } ?? "")
    }

    private static func sample() -> [UInt] {
        guard thread_suspend(mainThread) == KERN_SUCCESS else { return [] }
        let count = walkStack()
        thread_resume(mainThread)
        return Array(UnsafeBufferPointer(start: frameBuffer, count: count))
    }

    /// Runs while main is suspended: fills `frameBuffer` and nothing else.
    private static func walkStack() -> Int {
        #if arch(arm64)
        var state = arm_thread_state64_t()
        var stateCount = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) { thread_get_state(mainThread, ARM_THREAD_STATE64, $0, &stateCount) }
        }
        guard result == KERN_SUCCESS else { return 0 }
        // Return addresses saved by arm64e system code carry a pointer-authentication signature in the high bits.
        let addressMask = UInt(0x0000_7FFF_FFFF_FFFF)
        frameBuffer[0] = UInt(state.__pc) & addressMask
        frameBuffer[1] = UInt(state.__lr) & addressMask
        var count = 2
        var fp = UInt(state.__fp)
        while count < maxFrames, fp % 8 == 0, stack.contains(fp), stack.contains(fp + 15) {
            let record = UnsafePointer<UInt>(bitPattern: fp)!
            frameBuffer[count] = record[1] & addressMask
            count += 1
            guard record[0] > fp else { break }
            fp = record[0]
        }
        return count
        #else
        return 0
        #endif
    }
}
#endif
