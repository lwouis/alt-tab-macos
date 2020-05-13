import Cocoa

class Application: NSObject {
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
        if runningApplication.isFinishedLaunching {
            addAndObserveWindows()
        } else {
            runningApplication.addObserver(self, forKeyPath: "isFinishedLaunching", options: [.new], context: nil)
        }
    }

    deinit {
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
            // bug in macOS: sometimes the OS returns multiple duplicate windows (e.g. Mail.app starting at login)
            let actualWindows = Array(Set(windows.filter { Windows.list.firstIndexThatMatches($0) == nil }))
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
        for notification in Application.notifications(runningApplication) {
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
