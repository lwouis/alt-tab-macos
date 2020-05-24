import Cocoa

class Application: NSObject {
    // kvObservers should be listed first, so it gets deinit'ed first; otherwise it can crash
    var kvObservers: [NSKeyValueObservation]?
    var runningApplication: NSRunningApplication
    var axUiElement: AXUIElement?
    var axObserver: AXObserver?
    var isReallyFinishedLaunching = false

    static func notifications(_ app: NSRunningApplication) -> [String] {
        var n = [
            kAXApplicationActivatedNotification,
            kAXMainWindowChangedNotification,
            kAXWindowCreatedNotification,
            kAXApplicationHiddenNotification,
            kAXApplicationShownNotification,
            kAXFocusedUIElementChangedNotification,
        ]
        // workaround: Protégé exhibits bugs when we subscribe to its kAXFocusedUIElementChangedNotification
        // we don't know what's happening; we hardcode this exception to make the app usable
        if app.bundleIdentifier == "edu.stanford.protege" {
            n.remove(at: 5)
        }
        return n
    }

    init(_ runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication
        super.init()
        addAndObserveWindows()
        kvObservers = [
            runningApplication.observe(\.isFinishedLaunching, options: [.new]) { [weak self] _, _ in self?.addAndObserveWindows() },
            runningApplication.observe(\.activationPolicy, options: [.new]) { [weak self] _, _ in self?.addAndObserveWindows() },
        ]
    }

    deinit {
        debugPrint("Deinit app", runningApplication.bundleIdentifier ?? "nil")
    }

    func addAndObserveWindows() {
        if runningApplication.isFinishedLaunching && runningApplication.activationPolicy != .prohibited {
            axUiElement = AXUIElementCreateApplication(runningApplication.processIdentifier)
            AXObserverCreate(runningApplication.processIdentifier, axObserverCallback, &axObserver)
            debugPrint("Adding app", runningApplication.processIdentifier, runningApplication.bundleIdentifier ?? "nil")
            observeEvents()
        }
    }

    func observeNewWindows() {
        if runningApplication.isFinishedLaunching && runningApplication.activationPolicy != .prohibited {
            retryUntilTimeout({ [weak self] in
                guard let self = self else { return }
                if let windows_ = try self.axUiElement!.windows(), windows_.count > 0 {
                    // bug in macOS: sometimes the OS returns multiple duplicate windows (e.g. Mail.app starting at login)
                    let windows = try Array(Set(windows_)).map {
                        (
                            $0,
                            try $0.isActualWindow(self.runningApplication.bundleIdentifier),
                            try $0.cgWindowId(),
                            try $0.title(),
                            try $0.isFullscreen(),
                            try $0.isMinimized(),
                            try $0.position()
                        )
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.addWindows(windows)
                    }
                }
            })
        }
    }

    private func addWindows(_ axWindows: [(AXUIElement, Bool, CGWindowID?, String?, Bool, Bool, CGPoint?)]) {
        let windows: [Window] = axWindows.compactMap { (axUiElement, isActualWindow, wid, axTitle, isFullscreen, isMinimized, position) in
            if let wid = wid, isActualWindow && Windows.list.firstIndexThatMatches(axUiElement, wid) == nil {
                return Window(axUiElement, self, wid, axTitle, isFullscreen, isMinimized, position)
            }
            return nil
        }
        Windows.list.insertAndScaleRecycledPool(windows, at: 0)
        if App.app.appIsBeingUsed {
            Windows.cycleFocusedWindowIndex(windows.count)
        }
        App.app.refreshOpenUi(windows)
    }

    private func observeEvents() {
        guard let axObserver = axObserver else { return }
        for notification in Application.notifications(runningApplication) {
            retryUntilTimeout({ [weak self] in
                guard let self = self else { return }
                try self.axUiElement!.subscribeToNotification(axObserver, notification, { [weak self] in
                    guard let self = self else { return }
                    // some apps have `isFinishedLaunching == true` but are actually not finished, and will return .cannotComplete
                    // we consider them ready when the first subscription succeeds, and list their windows again at that point
                    if !self.isReallyFinishedLaunching {
                        self.isReallyFinishedLaunching = true
                        self.observeNewWindows()
                    }
                }, self.runningApplication)
            })
        }
        CFRunLoopAddSource(BackgroundWork.accessibilityEventsThread.runLoop, AXObserverGetRunLoopSource(axObserver), .defaultMode)
    }
}
