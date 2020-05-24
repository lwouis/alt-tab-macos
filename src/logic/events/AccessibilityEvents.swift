import Cocoa

func axObserverCallback(observer: AXObserver, element: AXUIElement, notificationName: CFString, _: UnsafeMutableRawPointer?) -> Void {
    let type = notificationName as String
    retryUntilTimeout({ try handleEvent(type, element) })
}

func retryUntilTimeout(_ fn: @escaping () throws -> Void, _ startTime: DispatchTime = DispatchTime.now()) {
    DispatchQueue.global(qos: .userInteractive).async {
        do {
            try fn()
        } catch {
            let timePassedInSeconds = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000
            if timePassedInSeconds < Double(AXUIElement.globalTimeoutInSeconds) {
                DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + .milliseconds(10)) {
                    retryUntilTimeout(fn, startTime)
                }
            }
        }
    }
}

func handleEvent(_ type: String, _ element: AXUIElement) throws {
    debugPrint("Accessibility event", type, element)
    // events are handled concurrently, thus we check that the app is still running
    if let pid = try element.pid(),
       let app = NSRunningApplication(processIdentifier: pid) {
        switch type {
            case kAXApplicationActivatedNotification: try applicationActivated(element)
            case kAXApplicationHiddenNotification,
                 kAXApplicationShownNotification: try applicationHiddenOrShown(element, app, type)
            case kAXWindowCreatedNotification: try windowCreated(element, app)
            case kAXMainWindowChangedNotification: try focusedWindowChanged(element, app)
            case kAXUIElementDestroyedNotification: try windowDestroyed(element)
            case kAXWindowMiniaturizedNotification,
                 kAXWindowDeminiaturizedNotification: try windowMiniaturizedOrDeminiaturized(element, type)
            case kAXTitleChangedNotification: try windowTitleChanged(element)
            case kAXWindowResizedNotification: try windowResized(element)
            case kAXWindowMovedNotification: try windowMoved(element)
            case kAXFocusedUIElementChangedNotification: try focusedUiElementChanged(element, app)
            default: return
        }
    }
}

private func focusedUiElementChanged(_ element: AXUIElement, _ app: NSRunningApplication) throws {
    let appAxUiElement = AXUIElementCreateApplication(app.processIdentifier)
    if let currentWindows = try appAxUiElement.windows() {
        DispatchQueue.main.async {
            let windows = Windows.list.filter {
                // for AXUIElement of apps, CFEqual or == don't work; looks like a Cocoa bug
                let isFromApp = $0.application.runningApplication.processIdentifier == app.processIdentifier
                if isFromApp {
                    // this event is the only opportunity we have to check if a window became a tab, or a tab became a window
                    let isTabbedNew = $0.getIsTabbed(currentWindows)
                    if $0.isTabbed != isTabbedNew {
                        $0.isTabbed = isTabbedNew
                        return true
                    }
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
        Windows.list.insert(Windows.list.remove(at: existingIndex), at: 0)
            App.app.refreshOpenUi([Windows.list[0], Windows.list[existingIndex]])
        }
    }
}

private func applicationHiddenOrShown(_ element: AXUIElement, _ app: NSRunningApplication, _ type: String) throws {
    DispatchQueue.main.async {
        let windows = Windows.list.filter {
            // for AXUIElement of apps, CFEqual or == don't work; looks like a Cocoa bug
            let isFromApp = $0.application.runningApplication.processIdentifier == app.processIdentifier
            if isFromApp {
                $0.isHidden = type == kAXApplicationHiddenNotification
            }
            return isFromApp
        }
        App.app.refreshOpenUi(windows)
    }
}

private func windowCreated(_ element: AXUIElement, _ app: NSRunningApplication) throws {
    if let wid = try element.cgWindowId(),
       try element.isActualWindow(app.bundleIdentifier) {
        let axTitle = try element.title()
        let isFullscreen = try element.isFullscreen()
        let isMinimized = try element.isMinimized()
        let position = try element.position()
        DispatchQueue.main.async {
            // a window being un-minimized can trigger kAXWindowCreatedNotification
            if Windows.list.firstIndexThatMatches(element, wid) == nil,
               let app = (Applications.list.first { $0.runningApplication.processIdentifier == app.processIdentifier }) {
                let window = Window(element, app, wid, axTitle, isFullscreen, isMinimized, position)
            Windows.list.insertAndScaleRecycledPool([window], at: 0)
                Windows.cycleFocusedWindowIndex(1)
                App.app.refreshOpenUi([window])
            }
        }
    }
}

private func focusedWindowChanged(_ element: AXUIElement, _ app: NSRunningApplication) throws {
    if let wid = try element.cgWindowId() {
        let isActualWindow = try element.isActualWindow(app.bundleIdentifier)
        let axTitle = try element.title()
        let isFullscreen = try element.isFullscreen()
        let isMinimized = try element.isMinimized()
        let position = try element.position()
        DispatchQueue.main.async {
            if let existingIndex = Windows.list.firstIndexThatMatches(element, wid) {
            Windows.list.insert(Windows.list.remove(at: existingIndex), at: 0)
                App.app.refreshOpenUi([Windows.list[0], Windows.list[existingIndex]])
            } else if isActualWindow,
                      let app = (Applications.list.first { $0.runningApplication.processIdentifier == app.processIdentifier }) {
                Windows.list.insert(Window(element, app, wid, axTitle, isFullscreen, isMinimized, position), at: 0)
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
