import Cocoa
import ApplicationServices.HIServices.AXNotificationConstants

/// Pure routing/classification for incoming AX events — extracted from `AccessibilityEvents` and
/// `AXCallScheduler` so the design's decisions are unit-testable without queues, threads, or timing
/// (same idea as `SelectionResolver`). The wrappers turn these decisions into actual scheduling.
enum AxEventRouting {
    /// the bounded pool an outgoing AX query runs on (see `AXCallScheduler`).
    enum Pool: Equatable { case firstTry, scan, retry }

    /// A timed-out (unresponsive) app is quarantined to `retry` regardless of caller; otherwise the bursty
    /// periodic inventory is isolated on `scan`, and everything else is an event-driven `firstTry`.
    static func pool(unresponsive: Bool, scan: Bool) -> Pool {
        if unresponsive { return .retry }
        return scan ? .scan : .firstTry
    }

    /// The ONLY events we coalesce: resize/move/title self-flood during a live drag (60–120/s), each needing
    /// a fresh attribute read. Every other AX event is edge-triggered and must run promptly (no coalescing).
    static func coalesces(_ type: String) -> Bool {
        type == kAXWindowResizedNotification || type == kAXWindowMovedNotification || type == kAXTitleChangedNotification
    }

    /// app-level notifications (subscribed on the app element).
    static func isAppEvent(_ type: String) -> Bool {
        type == kAXApplicationActivatedNotification || type == kAXApplicationHiddenNotification || type == kAXApplicationShownNotification
    }

    /// focus/main/activation carry MRU-order info that can't be re-queried; they take the prompt, IPC-free
    /// fast path (`focusOrderQueue`) rather than going through an attribute read.
    static func updatesFocusOrder(_ type: String) -> Bool {
        type == kAXFocusedWindowChangedNotification || type == kAXMainWindowChangedNotification || type == kAXApplicationActivatedNotification
    }

    /// window-event bucket: non-interchangeable handling must land in different buckets.
    static func windowBucket(_ type: String) -> String {
        switch type {
            case kAXMainWindowChangedNotification, kAXFocusedWindowChangedNotification: return "focus"
            case kAXWindowResizedNotification, kAXWindowMovedNotification: return "geometry"
            default: return "generic"
        }
    }

    /// `AXCallScheduler` de-dups in-flight calls per key, so non-interchangeable work must NOT share a key
    /// (else one is dropped while the other is running). App events split activation vs visibility;
    /// window events split focus / geometry / generic. (The bare `pid-<n>` scan key is owned by
    /// `manuallyUpdateWindows`, so it never collides with these.)
    static func dedupKey(_ type: String, pid: pid_t, wid: CGWindowID) -> String {
        if isAppEvent(type) {
            let bucket = type == kAXApplicationActivatedNotification ? "activate" : "visibility"
            return "pid-\(pid)-\(bucket)"
        }
        return "wid-\(wid)-\(windowBucket(type))"
    }
}
