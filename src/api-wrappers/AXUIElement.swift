import Cocoa

extension AXUIElement {
    static let normalLevel = CGWindowLevelForKey(.normalWindow)

    func cgWindowId() -> CGWindowID {
        var id = CGWindowID(0)
        _AXUIElementGetWindow(self, &id)
        return id
    }

    func pid() -> pid_t {
        var pid = pid_t(0)
        AXUIElementGetPid(self, &pid)
        return pid
    }

    func isActualWindow(_ bundleIdentifier: String?) -> Bool {
        // Some non-windows have title: nil (e.g. some OS elements)
        // Some non-windows have subrole: nil (e.g. some OS elements), "AXUnknown" (e.g. Bartender), "AXSystemDialog" (e.g. Intellij tooltips)
        // Minimized windows or windows of a hidden app have subrole "AXDialog"
        // Activity Monitor main window subrole is "AXDialog" for a brief moment at launch; it then becomes "AXStandardWindow"
        // CGWindowLevel == .normalWindow helps filter out iStats Pro and other top-level pop-overs
        let subrole_ = subrole()
        return subrole_ != nil &&
            (["AXStandardWindow", "AXDialog"].contains(subrole_) ||
                // All Steam windows have subrole = AXUnknown
                // some dropdown menus are not desirable; they have title == "", or sometimes role == nil when switching between menus quickly
                (bundleIdentifier == "com.valvesoftware.steam" && title() != "" && role() != nil)) &&
            isOnNormalLevel()
    }

    func isOnNormalLevel() -> Bool {
        let level: CGWindowLevel = cgWindowId().level()
        return level == AXUIElement.normalLevel
    }

    func position() -> CGPoint? {
        return value(kAXPositionAttribute, CGPoint.zero, .cgPoint)
    }

    func title() -> String? {
        return attribute(kAXTitleAttribute, String.self)
    }

    func windows() -> [AXUIElement]? {
        return attribute(kAXWindowsAttribute, [AXUIElement].self)
    }

    func isTabbed(_ window: AXUIElement) -> Bool {
        return windows()?.first { $0 == window } == nil
    }

    func isMinimized() -> Bool {
        return attribute(kAXMinimizedAttribute, Bool.self) == true
    }

    func isHidden() -> Bool {
        return attribute(kAXHiddenAttribute, Bool.self) == true
    }

    func isFullScreen() -> Bool {
        return attribute(kAXFullscreenAttribute, Bool.self) == true
    }

    func focusedWindow() -> AXUIElement? {
        return attribute(kAXFocusedWindowAttribute, AXUIElement.self)
    }

    func role() -> String? {
        return attribute(kAXRoleAttribute, String.self)
    }

    func subrole() -> String? {
        return attribute(kAXSubroleAttribute, String.self)
    }

    func closeButton() -> AXUIElement {
        return attribute(kAXCloseButtonAttribute, AXUIElement.self)!
    }

    func closeWindow() {
        if isFullScreen() {
            AXUIElementSetAttributeValue(self, kAXFullscreenAttribute as CFString, false as CFTypeRef)
        }
        AXUIElementPerformAction(closeButton(), kAXPressAction as CFString)
    }

    func minDeminWindow() {
        if isFullScreen() {
            AXUIElementSetAttributeValue(self, kAXFullscreenAttribute as CFString, false as CFTypeRef)
            // minimizing is ignored if sent immediatly; we wait for the de-fullscreen animation to be over
            DispatchQueues.accessibilityCommands.asyncAfter(deadline: .now() + .milliseconds(1000)) { [weak self] in
                guard let self = self else { return }
                AXUIElementSetAttributeValue(self, kAXMinimizedAttribute as CFString, true as CFTypeRef)
            }
        } else {
            AXUIElementSetAttributeValue(self, kAXMinimizedAttribute as CFString, !isMinimized() as CFTypeRef)
        }
    }

    func focusWindow() {
        AXUIElementPerformAction(self, kAXRaiseAction as CFString)
    }

    func subscribeWithRetry(_ axObserver: AXObserver, _ notification: String, _ pointer: UnsafeMutableRawPointer?, _ callback: (() -> Void)? = nil, _ runningApplication: NSRunningApplication? = nil, _ wid: CGWindowID? = nil, _ startTime: DispatchTime = DispatchTime.now()) {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] () -> () in
            guard let self = self else { return }
            // some apps return .isFinishedLaunching = true but will return .cannotComplete when we try to subscribe to them
            // this happens for example when apps launch and have heavy loading to do (e.g. Gimp).
            // we have no way to know if they are one day going to be letting us subscribe, so we timeout after 2 min
            let timePassedInSeconds = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
            if timePassedInSeconds > 120 { return }
            let result = AXObserverAddNotification(axObserver, self, notification as CFString, pointer)
            self.handleSubscriptionAttempt(result, axObserver, notification, pointer, callback, runningApplication, wid, startTime)
        }
    }

    func handleSubscriptionAttempt(_ result: AXError, _ axObserver: AXObserver, _ notification: String, _ pointer: UnsafeMutableRawPointer?, _ callback: (() -> Void)?, _ runningApplication: NSRunningApplication?, _ wid: CGWindowID?, _ startTime: DispatchTime) -> Void {
        if result == .success || result == .notificationAlreadyRegistered {
            DispatchQueue.main.async { [weak self] () -> () in
                callback?()
            }
        } else if result != .notificationUnsupported && result != .notImplemented {
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + .milliseconds(10), execute: { [weak self] in
                self?.subscribeWithRetry(axObserver, notification, pointer, callback, runningApplication, wid, startTime)
            })
        }
    }

    private func attribute<T>(_ key: String, _ type: T.Type) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, key as CFString, &value)
        if result == .success, let value = value as? T {
            return value
        }
        return nil
    }

    private func value<T>(_ key: String, _ target: T, _ type: AXValueType) -> T? {
        if let a = attribute(key, AXValue.self) {
            var value = target
            AXValueGetValue(a, type, &value)
            return value
        }
        return nil
    }
}
