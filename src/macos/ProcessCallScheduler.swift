import Cocoa

/// Off-main scheduler for blocking process & sysctl queries. Sibling of `AXCallScheduler` (Accessibility)
/// and `CGSCallScheduler` (WindowServer). Runs the work off the main thread and delivers results on main.
class ProcessCallScheduler {
    // 2 keeps the thread budget lean (see BackgroundWork); the startup burst of classifications still
    // drains in well under a second, and it runs async so it never blocks launch.
    private static let queue = LabeledOperationQueue("processCall", .userInitiated, 2)

    #if DEBUG
    // read-only handle for the "Live queue graph" sampler (DebugMenu); keeps `queue` private otherwise
    static var debugQueue: LabeledOperationQueue { queue }
    #endif

    /// Whether a pid is a real, switchable application. The XPC / zombie / emulator checks behind this do
    /// process & sysctl IPC, so we run them off-main and deliver the verdict on main.
    static func isActualApplication(_ pid: pid_t, _ bundleId: String?, thenMain: @escaping (Bool) -> Void) {
        queue.addOperation {
            let verdict = ApplicationDiscriminator.isActualApplication(pid, bundleId)
            DispatchQueue.main.async { thenMain(verdict) }
        }
    }
}
