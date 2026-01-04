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
                    let needsRefresh = window.size != size || window.position != position || window.isMinimized != isMinimized || window.isFullscreen != isFullscreen
                    window.title = window.bestEffortTitle(title)
                    window.size = size
                    window.position = position
                    window.isMinimized = isMinimized
                    if window.isFullscreen != isFullscreen {
                        window.isFullscreen = isFullscreen
                        App.app.checkIfShortcutsShouldBeDisabled(window, nil)
                    }
                    if needsRefresh {
                        App.app.refreshOpenUi([window], .refreshUiAfterExternalEvent)
                    }
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
        let appFocusedWindow = try element.focusedWindow()
        let wid = try appFocusedWindow?.cgWindowId()
        DispatchQueue.main.async {
            if let app = Applications.find(pid) {
                if app.hasBeenActiveOnce != true {
                    app.hasBeenActiveOnce = true
                }
                let window = (appFocusedWindow != nil && wid != nil) ? Windows.updateLastFocus(appFocusedWindow!, wid!)?.first : nil
                app.focusedWindow = window
                App.app.checkIfShortcutsShouldBeDisabled(window, app.runningApplication)
                App.app.refreshOpenUi(window != nil ? [window!] : [], .refreshUiAfterExternalEvent)
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
        if let (title, role, subrole, isMinimized, isFullscreen) = try element.windowAttributes() {
            let position = try element.position()
            let size = try element.size()
            let level = wid.level()
            DispatchQueue.main.async {
                if let app = Applications.find(pid), NSRunningApplication(processIdentifier: pid) != nil {
                    if (!Windows.list.contains { $0.isEqualRobust(element, wid) }) &&
                           AXUIElement.isActualWindow(app, wid, level, title, subrole, role, size) {
                        let window = Window(element, app, wid, title, isFullscreen, isMinimized, position, size)
                        Windows.appendAndUpdateFocus(window)
                        Windows.cycleFocusedWindowIndex(1)
                        App.app.refreshOpenUi([window], .refreshUiAfterExternalEvent)
                    }
                }
            }
        }
    }

    private static func focusedWindowChanged(_ element: AXUIElement, _ pid: pid_t) throws {
        let wid = try element.cgWindowId()
        if let runningApp = NSRunningApplication(processIdentifier: pid) {
            // photoshop will focus a window *after* you focus another app
            // we check that a focused window happens within an active app
            if runningApp.isActive {
                DispatchQueue.main.async {
                    guard let app = Applications.find(pid) else { return }
                    // if the window is shown by alt-tab, we mark it as focused for this app
                    // this avoids issues with dialogs, quicklook, etc (see scenarios from #1044 and #2003)
                    if let w = (Windows.list.first { $0.isEqualRobust(element, wid) }) {
                        app.focusedWindow = w
                    }
                    if let windows = Windows.updateLastFocus(element, wid) {
                        App.app.refreshOpenUi(windows, .refreshUiAfterExternalEvent)
                    } else {
                        AXUIElement.retryAxCallUntilTimeout(context: "(wid:\(wid) pid:\(pid))", pid: pid, callType: .updateWindow) {
                            if let (title, role, subrole, isMinimized, isFullscreen) = try element.windowAttributes() {
                                let position = try element.position()
                                let size = try element.size()
                                let level = wid.level()
                                DispatchQueue.main.async {
                                    if (!Windows.list.contains { $0.isEqualRobust(element, wid) }),
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
        } else {
            DispatchQueue.main.async {
                Applications.find(pid)?.focusedWindow = nil
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
}
