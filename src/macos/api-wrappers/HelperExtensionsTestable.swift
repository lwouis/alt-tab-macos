import Cocoa

// allow using a closure for NSControl action, instead of selector
class SelectorWrapper<T> {
    let selector: Selector
    let closure: (T) -> Void

    init(withClosure closure: @escaping (T) -> Void) {
        selector = #selector(callClosure)
        self.closure = closure
    }

    @objc
    private func callClosure(sender: AnyObject) {
        closure(sender as! T)
    }
}

fileprivate var handle: Int = 0

typealias ActionClosure = (NSControl) -> Void

extension NSControl {
    var onAction: ActionClosure? {
        get {
            return (objc_getAssociatedObject(self, &handle) as? SelectorWrapper<NSControl>)?.closure
        }
        set {
            if let newValue {
                let selectorWrapper = SelectorWrapper<NSControl>(withClosure: newValue)
                objc_setAssociatedObject(self, &handle, selectorWrapper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                action = selectorWrapper.selector
                target = selectorWrapper
            } else {
                objc_setAssociatedObject(self, &handle, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                action = nil
                target = nil
            }
        }
    }
}

extension NSWindow {
    /// AppKit persists window frames in `UserDefaults` as space-separated numbers ("x y w h",
    /// optionally followed by the save-time screen "x y w h"). On restore it rejects any frame that
    /// isn't finite or escapes Int32 bounds (CGRectContainsRect against INT_MIN..INT_MAX) by
    /// throwing NSInternalInconsistencyException — which aborts the app. Mirror that exact rule so a
    /// poison value (seen in the field after display reconfiguration) can be dropped before AppKit
    /// ever applies it. See `setFrameAutosaveNameSafely`.
    static func isValidPersistedFrame(_ string: String) -> Bool {
        let n = string.split(separator: " ").compactMap { Double($0) }
        guard n.count >= 4 else { return false } // need at least the window frame
        let lo = Double(Int32.min), hi = Double(Int32.max)
        guard n.allSatisfy({ $0.isFinite && $0 >= lo && $0 <= hi }) else { return false }
        let x = n[0], y = n[1], w = n[2], h = n[3]
        return w >= 0 && h >= 0 && (x + w) <= hi && (y + h) <= hi // w/h non-negative, no overflow
    }
}

extension pid_t {
    /// Whether the process still exists, asked of the kernel. `NSRunningApplication.isTerminated` is not an
    /// answer: it still reads `false` 1-3s after the process is gone (measured on macOS 27), while
    /// `NSWorkspace.runningApplications` announces the removal immediately. `EPERM` means the process
    /// exists but isn't ours to signal. A terminated `NSRunningApplication` reports pid `-1`, and
    /// `kill(-1, 0)` would probe every process the user owns, hence the sign check.
    /// A zombie still exists to the kernel and answers alive here; `isZombie` is the separate question.
    func isAlive() -> Bool {
        guard self > 0 else { return false }
        return kill(self, 0) == 0 || errno == EPERM
    }

    func isZombie() -> Bool {
        var kinfo = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, self]
        sysctl(&mib, u_int(mib.count), &kinfo, &size, nil, 0)
        return kinfo.kp_proc.p_stat == SZOMB
    }
}
