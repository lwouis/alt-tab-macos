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
       try pid != ProcessInfo.processInfo.processIdentifier || (element.subrole() != kAXUnknownSubrole && type != kAXFocusedUIElementChangedNotification) {
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
            case kAXWindowResizedNotification: try windowResized(element)
            case kAXWindowMovedNotification: try windowMoved(element)
            case kAXFocusedUIElementChangedNotification: try focusedUiElementChanged(pid)
            default: return
        }
    }
}

fileprivate func focusedUiElementChanged(_ pid: pid_t) throws {
    // this event is the only event triggered when the user tabs a window. However, macOS implementation is lazy: a
    // window freshly tabbed will still return the size/position/screenshot as when it was still a standalone
    // window. Only when the user clicks on the tab, and it gets displayed, will the tabbed window actually resize
    // (it will send the windowResized event)
    pid.retryToRefreshTabsUntilScreenIsNotAnimating { App.app.refreshOpenUi($0) }
}

fileprivate func applicationActivated(_ element: AXUIElement, _ pid: pid_t) throws {
    let appFocusedWindow = try element.focusedWindow()
    let wid = try appFocusedWindow?.cgWindowId()
    DispatchQueue.main.async {
        if let app = (Applications.list.first { $0.pid == pid }) {
            if !app.hasBeenActiveOnce {
                app.hasBeenActiveOnce = true
            }
            let window = (appFocusedWindow != nil && wid != nil) ? Windows.updateLastFocus(appFocusedWindow!, wid!)?.first : nil
            app.focusedWindow = window
            App.app.checkIfShortcutsShouldBeDisabled(window, app.runningApplication)
            App.app.refreshOpenUi(window != nil ? [window!] : nil)
            guard let win = (Windows.list.first { app.runningApplication.processIdentifier == $0.application.runningApplication.processIdentifier && !$0.isWindowlessApp }) else {
                // for edge-case: some app (e.g. Bear.app) is loading and runningApplication.isFinishedLaunching is false (sometimes) when we call observeNewWindows() at first time
                // as a result we miss their windows. but we will receive kAXApplicationActivatedNotification notification and we can add it successfully
                app.observeNewWindows()
                return
            }
        }
    }
}

fileprivate func applicationHiddenOrShown(_ pid: pid_t, _ type: String) throws {
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
        DispatchQueue.main.async {
            Applications.list.first { $0.pid == pid }?.focusedWindow = Windows.list.first { $0.isEqualRobust(element, wid) }
        }
    } else {
        DispatchQueue.main.async {
            Applications.list.first { $0.pid == pid }?.focusedWindow = nil
        }
    }
}

fileprivate func windowDestroyed(_ element: AXUIElement, _ pid: pid_t) throws {
    let wid = try element.cgWindowId()
    DispatchQueue.main.async {
        if let index = (Windows.list.firstIndex { $0.isEqualRobust(element, wid) }) {
            let window = Windows.list[index]
            Windows.removeAndUpdateFocus(window)
            let windowlessApp = window.application.addWindowslessAppsIfNeeded()
            if Windows.list.count > 0 {
                // closing a tab may make another tab visible; we refresh tab status
                pid.retryToRefreshTabsUntilScreenIsNotAnimating { windows in
                    Windows.moveFocusedWindowIndexAfterWindowDestroyedInBackground(index)
                    if let windowlessApp = windowlessApp {
                        App.app.refreshOpenUi(windows + windowlessApp)
                    } else {
                        App.app.refreshOpenUi(windows)
                    }
                }
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

fileprivate func windowTitleChanged(_ element: AXUIElement, _ pid: pid_t) throws {
    if let wid = try element.cgWindowId() {
        let newTitle = try element.title()
        DispatchQueue.main.async {
            if let window = (Windows.list.first { $0.isEqualRobust(element, wid) }),
               newTitle != nil && newTitle != window.title {
                window.title = newTitle!
                // refreshing tabs during title change helps mitigate some false positives of tab detection
                pid.retryToRefreshTabsUntilScreenIsNotAnimating {
                    App.app.refreshOpenUi($0)
                }
            }
        }
    }
}

fileprivate func windowResized(_ element: AXUIElement) throws {
    // TODO: only trigger this at the end of the resize, not on every tick
    // currently resizing a window will lag AltTab as it triggers too much UI work
    if let wid = try element.cgWindowId() {
        let isFullscreen = try element.isFullscreen()
        let size = try element.size()
        let position = try element.position()
        DispatchQueue.main.async {
            if let window = (Windows.list.first { $0.isEqualRobust(element, wid) }) {
                window.size = size
                window.position = position
                if window.isFullscreen != isFullscreen {
                    window.isFullscreen = isFullscreen
                    App.app.checkIfShortcutsShouldBeDisabled(window, nil)
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
