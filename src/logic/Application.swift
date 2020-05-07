import Cocoa

class Application: NSObject {
    var runningApplication: NSRunningApplication
    var axUiElement: AXUIElement?
    var axObserver: AXObserver?
    var isReallyFinishedLaunching = false

    static let notifications = [
        kAXApplicationActivatedNotification,
        kAXMainWindowChangedNotification,
        kAXWindowCreatedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
        kAXFocusedUIElementChangedNotification,
    ]

    // some apps never finish their subscription retry loop; they should be stopped to avoid infinite loop
    static func stopSubscriptionRetries(_ notification: String, _ runningApplication: NSRunningApplication) {
        let subscriptionToRemove: String = String(runningApplication.processIdentifier) + notification
        Applications.appsInSubscriptionRetryLoop.removeAll { (subscription: String) -> Bool in
            return subscription == subscriptionToRemove
        }
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
        debugPrint("Adding app", runningApplication.processIdentifier, runningApplication.bundleIdentifier ?? "nil")
        observeEvents()
    }

    func observeNewWindows() {
        if let windows = (axUiElement!.windows()?
            .filter { $0.isActualWindow(runningApplication.bundleIdentifier) }) {
            let actualWindows = windows.filter { Windows.list.firstIndexThatMatches($0) == nil }
            if actualWindows.count > 0 {
                addWindows(actualWindows)
            }
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let isFinishedLaunching = change![.newKey], isFinishedLaunching as! Bool else { return }
        removeObserver()
        addAndObserveWindows()
    }

    private func addWindows(_ axWindows: [AXUIElement]) {
        let windows = axWindows.map { Window($0, self) }
        Windows.list.insertAndScaleRecycledPool(windows, at: 0)
        if App.app.appIsBeingUsed {
            Windows.cycleFocusedWindowIndex(windows.count)
        }
        App.app.refreshOpenUi(windows)
    }

    private func observeEvents() {
        guard let axObserver = axObserver else { return }
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        for notification in Application.notifications {
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
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
    }
}
