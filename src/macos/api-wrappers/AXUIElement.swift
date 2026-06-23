import Cocoa
import ApplicationServices.HIServices.AXUIElement
import ApplicationServices.HIServices.AXValue
import ApplicationServices.HIServices.AXError
import ApplicationServices.HIServices.AXRoleConstants
import ApplicationServices.HIServices.AXAttributeConstants
import ApplicationServices.HIServices.AXActionConstants

/// common, subscriptions
extension AXUIElement {
    // default timeout for AX calls is 6s
    // we reduce to 1s to avoid AX calls blocking threads, thus too many threads getting created to make the next AX calls
    private static let globalMessagingTimeoutInSeconds = Float(1)
    static func setGlobalTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), globalMessagingTimeoutInSeconds)
    }

    private func throwIfNotSuccess(_ result: AXError) throws -> Void {
        // .cannotComplete can happen if the app is unresponsive
        if result == .cannotComplete {
            throw AxError.runtimeError
        }
        // for success or other errors we don't throw
    }

    @discardableResult
    func subscribeToNotification(_ axObserver: AXObserver, _ notification: String, _ refcon: UnsafeMutableRawPointer? = nil) throws -> Bool {
        // `refcon` is handed back verbatim to the AX callback for every delivery of this (element,
        // notification) pair. The only remaining caller is DockEvents (Mission Control), which passes nil;
        // the packed-(pid, wid) refcon scheme this supported went away with the per-window AX observers.
        let result = AXObserverAddNotification(axObserver, self, notification as CFString, refcon)
        if result == .success || result == .notificationAlreadyRegistered {
            return true
        }
        if result == .notificationUnsupported || result == .notImplemented {
            // subscription will never succeed
            return false
        }
        // temporary issue; subscription may succeed if retried
        throw AxError.runtimeError
    }
}

/// Attributes
extension AXUIElement {
    /// our own process's pid, cached. used to spot same-process AX elements (see `onCorrectThread(pid:_:)`).
    static let currentProcessPid = ProcessInfo.processInfo.processIdentifier

    /// The single place the own-process-AX threading rule lives. An AX read on an element in ANOTHER process is
    /// real Mach IPC and runs inline on the caller's (off-main) thread. An AX read on an element in our OWN
    /// process does NO IPC — `AXUIElementCopy*` / `_AXUIElementGetWindow` dispatch straight into AppKit's
    /// accessibility implementation on the CALLING thread (e.g. `-[_NSPopoverWindow accessibilityTitle]`), and
    /// AppKit is main-thread-only, so off-main they race AppKit's teardown of transient windows and trap in
    /// `__CF_IS_OBJC`. So run `body` on the main thread when `pid` is our own process AND we're off-main (a
    /// `main.sync` from the main thread would deadlock); otherwise run it inline. Every pid-aware AX accessor
    /// (`attributes(_:pid:)`, `liveness(pid:)`, `cgWindowId(pid:)`, `WindowElementAcquisition`) funnels here.
    static func onCorrectThread<T>(pid: pid_t, _ body: () throws -> T) rethrows -> T {
        if pid == currentProcessPid, !Thread.isMainThread {
            return try DispatchQueue.main.sync { try body() }
        }
        return try body()
    }

