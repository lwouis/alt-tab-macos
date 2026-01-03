import Cocoa
import ApplicationServices.HIServices.AXUIElement
import ApplicationServices.HIServices.AXValue
import ApplicationServices.HIServices.AXError
import ApplicationServices.HIServices.AXRoleConstants
import ApplicationServices.HIServices.AXAttributeConstants
import ApplicationServices.HIServices.AXActionConstants

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

    enum AXCallType: Int {
        case subscribeToAppNotification
        case subscribeToWindowNotification
        case subscribeToDockNotification
        case updateWindow
        case updateAppWindows
        case updateDockBadges
        case axEventEntrypoint
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
        Logger.info { "(pid:\(pid) wid:\(wid)) \(logFromContext(file, function, line, context, callType))" }
        retryAxCallUntilTimeout(file: file, function: function, line: line, context: context, after: .now() + humanPerceptionDelay, debounceType: debounceType, pid: pid, wid: wid, retriesQueue: true, startTimeInNanoseconds: startTimeInNanoseconds, callType: callType, block: block)
    }

    private static func logFromContext(_ file: String, _ function: String, _ line: Int, _ context: String, _ callType: AXCallType) -> String {
        return "Context: \((file as NSString).lastPathComponent):\(line) \(function) \(String(describing: callType)) \(context)"
    }

    func throwIfNotSuccess(_ result: AXError) throws -> Void {
        // .cannotComplete can happen if the app is unresponsive
        if result == .cannotComplete {
            throw AxError.runtimeError
        }
        // for success or other errors we don't throw
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

    func pid() throws -> pid_t {
        var pid = pid_t(0)
        try throwIfNotSuccess(AXUIElementGetPid(self, &pid))
        return pid
    }

    func attribute<T>(_ key: String, _ _: T.Type) throws -> T? {
        var attributeValue: AnyObject?
        try throwIfNotSuccess(AXUIElementCopyAttributeValue(self, key as CFString, &attributeValue))
        return attributeValue as? T
    }

    func windowAttributes() throws -> (String?, String?, String?, Bool, Bool)? {
        let attributes = [
            kAXTitleAttribute,
            kAXRoleAttribute,
            kAXSubroleAttribute,
            kAXMinimizedAttribute,
            kAXFullscreenAttribute,
        ]
        var values: CFArray?
        try throwIfNotSuccess(AXUIElementCopyMultipleAttributeValues(self, attributes as CFArray, [], &values))
        if let array = (values as? Array<Any>) {
            return (
                array[0] as? String,
                array[1] as? String,
                array[2] as? String,
                // if the value is nil, we return false. This avoid returning Bool?; simplifies things
                (array[3] as? Bool) ?? false,
                // if the value is nil, we return false. This avoid returning Bool?; simplifies things
                (array[4] as? Bool) ?? false
            )
        }
        return nil
    }

    private func value<T>(_ key: String, _ target: T, _ type: AXValueType) throws -> T? {
        if let a = try attribute(key, AXValue.self) {
            var value = target
            _ = withUnsafePointer(to: &value) {
                AXValueGetValue(a, type, UnsafeMutableRawPointer(mutating: $0))
            }
            return value
        }
        return nil
    }

    func title() throws -> String? {
        return try attribute(kAXTitleAttribute, String.self)
    }

    // periphery:ignore
    func parent() throws -> AXUIElement? {
        return try attribute(kAXParentAttribute, AXUIElement.self)
    }

    func children() throws -> [AXUIElement]? {
        return try attribute(kAXChildrenAttribute, [AXUIElement].self)
    }

    func isMinimized() throws -> Bool {
        // if the AX call doesn't return, we return false. This avoid returning Bool?; simplifies things
        return try attribute(kAXMinimizedAttribute, Bool.self) == true
    }

    func isFullscreen() throws -> Bool {
        // if the AX call doesn't return, we return false. This avoid returning Bool?; simplifies things
        return try attribute(kAXFullscreenAttribute, Bool.self) == true
    }

    func focusedWindow() throws -> AXUIElement? {
        return try attribute(kAXFocusedWindowAttribute, AXUIElement.self)
    }

    func role() throws -> String? {
        return try attribute(kAXRoleAttribute, String.self)
    }

    func subrole() throws -> String? {
        return try attribute(kAXSubroleAttribute, String.self)
    }

    func closeButton() throws -> AXUIElement? {
        return try attribute(kAXCloseButtonAttribute, AXUIElement.self)
    }

    func appIsRunning() throws -> Bool? {
        return try attribute(kAXIsApplicationRunningAttribute, Bool.self)
    }

    /// doesn't return windows on other Spaces
    /// use windowsByBruteForce if you want those
    func windows() throws -> [AXUIElement] {
        let windows = try attribute(kAXWindowsAttribute, [AXUIElement].self)
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

    func position() throws -> CGPoint? {
        return try value(kAXPositionAttribute, CGPoint.zero, .cgPoint)
    }

    func size() throws -> CGSize? {
        return try value(kAXSizeAttribute, CGSize.zero, .cgSize)
    }

    /// we combine both the normal approach and brute-force to get all possible windows
    /// with only normal approach: we miss other-Spaces windows
    /// with only brute-force approach: we miss windows when the app launches (e.g. launch Note.app: first window is not found by brute-force)
    func allWindows(_ pid: pid_t) throws -> [AXUIElement] {
        let aWindows = try windows()
        let bWindows = AXUIElement.windowsByBruteForce(pid)
        return Array(Set(aWindows + bWindows))
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
               let subrole = try? axUiElement.subrole(),
               [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole) {
                axWindows.append(axUiElement)
            }
            if timer.hasElapsed(milliseconds: 100) {
                return axWindows
            }
        }
        return axWindows
    }

    static func isActualWindow(_ app: Application, _ wid: CGWindowID, _ level: CGWindowLevel, _ title: String?, _ subrole: String?, _ role: String?, _ size: CGSize?) -> Bool {
        // Some non-windows have title: nil (e.g. some OS elements)
        // Some non-windows have subrole: nil (e.g. some OS elements), "AXUnknown" (e.g. Bartender), "AXSystemDialog" (e.g. Intellij tooltips)
        // Minimized windows or windows of a hidden app have subrole "AXDialog"
        // Activity Monitor main window subrole is "AXDialog" for a brief moment at launch; it then becomes "AXStandardWindow"
        // Some non-windows have cgWindowId == 0 (e.g. windows of apps starting at login with the checkbox "Hidden" checked)
        return wid != 0
            // Finder's file copy dialogs are wide but < 100 height (see https://github.com/lwouis/alt-tab-macos/issues/1466)
            // Sonoma introduced a bug: a caps-lock & language indicators shows as a small window.
            // We try to hide it by filtering out tiny windows
            && size != nil && (size!.width > 100 && size!.height > 50) && (
            (
                books(app) ||
                    keynote(app) ||
                    preview(app, subrole) ||
                    iina(app) ||
                    openFlStudio(app, title) ||
                    crossoverWindow(app, role, subrole, level) ||
                    isAlwaysOnTopScrcpy(app, level, role, subrole)
            ) || (
                 (
                    [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole) ||
                        openBoard(app) ||
                        adobeAudition(app, subrole) ||
                        adobeAfterEffects(app, subrole) ||
                        steam(app, title, role) ||
                        worldOfWarcraft(app, role) ||
                        battleNetBootstrapper(app, role) ||
                        firefox(app, role, size) ||
                        vlcFullscreenVideo(app, role) ||
                        sanGuoShaAirWD(app) ||
                        dvdFab(app) ||
                        drBetotte(app) ||
                        androidEmulator(app, title) ||
                        autocad(app, subrole)
                ) && (
                    mustHaveIfJetbrainApp(app, title, subrole, size!) &&
                        mustHaveIfSteam(app, title, role) &&
                        mustHaveIfFusion360(app, title, role) &&
                        mustHaveIfColorSlurp(app, subrole)
                )
            )
        )
    }

    private static func mustHaveIfFusion360(_ app: Application, _ title: String?, _ role: String?) -> Bool {
        // filter out Autodesk Fusion side panels "Browser" and "Comments" with subrole AXDialog but with no title
        return app.bundleIdentifier != "com.autodesk.fusion360" || (title != nil && title != "")
    }

    private static func mustHaveIfJetbrainApp(_ app: Application, _ title: String?, _ subrole: String?, _ size: NSSize) -> Bool {
        // jetbrain apps sometimes generate non-windows that pass all checks in isActualWindow
        // they have no title, so we can filter them out based on that
        // we also hide windows too small
        return app.bundleIdentifier?.range(of: "^com\\.(jetbrains\\.|google\\.android\\.studio).*?$", options: .regularExpression) == nil || (
            (subrole == kAXStandardWindowSubrole || (title != nil && title != "")) &&
                size.width > 100 && size.height > 100
        )
    }

    private static func mustHaveIfColorSlurp(_ app: Application, _ subrole: String?) -> Bool {
        return app.bundleIdentifier != "com.IdeaPunch.ColorSlurp" || subrole == kAXStandardWindowSubrole
    }

    private static func iina(_ app: Application) -> Bool {
        // IINA.app can have videos float (level == 2 instead of 0)
        // there is also complex animations during which we may or may not consider the window not a window
        return app.bundleIdentifier == "com.colliderli.iina"
    }

    private static func keynote(_ app: Application) -> Bool {
        // apple Keynote has a fake fullscreen window when in presentation mode
        // it covers the screen with a AXUnknown window instead of using standard fullscreen mode
        return app.bundleIdentifier == "com.apple.iWork.Keynote"
    }

    private static func preview(_ app: Application, _ subrole: String?) -> Bool {
        // when opening multiple documents at once with apple Preview,
        // one of the window will have level == 1 for some reason
        return app.bundleIdentifier == "com.apple.Preview" && [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole)
    }

    private static func openFlStudio(_ app: Application, _ title: String?) -> Bool {
        // OpenBoard is a ported app which doesn't use standard macOS windows
        return app.bundleIdentifier == "com.image-line.flstudio" && (title != nil && title != "")
    }

    private static func openBoard(_ app: Application) -> Bool {
        // OpenBoard is a ported app which doesn't use standard macOS windows
        return app.bundleIdentifier == "org.oe-f.OpenBoard"
    }

    private static func adobeAudition(_ app: Application, _ subrole: String?) -> Bool {
        return app.bundleIdentifier == "com.adobe.Audition" && subrole == kAXFloatingWindowSubrole
    }

    private static func adobeAfterEffects(_ app: Application, _ subrole: String?) -> Bool {
        return app.bundleIdentifier == "com.adobe.AfterEffects" && subrole == kAXFloatingWindowSubrole
    }

    private static func books(_ app: Application) -> Bool {
        // Books.app has animations on window creation. This means windows are originally created with subrole == AXUnknown or isOnNormalLevel == false
        return app.bundleIdentifier == "com.apple.iBooksX"
    }

    private static func worldOfWarcraft(_ app: Application, _ role: String?) -> Bool {
        return app.bundleIdentifier == "com.blizzard.worldofwarcraft" && role == kAXWindowRole
    }

    private static func battleNetBootstrapper(_ app: Application, _ role: String?) -> Bool {
        // Battlenet bootstrapper windows have subrole == AXUnknown
        return app.bundleIdentifier == "net.battle.bootstrapper" && role == kAXWindowRole
    }

    private static func drBetotte(_ app: Application) -> Bool {
        return app.bundleIdentifier == "com.ssworks.drbetotte"
    }

    private static func dvdFab(_ app: Application) -> Bool {
        return app.bundleIdentifier == "com.goland.dvdfab.macos"
    }

    private static func sanGuoShaAirWD(_ app: Application) -> Bool {
        return app.bundleIdentifier == "SanGuoShaAirWD"
    }

    private static func steam(_ app: Application, _ title: String?, _ role: String?) -> Bool {
        // All Steam windows have subrole == AXUnknown
        // some dropdown menus are not desirable; they have title == "", or sometimes role == nil when switching between menus quickly
        return app.bundleIdentifier == "com.valvesoftware.steam" && (title != nil && title != "" && role != nil)
    }

    private static func mustHaveIfSteam(_ app: Application, _ title: String?, _ role: String?) -> Bool {
        // All Steam windows have subrole == AXUnknown
        // some dropdown menus are not desirable; they have title == "", or sometimes role == nil when switching between menus quickly
        return app.bundleIdentifier != "com.valvesoftware.steam" || (title != nil && title != "" && role != nil)
    }

    private static func firefox(_ app: Application, _ role: String?, _ size: CGSize?) -> Bool {
        // Firefox fullscreen video have subrole == AXUnknown if fullscreen'ed when the base window is not fullscreen
        // Firefox tooltips are implemented as windows with subrole == AXUnknown
        return (app.bundleIdentifier?.hasPrefix("org.mozilla.firefox") ?? false) && role == kAXWindowRole && size?.height != nil && size!.height > 400
    }

    private static func vlcFullscreenVideo(_ app: Application, _ role: String?) -> Bool {
        // VLC fullscreen video have subrole == AXUnknown if fullscreen'ed
        return (app.bundleIdentifier?.hasPrefix("org.videolan.vlc") ?? false) && role == kAXWindowRole
    }

    private static func androidEmulator(_ app: Application, _ title: String?) -> Bool {
        // android emulator small vertical menu is a "window" with empty title; we exclude it
        return title != "" && Applications.isAndroidEmulator(app.bundleIdentifier, app.pid)
    }

    private static func crossoverWindow(_ app: Application, _ role: String?, _ subrole: String?, _ level: CGWindowLevel) -> Bool {
        return app.bundleIdentifier == nil && role == kAXWindowRole && subrole == kAXUnknownSubrole && level == CGWindow.normalLevel
            && (app.localizedName == "wine64-preloader" || app.executableURL?.absoluteString.contains("/winetemp-") ?? false)
    }

    private static func isAlwaysOnTopScrcpy(_ app: Application, _ level: CGWindowLevel, _ role: String?, _ subrole: String?) -> Bool {
        // scrcpy presents as a floating window when "Always on top" is enabled, so it doesn't get picked up normally.
        // It also doesn't have a bundle ID, so we need to match using the localized name, which should always be the same.
        return app.localizedName == "scrcpy" && level == CGWindow.floatingWindow && role == kAXWindowRole && subrole == kAXStandardWindowSubrole
    }

    private static func autocad(_ app: Application, _ subrole: String?) -> Bool {
        // AutoCAD uses the undocumented "AXDocumentWindow" subrole
        return (app.bundleIdentifier?.hasPrefix("com.autodesk.AutoCAD") ?? false) && subrole == kAXDocumentWindowSubrole
    }

    func focusWindow() throws {
        try performAction(kAXRaiseAction)
    }

    func setAttribute(_ key: String, _ value: Any) throws {
        try throwIfNotSuccess(AXUIElementSetAttributeValue(self, key as CFString, value as CFTypeRef))
    }

    func performAction(_ action: String) throws {
        try throwIfNotSuccess(AXUIElementPerformAction(self, action as CFString))
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
}

enum AxError: Error {
    case runtimeError
}

/// tests have shown that this ID has a range going from 0 to probably UInt.MAX
/// it starts at 0 for each app, and increments over time, for each new UI element
/// this means that long-lived apps (e.g. Finder) may have high IDs
/// we don't know how high it can go, and if it wraps around
typealias AXUIElementID = UInt64

enum DebounceType: Int {
    case windowResizedOrMoved
    case windowTitleChanged
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
