import Cocoa
import ApplicationServices.HIServices.AXUIElement
import ApplicationServices.HIServices.AXValue
import ApplicationServices.HIServices.AXError
import ApplicationServices.HIServices.AXRoleConstants
import ApplicationServices.HIServices.AXAttributeConstants
import ApplicationServices.HIServices.AXActionConstants

/// common, subscriptions, concurrency
extension AXUIElement {
    // default timeout for AX calls is 6s
    // we reduce to 1s to avoid AX calls blocking threads, thus too many threads getting created to make the next AX calls
    private static let globalMessagingTimeoutInSeconds = Float(1)
    // if an app times out our AX calls, we retry for 6s then give up
    private static let axCallsRetriesQueueTimeoutInSeconds = Float(6)
    // once an app is unresponsive, let's ignore other AX calls for it to avoid congestion
    private static var axCallsRetriesQueueUnresponsiveAppsMap = ConcurrentMap<String, UInt64>()
    // some events like window resizing trigger in quick succession. We debounce those
    private static var eventsDebounceMap = ConcurrentMap<String, DispatchWorkItem>()

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

    /// if the window server is busy, it may not reply to AX calls. We retry right before the call times-out and returns a bogus value
    static func retryAxCallUntilTimeout(file: String = #file, function: String = #function, line: Int = #line, context: String = "", after: DispatchTime? = nil, debounceType: DebounceType? = nil, pid: pid_t? = nil, wid: CGWindowID? = nil, retriesQueue: Bool = false, startTimeInNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds, callType: AXCallType, block: @escaping () throws -> Void) {
        let closure = { retryAxCallUntilTimeout_(file: file, function: function, line: line, context: context, after: after, debounceType: debounceType, pid: pid, wid: wid, retriesQueue: retriesQueue, startTimeInNanoseconds: startTimeInNanoseconds, callType: callType, block: block) }
        let queue = callType == .updateAppWindows ? BackgroundWork.axCallsManualDiscoveryQueue : (retriesQueue ? BackgroundWork.axCallsRetriesQueue : BackgroundWork.axCallsFirstAttemptQueue)
        if let after {
            queue!.addOperationAfter(deadline: after, block: closure)
        } else if let debounceType, let wid {
            let debounceMapKey = "\(debounceType.rawValue)\(wid)"
            let workItem = DispatchWorkItem {
                closure()
                eventsDebounceMap.withLock { $0[debounceMapKey] = nil }
            }
            eventsDebounceMap.withLock {
                $0[debounceMapKey]?.cancel()
                $0[debounceMapKey] = workItem
            }
            queue!.addOperationAfter(deadline: .now() + humanPerceptionDelay) {
                workItem.perform()
            }
        } else {
            queue!.addOperation(closure)
        }
    }

    private static func retryAxCallUntilTimeout_(file: String, function: String, line: Int, context: String, after: DispatchTime?, debounceType: DebounceType?, pid: pid_t?, wid: CGWindowID?, retriesQueue: Bool, startTimeInNanoseconds: UInt64, callType: AXCallType, block: @escaping () throws -> Void) {
        // attempt the AX call
        if (try? block()) != nil {
            return
        }
        // do we already have ongoing retries for this pid? The app is likely unresponsive
        // if their are common updates, we avoid congestion by only retrying the latest update
        if let pid, callType == .updateWindow || callType == .updateAppWindows {
            let unresponsiveAppsMapKey = "\(callType.rawValue)\(pid)"
            let time = axCallsRetriesQueueUnresponsiveAppsMap.withLock { $0[unresponsiveAppsMapKey] }
            if let time {
                if startTimeInNanoseconds > time {
                    // new most recent call; replace and retry
                    axCallsRetriesQueueUnresponsiveAppsMap.withLock { $0[unresponsiveAppsMapKey] = startTimeInNanoseconds }
                } else if startTimeInNanoseconds == time {
                    // most recent call; retry
                } else {
                    // old call which has been replaced; ignore
                    return
                }
            } else {
                // first call; set and retry
                axCallsRetriesQueueUnresponsiveAppsMap.withLock { $0[unresponsiveAppsMapKey] = startTimeInNanoseconds }
            }
        }
        // should we give up?
        let timePassedInSeconds = Float(DispatchTime.now().uptimeNanoseconds - startTimeInNanoseconds) / 1_000_000_000
        if timePassedInSeconds >= axCallsRetriesQueueTimeoutInSeconds {
            Logger.info { "AX call failed for more than \(Int(axCallsRetriesQueueTimeoutInSeconds))s. Giving up on it. \(logFromContext(file, function, line, context, callType))" }
            if let pid, callType == .updateWindow || callType == .updateAppWindows {
                let unresponsiveAppsMapKey = "\(callType.rawValue)\(pid)"
                axCallsRetriesQueueUnresponsiveAppsMap.withLock { $0.removeValue(forKey: unresponsiveAppsMapKey) }
            }
            return
        }
        // retry
        Logger.debug { "(pid:\(pid) wid:\(wid)) \(logFromContext(file, function, line, context, callType))" }
        retryAxCallUntilTimeout(file: file, function: function, line: line, context: context, after: .now() + humanPerceptionDelay, debounceType: debounceType, pid: pid, wid: wid, retriesQueue: true, startTimeInNanoseconds: startTimeInNanoseconds, callType: callType, block: block)
    }

