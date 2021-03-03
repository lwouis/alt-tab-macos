import Cocoa
import ApplicationServices.HIServices.AXUIElement
import ApplicationServices.HIServices.AXNotificationConstants

func axObserverCallback(observer: AXObserver, element: AXUIElement, notificationName: CFString, _: UnsafeMutableRawPointer?) -> Void {
    let type = notificationName as String
    retryAxCallUntilTimeout { try handleEvent(type, element) }
}

fileprivate func handleEvent(_ type: String, _ element: AXUIElement) throws {
    debugPrint("Accessibility event", type, type != kAXFocusedUIElementChangedNotification ? (try element.title() ?? "nil") : "nil")
    // events are handled concurrently, thus we check that the app is still running
    if let pid = try element.pid(),
       try (!(pid == ProcessInfo.processInfo.processIdentifier && element.subrole() == kAXUnknownSubrole)) {
        switch type {
            case kAXApplicationActivatedNotification: try applicationActivated(element, pid)
            case kAXApplicationHiddenNotification,
                 kAXApplicationShownNotification: try applicationHiddenOrShown(element, pid, type)
            case kAXWindowCreatedNotification: try windowCreated(element, pid)
            case kAXMainWindowChangedNotification,
                 kAXFocusedWindowChangedNotification: try focusedWindowChanged(element, pid)
            case kAXUIElementDestroyedNotification: try windowDestroyed(element, pid)
            case kAXWindowMiniaturizedNotification,
                 kAXWindowDeminiaturizedNotification: try windowMiniaturizedOrDeminiaturized(element, type)
            case kAXTitleChangedNotification: try windowTitleChanged(element)
            case kAXWindowResizedNotification: try windowResized(element)
            case kAXWindowMovedNotification: try windowMoved(element)
            case kAXFocusedUIElementChangedNotification: try focusedUiElementChanged(element, pid)
            default: return
        }
    }
}

fileprivate func focusedUiElementChanged(_ element: AXUIElement, _ pid: pid_t) throws {
    if NSRunningApplication(processIdentifier: pid) != nil {
        let currentWindows = try AXUIElementCreateApplication(pid).windows()
        DispatchQueue.main.async {
            let windows = updateTabs(pid, currentWindows)
            App.app.refreshOpenUi(windows)
        }
    }
}

fileprivate func updateTabs(_ pid: pid_t, _ currentWindows: [AXUIElement]?) -> [Window] {
    let windows = Windows.list.filter { w in
        if w.application.pid == pid && pid != ProcessInfo.processInfo.processIdentifier &&
               w.spaceId == Spaces.currentSpaceId {
            let oldIsTabbed = w.isTabbed
            w.isTabbed = (currentWindows?.first { $0 == w.axUiElement } == nil)
            return oldIsTabbed != w.isTabbed
        }
        return false
    }
    return windows
}

fileprivate func applicationActivated(_ element: AXUIElement, _ pid: pid_t) throws {
    if let appFocusedWindow = try element.focusedWindow(),
       let wid = try appFocusedWindow.cgWindowId() {
        DispatchQueue.main.async {
            if let app = (Applications.list.first { $0.pid == pid }), !app.hasBeenActiveOnce {
                app.hasBeenActiveOnce = true
            }
            // ensure alt-tab window remains key, so local shortcuts work
            if App.app.appIsBeingUsed { App.app.thumbnailsPanel.makeKeyAndOrderFront(nil) }
            if let window = Windows.updateLastFocus(appFocusedWindow, wid) {
                Windows.checkIfShortcutsShouldBeDisabled(window.first!)
                App.app.refreshOpenUi(window)
            }
        }
    }
}

fileprivate func applicationHiddenOrShown(_ element: AXUIElement, _ pid: pid_t, _ type: String) throws {
    DispatchQueue.main.async {
        if let app = (Applications.list.first { $0.pid == pid }) {
            app.isHidden = type == kAXApplicationHiddenNotification
            let windows = Windows.list.filter {
                // for AXUIElement of apps, CFEqual or == don't work; looks like a Cocoa bug
                return $0.application.pid == pid
            }
            App.app.refreshOpenUi(windows)
        }
    }
}

fileprivate func windowCreated(_ element: AXUIElement, _ pid: pid_t) throws {
    if let wid = try element.cgWindowId() {
        let axTitle = try element.title()
        let subrole = try element.subrole()
        let role = try element.role()
        let isFullscreen = try element.isFullscreen()
        let isMinimized = try element.isMinimized()
        let level = try wid.level()
        let position = try element.position()
        let size = try element.size()
        DispatchQueue.main.async {
            if (Windows.list.firstIndex { $0.isEqualRobust(element, wid) }) == nil,
               let runningApp = NSRunningApplication(processIdentifier: pid),
               AXUIElement.isActualWindow(runningApp, wid, level, axTitle, subrole, role, size),
               let app = (Applications.list.first { $0.pid == pid }) {
                let window = Window(element, app, wid, axTitle, isFullscreen, isMinimized, position, size)
                Windows.appendAndUpdateFocus(window)
                Windows.cycleFocusedWindowIndex(1)
                App.app.refreshOpenUi([window])
            }
        }
    }
}

