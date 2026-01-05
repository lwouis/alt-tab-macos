import Cocoa
import ApplicationServices.HIServices.AXUIElement
import ApplicationServices.HIServices.AXNotificationConstants

class AccessibilityEvents {
    static let axObserverCallback: AXObserverCallback = { _, element, notificationName, _ in
        let type = notificationName as String
        Logger.debug { type }
        AXUIElement.retryAxCallUntilTimeout(context: "(type:\(type)", callType: .axEventEntrypoint) { try handleEvent(type, element) }
    }

    static func updateWindowSizeAndPositionAndFullscreen(_ element: AXUIElement, _ wid: CGWindowID, _ window: Window?) throws {
        if let (title, _, _, isMinimized, isFullscreen) = try element.windowAttributes() {
            let size = try element.size()
            let position = try element.position()
            DispatchQueue.main.async { [weak window] in
                if let window = (window != nil ? window : (Windows.list.first { $0.isEqualRobust(element, wid) })) {
                    window.title = window.bestEffortTitle(title)
                    window.size = size
                    window.position = position
                    window.isMinimized = isMinimized
                    if window.isFullscreen != isFullscreen {
                        window.isFullscreen = isFullscreen
                        App.app.checkIfShortcutsShouldBeDisabled(window, nil)
                    }
                    App.app.refreshOpenUi([window], .refreshUiAfterExternalEvent)
                }
            }
        }
    }

    private static func handleEvent(_ type: String, _ element: AXUIElement) throws {
        // events are handled concurrently, thus we check that the app is still running
        let pid = try element.pid()
        if try pid != ProcessInfo.processInfo.processIdentifier || (element.subrole() != kAXUnknownSubrole) {
            Logger.info { "\(type) (pid:\(pid) title:\(try? element.title()))" }
            switch type {
            case kAXApplicationActivatedNotification: try applicationActivated(element, pid)
            case kAXApplicationHiddenNotification,
                 kAXApplicationShownNotification: try applicationHiddenOrShown(pid, type)
            case kAXWindowCreatedNotification: try windowCreated(element, pid)
            case kAXMainWindowChangedNotification,
                 kAXFocusedWindowChangedNotification: try focusedWindowChanged(element, pid)
            case kAXUIElementDestroyedNotification: try windowDestroyed(element, pid)
            case kAXWindowMiniaturizedNotification,
                 kAXWindowDeminiaturizedNotification: try windowMiniaturizedOrDeminiaturized(element, type)
            case kAXTitleChangedNotification: try windowTitleChanged(element, pid)
            case kAXWindowResizedNotification,
                 kAXWindowMovedNotification: try windowResizedOrMoved(element, pid)
            default: return
            }
        }
    }

