import Cocoa

func axObserverCallback(observer: AXObserver, element: AXUIElement, notificationName: CFString, _: UnsafeMutableRawPointer?) -> Void {
    let type = notificationName as String
    retryAxCallUntilTimeout({ try handleEvent(type, element) })
}

// if the window server is busy, it may not reply to AX calls. We retry right before the call times-out and returns a bogus value
func retryAxCallUntilTimeout(_ fn: @escaping () throws -> Void, _ startTime: DispatchTime = DispatchTime.now()) {
    BackgroundWork.axCallsQueue.asyncWithCap(semaphore: BackgroundWork.axCallsGlobalSemaphore) {
        do {
            try fn()
        } catch {
            let timePassedInSeconds = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
            if timePassedInSeconds < Double(AXUIElement.globalTimeoutInSeconds) {
                BackgroundWork.axCallsQueue.asyncWithCap(.now() + .milliseconds(10), semaphore: BackgroundWork.axCallsGlobalSemaphore) {
                    retryAxCallUntilTimeout(fn, startTime)
                }
            }
        }
    }
}

func handleEvent(_ type: String, _ element: AXUIElement) throws {
    debugPrint("Accessibility event", type, try element.title())
    // events are handled concurrently, thus we check that the app is still running
    if let pid = try element.pid() {
        switch type {
            case kAXApplicationActivatedNotification: try applicationActivated(element)
            case kAXApplicationHiddenNotification,
                 kAXApplicationShownNotification: try applicationHiddenOrShown(element, pid, type)
            case kAXWindowCreatedNotification: try windowCreated(element, pid)
            case kAXMainWindowChangedNotification: try focusedWindowChanged(element, pid)
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
    let appAxUiElement = AXUIElementCreateApplication(pid)
    if let currentWindows = try appAxUiElement.windows() {
        DispatchQueue.main.async {
            let windows = Windows.list.filter { w in
                // for AXUIElement of apps, CFEqual or == don't work; looks like a Cocoa bug
                let isFromApp = w.application.runningApplication.processIdentifier == pid
                if isFromApp {
                    // this event is the only opportunity we have to check if a window became a tab, or a tab became a window
                    let oldIsTabbed = w.isTabbed
                    w.refreshIsTabbed(currentWindows)
                    return oldIsTabbed != w.isTabbed
                }
                return false
            }
            App.app.refreshOpenUi(windows)
        }
    }
}

private func applicationActivated(_ element: AXUIElement) throws {
    if let appFocusedWindow = try element.focusedWindow(),
       let wid = try appFocusedWindow.cgWindowId() {
        DispatchQueue.main.async {
            guard let existingIndex = Windows.list.firstIndexThatMatches(appFocusedWindow, wid) else { return }
            Windows.list.insertAndScaleRecycledPool(Windows.list.remove(at: existingIndex), at: 0)
            App.app.refreshOpenUi([Windows.list[0], Windows.list[existingIndex]])
        }
    }
}

private func applicationHiddenOrShown(_ element: AXUIElement, _ pid: pid_t, _ type: String) throws {
    DispatchQueue.main.async {
        let windows = Windows.list.filter {
            // for AXUIElement of apps, CFEqual or == don't work; looks like a Cocoa bug
            let isFromApp = $0.application.runningApplication.processIdentifier == pid
            if isFromApp {
                $0.isHidden = type == kAXApplicationHiddenNotification
            }
            return isFromApp
        }
        App.app.refreshOpenUi(windows)
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
            // a window being un-minimized can trigger kAXWindowCreatedNotification
            if Windows.list.firstIndexThatMatches(element, wid) == nil,
               let runningApp = NSRunningApplication(processIdentifier: pid),
               element.isActualWindow(runningApp, wid, isOnNormalLevel, axTitle, subrole, role),
               let app = (Applications.list.first { $0.runningApplication.processIdentifier == pid }) {
                let window = Window(element, app, wid, axTitle, isFullscreen, isMinimized, position)
                Windows.list.insertAndScaleRecycledPool(window, at: 0)
                Windows.cycleFocusedWindowIndex(1)
                App.app.refreshOpenUi([window])
            }
        }
    }
}

private func focusedWindowChanged(_ element: AXUIElement, _ pid: pid_t) throws {
    if let wid = try element.cgWindowId() {
        let axTitle = try element.title()
        let subrole = try element.subrole()
        let role = try element.role()
        let isFullscreen = try element.isFullscreen()
        let isMinimized = try element.isMinimized()
        let isOnNormalLevel = element.isOnNormalLevel(wid)
        let position = try element.position()
        DispatchQueue.main.async {
            if let existingIndex = Windows.list.firstIndexThatMatches(element, wid) {
                Windows.list.insertAndScaleRecycledPool(Windows.list.remove(at: existingIndex), at: 0)
                App.app.refreshOpenUi([Windows.list[0], Windows.list[existingIndex]])
            } else if let runningApp = NSRunningApplication(processIdentifier: pid),
                      element.isActualWindow(runningApp, wid, isOnNormalLevel, axTitle, subrole, role),
                      let app = (Applications.list.first { $0.runningApplication.processIdentifier == pid }) {
                Windows.list.insertAndScaleRecycledPool(Window(element, app, wid, axTitle, isFullscreen, isMinimized, position), at: 0)
                App.app.refreshOpenUi([Windows.list[0]])
            }
        }
    }
}

private func windowDestroyed(_ element: AXUIElement) throws {
    let wid = try element.cgWindowId()
    DispatchQueue.main.async {
        guard let existingIndex = Windows.list.firstIndexThatMatches(element, wid) else { return }
        Windows.list.remove(at: existingIndex)
        guard Windows.list.count > 0 else { App.app.hideUi(); return }
        Windows.moveFocusedWindowIndexAfterWindowDestroyedInBackground(existingIndex)
        App.app.refreshOpenUi()
    }
}

private func windowMiniaturizedOrDeminiaturized(_ element: AXUIElement, _ type: String) throws {
    if let wid = try element.cgWindowId() {
        DispatchQueue.main.async {
            guard let index = Windows.list.firstIndexThatMatches(element, wid) else { return }
            let window = Windows.list[index]
            window.isMinimized = type == kAXWindowMiniaturizedNotification
            App.app.refreshOpenUi([window])
        }
    }
}

private func windowTitleChanged(_ element: AXUIElement) throws {
    if let wid = try element.cgWindowId() {
        let newTitle = try element.title()
        DispatchQueue.main.async {
            guard let index = Windows.list.firstIndexThatMatches(element, wid) else { return }
            let window = Windows.list[index]
            guard newTitle != nil && newTitle != window.title else { return }
            window.title = newTitle!
            App.app.refreshOpenUi([window])
        }
    }
}

private func windowResized(_ element: AXUIElement) throws {
    // TODO: only trigger this at the end of the resize, not on every tick
    // currenly resizing a window will lag AltTab as it triggers too much UI work
    if let wid = try element.cgWindowId() {
        let isFullscreen = try element.isFullscreen()
        DispatchQueue.main.async {
            guard let index = Windows.list.firstIndexThatMatches(element, wid) else { return }
            let window = Windows.list[index]
            window.isFullscreen = isFullscreen
            App.app.refreshOpenUi([window])
        }
    }
}

private func windowMoved(_ element: AXUIElement) throws {
    if let wid = try element.cgWindowId() {
        let position = try element.position()
        DispatchQueue.main.async {
            guard let index = Windows.list.firstIndexThatMatches(element, wid) else { return }
            let window = Windows.list[index]
            window.position = position
            App.app.refreshOpenUi([window])
        }
    }
}