fileprivate func focusedWindowChanged(_ element: AXUIElement, _ pid: pid_t) throws {
    if let wid = try element.cgWindowId(),
       let runningApp = NSRunningApplication(processIdentifier: pid) {
        // photoshop will focus a window *after* you focus another app
        // we check that a focused window happens within an active app
        if runningApp.isActive {
            let axTitle = try element.title()
            let subrole = try element.subrole()
            let role = try element.role()
            let isFullscreen = try element.isFullscreen()
            let isMinimized = try element.isMinimized()
            let level = try wid.level()
            let position = try element.position()
            let size = try element.size()
            DispatchQueue.main.async {
                if let windows = Windows.updateLastFocus(element, wid) {
                    App.app.refreshOpenUi(windows)
                } else if AXUIElement.isActualWindow(runningApp, wid, level, axTitle, subrole, role, size),
                          let app = (Applications.list.first { $0.pid == pid }) {
                    let window = Window(element, app, wid, axTitle, isFullscreen, isMinimized, position, size)
                    Windows.appendAndUpdateFocus(window)
                    App.app.refreshOpenUi([window])
                }
            }
        } else {
            DispatchQueue.main.async {
                if let app = (Applications.list.first { $0.pid == pid }) {
                    // work-around for apps started "hidden" like in Login Items with the "Hide" checkbox, or with `open -j`
                    // these apps report isHidden=false, don't generate windowCreated events initially, and have a delay before their windows are created
                    // our only recourse is to manually check their windows once they emit
                    if (!app.hasBeenActiveOnce) {
                        app.observeNewWindows()
                    }
                }
            }
        }
    }
}

fileprivate func windowDestroyed(_ element: AXUIElement, _ pid: pid_t) throws {
    let wid = try element.cgWindowId()
    let appIsStillRunning = NSRunningApplication(processIdentifier: pid) != nil
    let currentWindows = appIsStillRunning ? try AXUIElementCreateApplication(pid).windows() : []
    DispatchQueue.main.async {
        if let window = (Windows.list.first { $0.isEqualRobust(element, wid) }) {
            Windows.removeAndUpdateFocus(window)
            let windowlessApp = window.application.addWindowslessAppsIfNeeded()
            if Windows.list.count > 0 {
                // closing a tab may make another tab visible; we refresh tab status
                var windows = updateTabs(pid, currentWindows)
                Windows.moveFocusedWindowIndexAfterWindowDestroyedInBackground(window)
                if let windowlessApp = windowlessApp {
                    windows.append(contentsOf: windowlessApp)
                }
                App.app.refreshOpenUi(windows)
            } else {
                App.app.hideUi()
            }
        }
    }
}

fileprivate func windowMiniaturizedOrDeminiaturized(_ element: AXUIElement, _ type: String) throws {
    if let wid = try element.cgWindowId() {
        DispatchQueue.main.async {
            if let window = (Windows.list.first { $0.isEqualRobust(element, wid) }) {
                window.isMinimized = type == kAXWindowMiniaturizedNotification
                App.app.refreshOpenUi([window])
            }
        }
    }
}

fileprivate func windowTitleChanged(_ element: AXUIElement) throws {
    if let wid = try element.cgWindowId() {
        let newTitle = try element.title()
        DispatchQueue.main.async {
            if let window = (Windows.list.first { $0.isEqualRobust(element, wid) }),
               newTitle != nil && newTitle != window.title {
                window.title = newTitle!
                App.app.refreshOpenUi([window])
            }
        }
    }
}

fileprivate func windowResized(_ element: AXUIElement) throws {
    // TODO: only trigger this at the end of the resize, not on every tick
    // currenly resizing a window will lag AltTab as it triggers too much UI work
    if let wid = try element.cgWindowId() {
        let isFullscreen = try element.isFullscreen()
        DispatchQueue.main.async {
            if let window = (Windows.list.first { $0.isEqualRobust(element, wid) }) {
                if window.isFullscreen != isFullscreen {
                    window.isFullscreen = isFullscreen
                    Windows.checkIfShortcutsShouldBeDisabled(window)
                }
                App.app.refreshOpenUi([window])
            }
        }
    }
}

fileprivate func windowMoved(_ element: AXUIElement) throws {
    if let wid = try element.cgWindowId() {
        let position = try element.position()
        DispatchQueue.main.async {
            if let window = (Windows.list.first { $0.isEqualRobust(element, wid) }) {
                window.position = position
                App.app.refreshOpenUi([window])
            }
        }
    }
}
