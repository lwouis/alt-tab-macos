import Cocoa
import ApplicationServices.HIServices.AXNotificationConstants

class Application: NSObject {
    // kvObservers should be listed first, so it gets deinit'ed first; otherwise it can crash
    var kvObservers: [NSKeyValueObservation]?
    var runningApplication: NSRunningApplication
    var axUiElement: AXUIElement?
    var axObserver: AXObserver?
    var isReallyFinishedLaunching = false
    var localizedName: String?
    var bundleIdentifier: String?
    var bundleURL: URL?
    var executableURL: URL?
    var pid: pid_t
    var isHidden: Bool
    var hasBeenActiveOnce: Bool
    var icon: CGImage?
    var dockLabel: String?
    var focusedWindow: Window? = nil
    var alreadyRequestedToQuit = false

    func debugId() -> String {
        return "(pid:\(pid) \(bundleIdentifier ?? bundleURL?.absoluteString ?? executableURL?.absoluteString ?? localizedName))"
    }

    static let notifications = [
        kAXApplicationActivatedNotification,
        kAXMainWindowChangedNotification,
        kAXFocusedWindowChangedNotification,
        kAXWindowCreatedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]

    private static let appIconPadding: CGFloat = {
        // Tahoe redesigned app icons. Keeping their rounded look, and reducing their size; we trim that padding
        if #available(macOS 26.0, *) {
            return 84
        }
        // Big Sur redesigned app icons. A big change from square icons to rounded icons, and reducing their size; we trim that padding
        if #available(macOS 11.0, *) {
            return 24
        }
        return 0
    }()

    static func appIconWithoutPadding(_ icon: NSImage?) -> CGImage? {
        guard let icon else { return nil }
        let finalWidth = max(ThumbnailsPanel.maxPossibleAppIconSize.width, ThumbnailsPanel.maxPossibleAppIconSize.height)
        let padding = appIconPadding * (finalWidth / (1024 - appIconPadding * 2))
        let sourceWidth = finalWidth + padding * 2
        guard let context = CGContext(data: nil, width: Int(finalWidth), height: Int(finalWidth), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        let drawRect = CGRect(x: -padding, y: -padding, width: sourceWidth, height: sourceWidth)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0, respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    init(_ runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication
        pid = runningApplication.processIdentifier
        isHidden = runningApplication.isHidden
        hasBeenActiveOnce = runningApplication.isActive
        icon = Application.appIconWithoutPadding(runningApplication.icon)
        localizedName = runningApplication.localizedName
        bundleIdentifier = runningApplication.bundleIdentifier
        bundleURL = runningApplication.bundleURL
        executableURL = runningApplication.executableURL
        super.init()
        Logger.debug { self.debugId() }
        observeEventsIfEligible()
        kvObservers = [
            runningApplication.observe(\.isFinishedLaunching, options: [.new]) { [weak self] _, _ in
                guard let self else { return }
                self.observeEventsIfEligible()
            },
            runningApplication.observe(\.activationPolicy, options: [.new]) { [weak self] _, _ in
                guard let self else { return }
                if self.runningApplication.activationPolicy != .regular {
                    self.removeWindowlessAppWindow()
                }
                self.observeEventsIfEligible()
            },
        ]
    }

    deinit {
        Logger.debug { self.debugId() }
    }


    func observeEventsIfEligible() {
        if runningApplication.activationPolicy != .prohibited && !isReallyFinishedLaunching {
            if axUiElement == nil {
                axUiElement = AXUIElementCreateApplication(pid)
            }
            if axObserver == nil {
                AXObserverCreate(pid, AccessibilityEvents.axObserverCallback, &axObserver)
            }
            observeEvents()
        }
    }

    private func observeEvents() {
        guard let axObserver else { return }
        AXUIElement.retryAxCallUntilTimeout(context: debugId(), pid: pid, callType: .subscribeToAppNotification) { [weak self] in
            guard let self, !self.isReallyFinishedLaunching else { return }
            if try self.axUiElement!.subscribeToNotification(axObserver, Application.notifications.first!) {
                Logger.debug { "Subscribed to app: \(self.debugId())" }
                if !self.isReallyFinishedLaunching {
                    // some apps have `isFinishedLaunching == true` but are actually not finished, and will return .cannotComplete
                    // we consider them ready when the first subscription succeeds
                    // windows opened before that point won't send a notification, so check those windows manually here
                    self.isReallyFinishedLaunching = true
                    for notification in Application.notifications.dropFirst() {
                        AXUIElement.retryAxCallUntilTimeout(context: self.debugId(), pid: self.pid, callType: .subscribeToAppNotification) { [weak self] in
                            try self?.axUiElement!.subscribeToNotification(axObserver, notification)
                        }
                    }
                    DispatchQueue.main.async { [weak self] in
                        self?.manuallyUpdateWindows()
                    }
                }
            }
        }
        CFRunLoopAddSource(BackgroundWork.accessibilityEventsThread.runLoop, AXObserverGetRunLoopSource(axObserver), .commonModes)
    }

    func manuallyUpdateWindows() {
        AXUIElement.retryAxCallUntilTimeout(context: debugId(), pid: pid, callType: .updateAppWindows) { [weak self] in
            guard let self, let axUiElement = self.axUiElement else { return }
            let axWindows = try axUiElement.allWindows(self.pid)
            guard !axWindows.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.addWindowlessWindowIfNeeded() != nil {
                        App.app.refreshOpenUi([], .refreshUiAfterExternalEvent)
                    }
                }
                // workaround: some apps launch but take a while to create their window(s)
                // initial windows don't trigger a windowCreated notification, so we won't get notified
                // it's very unlikely an app would launch with no initial window
                // so we retry until timeout, in those rare cases (e.g. Bear.app)
                // we only do this for regular, active app, to avoid wasting CPU, with the trade-off of maybe missing some windows
                if self.runningApplication.isActive && self.runningApplication.activationPolicy == .regular {
                    throw AxError.runtimeError
                }
                return
            }
            for axWindow in axWindows {
                let wid = try axWindow.cgWindowId()
                guard wid != 0 else { continue } // some bogus "windows" have wid 0
                try AccessibilityEvents.handleEventWindow(kAXWindowCreatedNotification, wid, pid, axWindow)
            }
        }
    }

    @discardableResult
    func addWindowlessWindowIfNeeded() -> Window? {
        guard runningApplication.activationPolicy == .regular && !runningApplication.isTerminated
               && !(Windows.list.contains { $0.application.pid == pid }) else { return nil }
        let window = Window(self)
        Windows.appendWindow(window)
        focusedWindow = nil
        App.app.refreshOpenUi([], .refreshUiAfterExternalEvent)
        return window
    }

    func removeWindowlessAppWindow() {
        guard let windowlessAppWindow = (Windows.list.first { $0.isWindowlessApp == true && $0.application.pid == pid }) else { return }
        Windows.removeWindows([windowlessAppWindow], false)
        App.app.refreshOpenUi([], .refreshUiAfterExternalEvent)
    }

    func hideOrShow() {
        if runningApplication.isHidden {
            runningApplication.unhide()
        } else {
            runningApplication.hide()
        }
    }

    func canBeQuit() -> Bool {
        return bundleIdentifier != "com.apple.finder" || Preferences.finderShowsQuitMenuItem
    }

    func quit() {
        // only let power users quit Finder if they opt-in
        if !canBeQuit() {
            NSSound.beep()
            return
        }
        if alreadyRequestedToQuit {
            runningApplication.forceTerminate()
        } else {
            runningApplication.terminate()
            alreadyRequestedToQuit = true
        }
    }
}