    private static func logFromContext(_ file: String, _ function: String, _ line: Int, _ context: String, _ callType: AXCallType) -> String {
        return "Context: \((file as NSString).lastPathComponent):\(line) \(function) \(String(describing: callType)) \(context)"
    }

    @discardableResult
    func subscribeToNotification(_ axObserver: AXObserver, _ notification: String, _ callback: (() -> Void)? = nil) throws -> Bool {
        let result = AXObserverAddNotification(axObserver, self, notification as CFString, nil)
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

    enum AXCallType: Int {
        case subscribeToAppNotification
        case subscribeToWindowNotification
        case subscribeToDockNotification
        case updateWindow
        case updateAppWindows
        case updateDockBadges
        case axEventEntrypoint
    }

    final class ConcurrentMap<K: Hashable, V> {
        private var map = [K: V]()
        private let lock = NSLock()

        @discardableResult
        func withLock<T>(_ block: (inout [K: V]) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return block(&map)
        }
    }
}

/// Attributes
extension AXUIElement {
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

    func pid() throws -> pid_t {
        var pid = pid_t(0)
        try throwIfNotSuccess(AXUIElementGetPid(self, &pid))
        return pid
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

    /// we combine both the normal approach and brute-force to get all possible windows
    /// with only normal approach: we miss other-Spaces windows
    /// with only brute-force approach: we miss windows when the app launches (e.g. launch Note.app: first window is not found by brute-force)
    func allWindows(_ pid: pid_t) throws -> [AXUIElement] {
        let aWindows = try windows()
        let bWindows = Self.windowsByBruteForce(pid)
        return Array(Set(aWindows + bWindows))
    }

    /// doesn't return windows on other Spaces
    /// use windowsByBruteForce if you want those
    private func windows() throws -> [AXUIElement] {
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

    /// brute-force getting the windows of a process by iterating over AXUIElementID one by one
    private static func windowsByBruteForce(_ pid: pid_t) -> [AXUIElement] {
        // we use this to call _AXUIElementCreateWithRemoteToken; we reuse the object for performance
        // tests showed that this remoteToken is 20 bytes: 4 + 4 + 4 + 8; the order of bytes matters
        var remoteToken = Data(count: 20)
        remoteToken.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        remoteToken.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        remoteToken.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        var axWindows = [AXUIElement]()
        // we iterate to 1000 as a tradeoff between performance, and missing windows of long-lived processes
        // different apps can take widely different time for this to complete. We stop iterating if we time out
        let timer = LightweightTimer()
        for axUiElementId: AXUIElementID in 0..<1000 {
            remoteToken.replaceSubrange(12..<20, with: withUnsafeBytes(of: axUiElementId) { Data($0) })
            if let axUiElement = _AXUIElementCreateWithRemoteToken(remoteToken as CFData)?.takeRetainedValue(),
               let subrole = try? axUiElement.attributes([kAXSubroleAttribute]).subrole,
               [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole) {
                axWindows.append(axUiElement)
            }
            if timer.hasElapsed(milliseconds: 100) {
                return axWindows
            }
        }
        return axWindows
    }
}

/// Actions
extension AXUIElement {
    func focusWindow() throws {
        try performAction(kAXRaiseAction)
    }

    func setAttribute(_ key: String, _ value: Any) throws {
        try throwIfNotSuccess(AXUIElementSetAttributeValue(self, key as CFString, value as CFTypeRef))
    }

    func performAction(_ action: String) throws {
        try throwIfNotSuccess(AXUIElementPerformAction(self, action as CFString))
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

enum DebounceType: Int {
    case windowResizedOrMoved
    case windowTitleChanged
}
