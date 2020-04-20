import Cocoa

func axObserverCallback(observer: AXObserver, element: AXUIElement, notificationName: CFString, applicationPointer: UnsafeMutableRawPointer?) -> Void {
    let type = notificationName as String
    debugPrint("Accessibility event", type, element.title() ?? "nil")
    switch type {
        case kAXApplicationActivatedNotification: applicationActivated(element)
        case kAXApplicationHiddenNotification,
             kAXApplicationShownNotification: applicationHiddenOrShown(element, type)
        case kAXWindowCreatedNotification: windowCreated(element, applicationPointer)
        case kAXFocusedWindowChangedNotification: focusedWindowChanged(element)
        case kAXUIElementDestroyedNotification: windowDestroyed(element)
        case kAXWindowMiniaturizedNotification,
             kAXWindowDeminiaturizedNotification: windowMiniaturizedOrDeminiaturized(element, type)
        case kAXTitleChangedNotification: windowTitleChanged(element)
        case kAXWindowResizedNotification: windowResized(element)
        default: return
    }
}

private func applicationActivated(_ element: AXUIElement) {
    guard !App.app.appIsBeingUsed,
          let appFocusedWindow = element.focusedWindow(),
          let existingIndex = Windows.list.firstIndexThatMatches(appFocusedWindow) else { return }
    Windows.list.insert(Windows.list.remove(at: existingIndex), at: 0)
    App.app.refreshOpenUi([Windows.list[0], Windows.list[existingIndex]], true)
}

private func applicationHiddenOrShown(_ element: AXUIElement, _ type: String) {
    let windows = Windows.list.filter {
        // for AXUIElement of apps, CFEqual or == don't work; looks like a Cocoa bug
        $0.application.axUiElement!.pid() == element.pid()
    }
    windows.forEach { $0.isHidden = type == kAXApplicationHiddenNotification }
    App.app.refreshOpenUi(windows, true)
}

private func windowCreated(_ element: AXUIElement, _ applicationPointer: UnsafeMutableRawPointer?) {
    let application = Unmanaged<Application>.fromOpaque(applicationPointer!).takeUnretainedValue()
    guard element.isActualWindow(application.runningApplication.bundleIdentifier) else { return }
    // a window being un-minimized can trigger kAXWindowCreatedNotification
    guard Windows.list.firstIndexThatMatches(element) == nil else { return }
    let window = Window(element, application)
    Windows.list.insertAndScaleRecycledPool([window], at: 0)
    Windows.cycleFocusedWindowIndex(1)
    App.app.refreshOpenUi([window])
}

private func focusedWindowChanged(_ element: AXUIElement) {
    guard !App.app.appIsBeingUsed,
          let existingIndex = Windows.list.firstIndexThatMatches(element) else { return }
    Windows.list.insert(Windows.list.remove(at: existingIndex), at: 0)
    App.app.refreshOpenUi([Windows.list[0], Windows.list[existingIndex]])
}

private func windowDestroyed(_ element: AXUIElement) {
    guard let existingIndex = Windows.list.firstIndexThatMatches(element) else { return }
    Windows.list.remove(at: existingIndex)
    guard Windows.list.count > 0 else { App.app.hideUi(); return }
    Windows.moveFocusedWindowIndexAfterWindowDestroyedInBackground(existingIndex)
    App.app.refreshOpenUi()
}

private func windowMiniaturizedOrDeminiaturized(_ element: AXUIElement, _ type: String) {
    guard let index = Windows.list.firstIndexThatMatches(element) else { return }
    let window = Windows.list[index]
    window.isMinimized = type == kAXWindowMiniaturizedNotification
    App.app.refreshOpenUi([window], true)
}

private func windowTitleChanged(_ element: AXUIElement) {
    guard let index = Windows.list.firstIndexThatMatches(element) else { return }
    let window = Windows.list[index]
    guard let newTitle = window.axUiElement.title(),
          newTitle != window.title else { return }
    window.title = newTitle
    App.app.refreshOpenUi([window])
}

private func windowResized(_ element: AXUIElement) {
    guard let index = Windows.list.firstIndexThatMatches(element) else { return }
    let window = Windows.list[index]
    App.app.refreshOpenUi([window])
}