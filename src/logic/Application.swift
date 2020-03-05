import Cocoa

class Application: NSObject {
    var runningApplication: NSRunningApplication
    var axUiElement: AXUIElement?
    var axObserver: AXObserver?
    var isReallyFinishedLaunching = false

    static let notifications = [
        kAXApplicationActivatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXWindowCreatedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]

    // some apps never finish their subscription retry loop; they should be stopped to avoid infinite loop
    static func stopSubscriptionRetries(_ notification: String, _ runningApplication: NSRunningApplication) {
        debugPrint("removeObservers", runningApplication.processIdentifier, runningApplication.bundleIdentifier)
        Applications.appsInSubscriptionRetryLoop.removeAll { $0 == String(runningApplication.processIdentifier) + String(notification) }
    }

    init(_ runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication
        super.init()
        if runningApplication.isFinishedLaunching {
            addAndObserveWindows()
        } else {
            runningApplication.addObserver(self, forKeyPath: "isFinishedLaunching", options: [.new], context: nil)
        }
    }

    deinit {
        debugPrint("deinit", runningApplication.processIdentifier, runningApplication.bundleIdentifier)
        // some apps never finish launching; subscription retries should be stopped to avoid infinite loops
        Application.notifications.forEach { Application.stopSubscriptionRetries($0, runningApplication) }
        // some apps never finish launching; observer should be removed to avoid leak
        removeObserver()
    }

    func removeObserver() {
        runningApplication.safeRemoveObserver(self, "isFinishedLaunching")
    }

    private func addAndObserveWindows() {
        axUiElement = AXUIElementCreateApplication(runningApplication.processIdentifier)
        AXObserverCreate(runningApplication.processIdentifier, axObserverCallback, &axObserver)
        debugPrint("Adding app: " + (runningApplication.bundleIdentifier ?? "nil"))
        observeEvents()
    }

    func observeNewWindows() {
        var newWindows = [AXUIElement]()
        for window in getActualWindows() {
            guard Windows.list.firstIndexThatMatches(window) == nil else { continue }
            newWindows.append(window)
        }
        addWindows(newWindows)
    }

    private func getActualWindows() -> [AXUIElement] {
        return axUiElement!.windows()?.filter { $0.isActualWindow(runningApplication.isHidden) } ?? []
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let isFinishedLaunching = change![.newKey], isFinishedLaunching as! Bool else { return }
        removeObserver()
        addAndObserveWindows()
    }

    private func addWindows(_ windows: [AXUIElement]) {
        Windows.list.insert(contentsOf: windows.map { Window($0, self) }, at: 0)
    }

    private func observeEvents() {
        guard let axObserver = axObserver else { return }
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        for notification in Application.notifications {
            debugPrint("subscribeWithRetry app", runningApplication.processIdentifier, notification, runningApplication.bundleIdentifier)
            Applications.appsInSubscriptionRetryLoop.append(String(runningApplication.processIdentifier) + String(notification))
            axUiElement!.subscribeWithRetry(axObserver, notification, selfPointer, { [weak self] in
                // some apps have `isFinishedLaunching == true` but are actually not finished, and will return .cannotComplete
                // we consider them ready when the first subscription succeeds, and list their windows again at that point
                guard let self = self else { return }
                if !self.isReallyFinishedLaunching {
                    self.isReallyFinishedLaunching = true
                    self.observeNewWindows()
                }
            }, runningApplication)
        }
        debugPrint("app sub list", Applications.appsInSubscriptionRetryLoop)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
    }
}

private func axObserverCallback(observer: AXObserver, element: AXUIElement, notificationName: CFString, applicationPointer: UnsafeMutableRawPointer?) -> Void {
    let application = Unmanaged<Application>.fromOpaque(applicationPointer!).takeUnretainedValue()
    let app = App.shared as! App
    let type = notificationName as String
    debugPrint("OS event: " + type, element.title() ?? "nil")
    switch type {
        case kAXApplicationActivatedNotification: eventApplicationActivated(app, element)
        case kAXApplicationHiddenNotification, kAXApplicationShownNotification: eventApplicationHiddenOrShown(app, element, type)
        case kAXWindowCreatedNotification: eventWindowCreated(app, element, application)
        case kAXFocusedWindowChangedNotification: eventFocusedWindowChanged(app, element)
        default: return
    }
}

private func eventApplicationActivated(_ app: App, _ element: AXUIElement) {
    guard !app.appIsBeingUsed,
          let appFocusedWindow = element.focusedWindow(),
          let existingIndex = Windows.list.firstIndexThatMatches(appFocusedWindow) else { return }
    Windows.list.insert(Windows.list.remove(at: existingIndex), at: 0)
}

private func eventApplicationHiddenOrShown(_ app: App, _ element: AXUIElement, _ type: String) {
    for window in Windows.list {
        guard CFEqual(window.application.axUiElement!, element) else { continue }
        window.isHidden = type == kAXApplicationHiddenNotification
    }
    app.refreshOpenUi()
}

private func eventWindowCreated(_ app: App, _ element: AXUIElement, _ application: Application) {
    guard element.isActualWindow() else { return }
    // a window being un-minimized can trigger kAXWindowCreatedNotification
    guard Windows.list.firstIndexThatMatches(element) == nil else { return }
    let window = Window(element, application)
    Windows.list.insert(window, at: 0)
    Windows.moveFocusedWindowIndexAfterWindowCreatedInBackground()
    // TODO: find a better way to get thumbnail of the new window
    window.refreshThumbnail()
    app.refreshOpenUi()
}

private func eventFocusedWindowChanged(_ app: App, _ element: AXUIElement) {
    guard !app.appIsBeingUsed,
          let existingIndex = Windows.list.firstIndexThatMatches(element) else { return }
    Windows.list.insert(Windows.list.remove(at: existingIndex), at: 0)
}