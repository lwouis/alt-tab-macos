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

    func isActualWindow() -> Bool {
        // TODO: TotalFinder and XtraFinder double-window hacks (see #84)
        // Some non-windows have title: nil (e.g. some OS elements)
        // Some non-windows have subrole: nil (e.g. some OS elements), "AXUnknown" (e.g. Bartender), "AXSystemDialog" (e.g. Intellij tooltips)
        // Minimized windows or windows of a hidden app have subrole "AXDialog"
        // Activity Monitor main window subrole is "AXDialog" for a brief moment at launch; it then becomes "AXStandardWindow"
        // CGWindowLevel == .normalWindow helps filter out iStats Pro and other top-level pop-overs
        return ["AXStandardWindow", "AXDialog"].contains(subrole()) && isOnNormalLevel()
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

    func isMinimized() -> Bool {
        return attribute(kAXMinimizedAttribute, Bool.self) == true
    }

    func isHidden() -> Bool {
        return attribute(kAXHiddenAttribute, Bool.self) == true
    }

    func focusedWindow() -> AXUIElement? {
        return attribute(kAXFocusedWindowAttribute, AXUIElement.self)
    }

    func subrole() -> String? {
        return attribute(kAXSubroleAttribute, String.self)
    }

    func subscribeWithRetry(_ axObserver: AXObserver, _ notification: String, _ pointer: UnsafeMutableRawPointer?, _ callback: (() -> Void)? = nil, _ runningApplication: NSRunningApplication? = nil, _ wid: CGWindowID? = nil, _ attemptsCount: Int = 0) {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] () -> () in
            guard let self = self else { return }
            DispatchQueue.main.async { () -> () in
                if let runningApplication = runningApplication, Applications.appsInSubscriptionRetryLoop.first(where: { $0 == String(runningApplication.processIdentifier) + String(notification) }) == nil { return }
                if let wid = wid, Windows.windowsInSubscriptionRetryLoop.first(where: { $0 == String(wid) + String(notification) }) == nil { return }
            }
            let result = AXObserverAddNotification(axObserver, self, notification as CFString, pointer)
            self.handleSubscriptionAttempt(result, axObserver, notification, pointer, callback, runningApplication, wid, attemptsCount)
        }
    }

    func handleSubscriptionAttempt(_ result: AXError, _ axObserver: AXObserver, _ notification: String, _ pointer: UnsafeMutableRawPointer?, _ callback: (() -> Void)?, _ runningApplication: NSRunningApplication?, _ wid: CGWindowID?, _ attemptsCount: Int) -> Void {
        if result == .success || result == .notificationAlreadyRegistered {
            DispatchQueue.main.async { [weak self] () -> () in
                callback?()
                self?.stopRetries(runningApplication, wid, notification)
            }
        } else if result == .notificationUnsupported || result == .notImplemented {
            DispatchQueue.main.async { [weak self] () -> () in
                self?.stopRetries(runningApplication, wid, notification)
            }
        } else {
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + .milliseconds(10), execute: { [weak self] in
                self?.subscribeWithRetry(axObserver, notification, pointer, callback, runningApplication, wid, attemptsCount + 1)
            })
        }
    }

    func stopRetries(_ runningApplication: NSRunningApplication?, _ wid: CGWindowID?, _ notification: String) {
        if let runningApplication = runningApplication {
            Application.stopSubscriptionRetries(notification, runningApplication)
        }
        if let wid = wid {
            Window.stopSubscriptionRetries(notification, wid)
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