    // periphery:ignore
    func id() -> AXUIElementID? {
        let pointer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque()).advanced(by: 0x20)
        let cfDataPointer = pointer.load(as: CFData?.self)
        let cfData = cfDataPointer
        let bytePtr = CFDataGetBytePtr(cfData)
        return bytePtr?.withMemoryRebound(to: AXUIElementID.self, capacity: 1) { $0.pointee }
    }

    func cgWindowId() throws -> CGWindowID {
        var id = CGWindowID(0)
        try throwIfNotSuccess(_AXUIElementGetWindow(self, &id))
        return id
    }

    /// pid-aware `cgWindowId()` — routes the own-process read to main. See `onCorrectThread(pid:_:)`.
    func cgWindowId(pid: pid_t) throws -> CGWindowID {
        try Self.onCorrectThread(pid: pid) { try cgWindowId() }
    }

    func pid() throws -> pid_t {
        var pid = pid_t(0)
        try throwIfNotSuccess(AXUIElementGetPid(self, &pid))
        return pid
    }

    /// A direct liveness probe for the window behind this element. Returns the raw `AXError` so the caller can
    /// tell a DEAD element (`.invalidUIElement` — the window was closed/destroyed) apart from a merely
    /// UNRESPONSIVE app (`.cannotComplete` — retry later) or a live one (`.success`). Reads `kAXRole`, the
    /// cheapest always-present attribute. Used to catch a close that WindowServer's destroy event (804) reports
    /// late or never — apps like Finder retain the CGWindow for seconds-to-forever after closing the window,
    /// but the AX element dies within ~20ms. Own-process read routed to main (see `onCorrectThread(pid:_:)`).
    func liveness(pid: pid_t) -> AXError {
        Self.onCorrectThread(pid: pid) {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(self, kAXRoleAttribute as CFString, &value)
        }
    }

    func attributes(_ keys: [String]) throws -> AXAttributes {
        var values: CFArray?
        try throwIfNotSuccess(AXUIElementCopyMultipleAttributeValues(self, keys as CFArray, [], &values))
        let array = values as? [CFTypeRef] ?? []
        var result = AXAttributes()
        for (index, key) in keys.enumerated() {
            guard index < array.count else { continue }
            let value = array[index]
            switch key {
            case kAXTitleAttribute: result.title = castSafely(value)
            case kAXRoleAttribute: result.role = castSafely(value)
            case kAXSubroleAttribute: result.subrole = castSafely(value)
            case kAXStatusLabelAttribute: result.statusLabel = castSafely(value)
            case kAXMinimizedAttribute: result.isMinimized = castSafely(value)
            case kAXFullscreenAttribute: result.isFullscreen = castSafely(value)
            case kAXMainAttribute: result.isMain = castSafely(value)
            case kAXIsApplicationRunningAttribute: result.appIsRunning = castSafely(value)
            case kAXURLAttribute: result.url = castSafely(value)
            case kAXParentAttribute: result.parent = castSafely(value)
            case kAXFocusedWindowAttribute: result.focusedWindow = castSafely(value)
            case kAXMainWindowAttribute: result.mainWindow = castSafely(value)
            case kAXCloseButtonAttribute: result.closeButton = castSafely(value)
            case kAXChildrenAttribute: result.children = castSafely(value)
            case kAXWindowsAttribute: result.windows = castSafely(value)
            case kAXPositionAttribute: result.position = castSafely(value)
            case kAXSizeAttribute: result.size = castSafely(value)
            default: Logger.error { "key:\(key) value:\(value)" }
            }
        }
        return result
    }

    /// pid-aware variant of `attributes(_:)` — routes the own-process read to main. See `onCorrectThread(pid:_:)`.
    func attributes(_ keys: [String], pid: pid_t) throws -> AXAttributes {
        try Self.onCorrectThread(pid: pid) { try attributes(keys) }
    }

    func castSafely<T>(_ value: CFTypeRef) -> T? {
        switch CFGetTypeID(value) {
        case AXValueGetTypeID():
            let axValue = value as! AXValue
            switch AXValueGetType(axValue) {
            case .axError:
                // without .stopOnError, AXUIElementCopyMultipleAttributeValues always returns an array. it contains placeholder values.
                // This makes it very hard to know what's real. For example, if an app has no MainWindow, it will return .axError. If we cast it to AXUIElement, it will succeed, but the object will have its attributes zero'd
                // we have to check for .axError, which we map to nil values
                return nil
            case .cgSize:
                var size = CGSize.zero
                AXValueGetValue(axValue, .cgSize, &size)
                return size as? T
            case .cgPoint:
                var point = CGPoint.zero
                AXValueGetValue(axValue, .cgPoint, &point)
                return point as? T
            case let unknownAXValueType:
                Logger.error { unknownAXValueType }
                return nil
            }
        case AXUIElementGetTypeID(): return value as? T
        case CFArrayGetTypeID(): return value as? T
        case CFURLGetTypeID(): return value as? T
        case CFStringGetTypeID(): return value as? T
        case CFBooleanGetTypeID(): return value as? T
        case let unknownCFTypeID:
            Logger.error { unknownCFTypeID }
            return nil
        }
    }

    /// The app's windows on the CURRENT Space (AX `kAXWindows`); does NOT return other-Space windows — use
    /// `windowByBruteForce` to resolve a specific other-Space wid.
    func windows() throws -> [AXUIElement] {
        let windows = try attributes([kAXWindowsAttribute]).windows
        if let windows,
           !windows.isEmpty {
            // bug in macOS: sometimes the OS returns multiple duplicate windows (e.g. Mail.app starting at login)
            let uniqueWindows = Array(Set(windows))
            if !uniqueWindows.isEmpty {
                return uniqueWindows
            }
        }
        return []
    }

    /// Wall-clock budget for any brute-force AX scan. The AXUIElementID space is `UInt64` and a long-lived app's
    /// windows can have high, sparse ids, so TIME — not an id ceiling — is the real bound; a monotonic
    /// `LightweightTimer` (checked every iteration) makes it reliable. Shared so every brute-force is capped the
    /// same way. These run on the isolated AX scan pool (`scan: true`), off the main thread.
    static let bruteForceBudgetMs: Double = 250

    /// Build an element per AXUIElementID for `pid` from a remote token (`_AXUIElementCreateWithRemoteToken` —
    /// the only way to reach windows absent from every CGS list: other-Space windows and inactive OS tabs) and
    /// hand it to `inspect`, until `inspect` returns true (it found what it wanted) or the budget elapses.
    /// IPC per id — off the main thread only. The token's id field is the only part rewritten per iteration.
    private static func bruteForceElements(_ pid: pid_t, _ inspect: (AXUIElement) -> Bool) {
        // 20 bytes: pid (4) + 0 (4) + magic 0x636f636f "coco" (4) + AXUIElementID (8); byte order matters.
        var remoteToken = Data(count: 20)
        remoteToken.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        remoteToken.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        remoteToken.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        let timer = LightweightTimer()
        for axUiElementId: AXUIElementID in 0..<AXUIElementID.max {
            remoteToken.replaceSubrange(12..<20, with: withUnsafeBytes(of: axUiElementId) { Data($0) })
            if let candidate = _AXUIElementCreateWithRemoteToken(remoteToken as CFData)?.takeRetainedValue(),
               inspect(candidate) {
                return
            }
            if timer.hasElapsed(milliseconds: bruteForceBudgetMs) { return }
        }
    }

    /// Resolve the AX element for ONE other-Space wid (there is no wid→element API). Returns the INSTANT a
    /// candidate's window id matches — matching by wid (rather than collecting every window and reading a subrole
    /// per id) early-exits at the target's index, reaching far higher ids within the budget. Subrole is judged
    /// downstream by the discriminator; here we only locate.
    static func windowByBruteForce(_ pid: pid_t, _ wid: CGWindowID) -> AXUIElement? {
        var found: AXUIElement?
        bruteForceElements(pid) { candidate in
            guard (try? candidate.cgWindowId()) == wid else { return false }
            found = candidate
            return true
        }
        return found
    }

    /// Find untracked standard windows whose title is one of `titles` — the only way to reach an INACTIVE OS
    /// TAB's window, which is absent from every CGS list (so normal discovery misses it) yet still reachable
    /// through the remote token. A tracked window's child elements resolve to its (excluded) wid, so they're
    /// skipped before the subrole read; only untracked wids pay for it. Returns each match's wid + element +
    /// title; stops once `titles.count` are found.
    static func untrackedWindowsByBruteForce(_ pid: pid_t, excluding: Set<CGWindowID>, matching titles: [String]) -> [(CGWindowID, AXUIElement, String)] {
        var seen = Set<CGWindowID>()
        var result = [(CGWindowID, AXUIElement, String)]()
        bruteForceElements(pid) { candidate in
            guard let wid = try? candidate.cgWindowId(), wid != 0, !excluding.contains(wid), !seen.contains(wid),
                  let a = try? candidate.attributes([kAXSubroleAttribute, kAXTitleAttribute]),
                  a.subrole == kAXStandardWindowSubrole, let title = a.title, titles.contains(title) else { return false }
            seen.insert(wid)
            result.append((wid, candidate, title))
            return result.count >= titles.count
        }
        return result
    }
}

