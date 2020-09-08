import Cocoa

func axObserverCallback(observer: AXObserver, element: AXUIElement, notificationName: CFString, _: UnsafeMutableRawPointer?) -> Void {
    let type = notificationName as String
    retryAxCallUntilTimeout { try handleEvent(type, element) }
}

// if the window server is busy, it may not reply to AX calls. We retry right before the call times-out and returns a bogus value
func retryAxCallUntilTimeout(_ group: DispatchGroup? = nil, _ fn: @escaping () throws -> Void, _ startTime: DispatchTime = DispatchTime.now()) {
    group?.enter()
    BackgroundWork.axCallsQueue.async {
        retryAxCallUntilTimeout_(group, fn, startTime)
    }
}

func retryAxCallUntilTimeout_(_ group: DispatchGroup?, _ fn: @escaping () throws -> Void, _ startTime: DispatchTime = DispatchTime.now()) {
    do {
        try fn()
        group?.leave()
    } catch {
        let timePassedInSeconds = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
        if timePassedInSeconds < Double(AXUIElement.globalTimeoutInSeconds) {
            BackgroundWork.axCallsQueue.asyncAfter(deadline: .now() + .milliseconds(10)) {
                retryAxCallUntilTimeout_(group, fn, startTime)
            }
        }
    }
}

func handleEvent(_ type: String, _ element: AXUIElement) throws {
    debugPrint("Accessibility event", type, type != kAXFocusedUIElementChangedNotification ? (try element.title() ?? "nil") : "nil")
    // events are handled concurrently, thus we check that the app is still running
    if let pid = try element.pid(),
       try (!(type == kAXWindowCreatedNotification && pid == ProcessInfo.processInfo.processIdentifier && element.subrole() == kAXUnknownSubrole)) {
        switch type {
            case kAXApplicationActivatedNotification: try applicationActivated(element)
            case kAXApplicationHiddenNotification,
                 kAXApplicationShownNotification: try applicationHiddenOrShown(element, pid, type)
            case kAXWindowCreatedNotification: try windowCreated(element, pid)
            case kAXMainWindowChangedNotification,
                 kAXFocusedWindowChangedNotification: try focusedWindowChanged(element, pid)
            case kAXUIElementDestroyedNotification: try windowDestroyed(element)
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

private func focusedUiElementChanged(_ element: AXUIElement, _ pid: pid_t) throws {
    let currentWindows = try AXUIElementCreateApplication(pid).windows()
    DispatchQueue.main.async {
        let windows = Windows.list.filter { w in
            if w.application.pid == pid && pid != ProcessInfo.processInfo.processIdentifier &&
                   w.spaceId == Spaces.currentSpaceId {
                let oldIsTabbed = w.isTabbed
                w.isTabbed = (currentWindows?.first { $0 == w.axUiElement } == nil)
                return oldIsTabbed != w.isTabbed
            }
            return false
        }
        App.app.refreshOpenUi(windows)
    }
}

private func applicationActivated(_ element: AXUIElement) throws {
    if let appFocusedWindow = try element.focusedWindow(),
       let wid = try appFocusedWindow.cgWindowId() {
        DispatchQueue.main.async {
            // ensure alt-tab window remains key, so local shortcuts work
            if App.app.appIsBeingUsed { App.app.thumbnailsPanel.makeKeyAndOrderFront(nil) }
            if let windows = Windows.updateLastFocus(appFocusedWindow, wid) {
                App.app.refreshOpenUi(windows)
            }
            Windows.checkIfShortcutsShouldBeDisabled()
        }
    }
}

private func applicationHiddenOrShown(_ element: AXUIElement, _ pid: pid_t, _ type: String) throws {
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

private func windowCreated(_ element: AXUIElement, _ pid: pid_t) throws {
    if let wid = try element.cgWindowId() {
        let axTitle = try element.title()
        let subrole = try element.subrole()
        let role = try element.role()
        let isFullscreen = try element.isFullscreen()
        let isMinimized = try element.isMinimized()
        let isOnNormalLevel = element.isOnNormalLevel(wid)
        let position = try element.position()
        DispatchQueue.main.async {
            if (Windows.list.firstIndex { $0.isEqualRobust(element, wid) }) == nil,
               let runningApp = NSRunningApplication(processIdentifier: pid),
               element.isActualWindow(runningApp, wid, isOnNormalLevel, axTitle, subrole, role),
               let app = (Applications.list.first { $0.pid == pid }) {
                let window = Window(element, app, wid, axTitle, isFullscreen, isMinimized, position)
                Windows.appendAndUpdateFocus(window)
                Windows.cycleFocusedWindowIndex(1)
                App.app.refreshOpenUi([window])
            }
        }
    }
}

private func focusedWindowChanged(_ element: AXUIElement, _ pid: pid_t) throws {
    if let wid = try element.cgWindowId(),
       let runningApp = NSRunningApplication(processIdentifier: pid),
       // photoshop will focus a window *after* you focus another app
       // we check that a focused window happens within an active app
       runningApp.isActive {
        let axTitle = try element.title()
        let subrole = try element.subrole()
        let role = try element.role()
        let isFullscreen = try element.isFullscreen()
        let isMinimized = try element.isMinimized()
        let isOnNormalLevel = element.isOnNormalLevel(wid)
        let position = try element.position()
        DispatchQueue.main.async {
            if let windows = Windows.updateLastFocus(element, wid) {
                App.app.refreshOpenUi(windows)
            } else if element.isActualWindow(runningApp, wid, isOnNormalLevel, axTitle, subrole, role),
            let app = (Applications.list.first { $0.pid == pid }) {
                let window = Window(element, app, wid, axTitle, isFullscreen, isMinimized, position)
                Windows.appendAndUpdateFocus(window)
                App.app.refreshOpenUi([window])
            }
            Windows.checkIfShortcutsShouldBeDisabled()
        }
    }
}

private func windowDestroyed(_ element: AXUIElement) throws {
    let wid = try element.cgWindowId()
    DispatchQueue.main.async {
        if let window = (Windows.list.first { $0.isEqualRobust(element, wid) }) {
            Windows.removeAndUpdateFocus(window)
            let windowlessApp = window.application.addWindowslessAppsIfNeeded()
            if Windows.list.count > 0 {
                Windows.moveFocusedWindowIndexAfterWindowDestroyedInBackground(window)
                App.app.refreshOpenUi(windowlessApp)
            } else {
                App.app.hideUi()
            }
        }
    }
}

private func windowMiniaturizedOrDeminiaturized(_ element: AXUIElement, _ type: String) throws {
    if let wid = try element.cgWindowId() {
        DispatchQueue.main.async {
            if let window = (Windows.list.first { $0.isEqualRobust(element, wid) }) {
            window.isMinimized = type == kAXWindowMiniaturizedNotification
                App.app.refreshOpenUi([window])
            }
        }
    }
}

private func windowTitleChanged(_ element: AXUIElement) throws {
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

private func windowResized(_ element: AXUIElement) throws {
    // TODO: only trigger this at the end of the resize, not on every tick
    // currenly resizing a window will lag AltTab as it triggers too much UI work
    if let wid = try element.cgWindowId() {
        let isFullscreen = try element.isFullscreen()
        DispatchQueue.main.async {
            if let window = (Windows.list.first { $0.isEqualRobust(element, wid) }) {
                window.isFullscreen = isFullscreen
                App.app.refreshOpenUi([window])
            }
            Windows.checkIfShortcutsShouldBeDisabled()
        }
    }
}

private func windowMoved(_ element: AXUIElement) throws {
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