    private static func applicationActivated(_ element: AXUIElement, _ pid: pid_t) throws {
        let initialFocusedWindow = try element.focusedWindow()
        let initialWid = try initialFocusedWindow?.cgWindowId()

        func applyFocusBump(_ axWindow: AXUIElement?, _ wid: CGWindowID?) {
            DispatchQueue.main.async {
                if let app = Applications.find(pid) {
                    if app.hasBeenActiveOnce != true {
                        app.hasBeenActiveOnce = true
                    }
                    app.isHidden = false

                    var window: Window? = nil
                    if let axWindow, let wid {
                        // Try to update recency immediately if we can identify the window
                        window = Windows.updateLastFocus(axWindow, wid)?.first

                        // If the window isn't tracked yet, mirror the focusedWindowChanged fallback to create it
                        if window == nil {
                            AXUIElement.retryAxCallUntilTimeout(context: "activation wid:\(wid) pid:\(pid)", pid: pid, callType: .updateWindow) {
                                if let (title, role, subrole, isMinimized, isFullscreen) = try axWindow.windowAttributes() {
                                    let position = try axWindow.position()
                                    let size = try axWindow.size()
                                    let level = wid.level()
                                    DispatchQueue.main.async {
                                        if let app2 = Applications.find(pid),
                                           (!Windows.list.contains { $0.isEqualRobust(axWindow, wid) }),
                                           AXUIElement.isActualWindow(app2, wid, level, title, subrole, role, size) {
                                            let w = Window(axWindow, app2, wid, title, isFullscreen, isMinimized, position, size)
                                            Windows.appendAndUpdateFocus(w)
                                            App.app.refreshOpenUi([w], .refreshUiAfterExternalEvent)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    app.focusedWindow = window
                    App.app.checkIfShortcutsShouldBeDisabled(window, app.runningApplication)
                    App.app.refreshOpenUi(window != nil ? [window!] : [], .refreshUiAfterExternalEvent)
                }
            }
        }

        // First attempt: bump using whatever focused window we can get immediately
        applyFocusBump(initialFocusedWindow, initialWid)

        // If activation happened before a stable focused window exists, retry shortly after
        if initialFocusedWindow == nil || initialWid == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) {
                AXUIElement.retryAxCallUntilTimeout(context: "activationRetry pid:\(pid)", pid: pid, callType: .updateWindow) {
                    let retryFocused = try element.focusedWindow()
                    let retryWid = try retryFocused?.cgWindowId()
                    applyFocusBump(retryFocused, retryWid)
                }
            }
        }
    }

    private static func applicationHiddenOrShown(_ pid: pid_t, _ type: String) throws {
        DispatchQueue.main.async {
            if let app = Applications.find(pid) {
                app.isHidden = type == kAXApplicationHiddenNotification
                let windows = Windows.list.filter {
                    // for AXUIElement of apps, CFEqual or == don't work; looks like a Cocoa bug
                    return $0.application.pid == pid
                }
                // if we process the "shown" event too fast, the window won't be listed by CGSCopyWindowsWithOptionsAndTags
                // it will thus be detected as isTabbed. We add a delay to work around this scenario
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
                    App.app.refreshOpenUi(windows, .refreshUiAfterExternalEvent)
                }
            }
        }
    }

    private static func windowCreated(_ element: AXUIElement, _ pid: pid_t) throws {
        let wid = try element.cgWindowId()
        DispatchQueue.main.async {
            guard let app = Applications.find(pid) else { return }
            app.isHidden = false
            // if the window is shown by alt-tab, we mark it as focused for this app
            // this avoids issues with dialogs, quicklook, etc (see scenarios from #1044 and #2003)
            if let w = (Windows.list.first { $0.isEqualRobust(element, wid) }) {
                app.focusedWindow = w
            }
            Windows.updateLastFocusDebounced(element, wid, pid: pid, debounce: 60, requireFrontmost: false)
            
            // Also schedule a fallback to create the window if it doesn't exist yet after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) {
                // If the window still isn't tracked, try to create it
                if (Windows.list.first { $0.isEqualRobust(element, wid) }) == nil {
                    AXUIElement.retryAxCallUntilTimeout(context: "wid:\(wid) pid:\(pid)", pid: pid, callType: .updateWindow) {
                        if let (title, role, subrole, isMinimized, isFullscreen) = try element.windowAttributes() {
                            let position = try element.position()
                            let size = try element.size()
                            let level = wid.level()
                            DispatchQueue.main.async {
                                if let app = Applications.find(pid),
                                   (!Windows.list.contains { $0.isEqualRobust(element, wid) }),
                                   AXUIElement.isActualWindow(app, wid, level, title, subrole, role, size) {
                                    let window = Window(element, app, wid, title, isFullscreen, isMinimized, position, size)
                                    Windows.appendAndUpdateFocus(window)
                                    App.app.refreshOpenUi([window], .refreshUiAfterExternalEvent)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func windowDestroyed(_ element: AXUIElement, _ pid: pid_t) throws {
        let wid = try element.cgWindowId()
        DispatchQueue.main.async {
            if let index = (Windows.list.firstIndex { $0.isEqualRobust(element, wid) }) {
                Windows.removeWindow(index, pid)
            }
        }
    }

    private static func windowMiniaturizedOrDeminiaturized(_ element: AXUIElement, _ type: String) throws {
        let wid = try element.cgWindowId()
        DispatchQueue.main.async {
            if let window = (Windows.list.first { $0.isEqualRobust(element, wid) }) {
                window.isMinimized = type == kAXWindowMiniaturizedNotification
                App.app.refreshOpenUi([window], .refreshUiAfterExternalEvent)
            }
        }
    }

    private static func windowTitleChanged(_ element: AXUIElement, _ pid: pid_t) throws {
        let wid = try element.cgWindowId()
        AXUIElement.retryAxCallUntilTimeout(context: "(wid:\(wid) pid:\(pid))", debounceType: .windowTitleChanged, pid: pid, wid: wid, callType: .updateWindow) {
            if let (title, _, _, isMinimized, isFullscreen) = try element.windowAttributes() {
                DispatchQueue.main.async {
                    if let window = (Windows.list.first { $0.isEqualRobust(element, wid) }), title != window.title {
                        window.title = window.bestEffortTitle(title)
                        window.isMinimized = isMinimized
                        window.isFullscreen = isFullscreen
                        App.app.refreshOpenUi([window], .refreshUiAfterExternalEvent)
                    }
                }
            }
        }
    }

    private static func windowResizedOrMoved(_ element: AXUIElement, _ pid: pid_t) throws {
        let wid = try element.cgWindowId()
        AXUIElement.retryAxCallUntilTimeout(context: "(wid:\(wid) pid:\(pid))", debounceType: .windowResizedOrMoved, pid: pid, wid: wid, callType: .updateWindow) {
            try updateWindowSizeAndPositionAndFullscreen(element, wid, nil)
        }
    }

    private static func focusedWindowChanged(_ element: AXUIElement, _ pid: pid_t) throws {
        let wid = try element.cgWindowId()
        DispatchQueue.main.async {
            if let window = Windows.updateLastFocus(element, wid)?.first, let app = Applications.find(pid) {
                app.focusedWindow = window
                App.app.checkIfShortcutsShouldBeDisabled(window, app.runningApplication)
                App.app.refreshOpenUi([window], .refreshUiAfterExternalEvent)
            }
        }
    }
}