/// Actions
extension AXUIElement {
    /// Raise the window within its app's stack. Returns the raw AXError instead of throwing, so callers can
    /// react to `.invalidUIElement` (a stale element: the app silently rebuilt the window's accessibility node,
    /// #5586) by re-resolving and retrying, rather than silently no-opping.
    @discardableResult
    func raiseWindow() -> AXError {
        return AXUIElementPerformAction(self, kAXRaiseAction as CFString)
    }

    func setAttribute(_ key: String, _ value: Any) throws {
        try throwIfNotSuccess(AXUIElementSetAttributeValue(self, key as CFString, value as CFTypeRef))
    }

    func performAction(_ action: String) throws {
        try throwIfNotSuccess(AXUIElementPerformAction(self, action as CFString))
    }

    /// Query the window's AXTabGroup child to detect OS-level tabs.
    /// Returns tab titles if the window has tabs (always ≥ 2), nil otherwise.
    /// `children` should come from the prior `.attributes([..., kAXChildrenAttribute])` call.
    static func tabGroupInfo(_ children: [AXUIElement]?) -> [String]? {
        guard let children else { return nil }
        for child in children {
            let a = try? child.attributes([kAXRoleAttribute, kAXChildrenAttribute])
            guard a?.role == "AXTabGroup", let tabChildren = a?.children else { continue }
            let titles = tabChildren.compactMap { tab -> String? in
                let t = try? tab.attributes([kAXSubroleAttribute, kAXTitleAttribute])
                guard t?.subrole == "AXTabButton" else { return nil }
                return t?.title ?? ""
            }
            return titles.count >= 2 ? titles : nil
        }
        return nil
    }
}

/// tests have shown that this ID has a range going from 0 to probably UInt.MAX
/// it starts at 0 for each app, and increments over time, for each new UI element
/// this means that long-lived apps (e.g. Finder) may have high IDs
/// we don't know how high it can go, and if it wraps around
typealias AXUIElementID = UInt64

enum AxError: Error {
    case runtimeError
}

struct AXAttributes {
    var title: String?
    var role: String?
    var subrole: String?
    var isMinimized: Bool?
    var isFullscreen: Bool?
    var isMain: Bool?
    var parent: AXUIElement?
    var children: [AXUIElement]?
    var focusedWindow: AXUIElement?
    var mainWindow: AXUIElement?
    var closeButton: AXUIElement?
    var appIsRunning: Bool?
    var url: URL?
    var statusLabel: String?
    var windows: [AXUIElement]?
    var position: CGPoint?
    var size: CGSize?
}
