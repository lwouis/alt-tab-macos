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
                    self.removeWindowslessAppWindow()
                }
                self.observeEventsIfEligible()
            },
        ]
    }

    deinit {
        Logger.debug { self.debugId() }
    }

    func removeWindowslessAppWindow() {
        if let windowlessAppWindow = (Windows.list.firstIndex { $0.isWindowlessApp == true && $0.application.pid == pid }) {
            Windows.list.remove(at: windowlessAppWindow)
            App.app.refreshOpenUi([], .refreshUiAfterExternalEvent)
        }
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

    func manuallyUpdateWindows() {
        AXUIElement.retryAxCallUntilTimeout(context: debugId(), pid: pid, callType: .updateAppWindows) { [weak self] in
            guard let self, let axUiElement = self.axUiElement else { return }
            var atLeastOneActualWindow = false
            let axWindows = try axUiElement.allWindows(self.pid)
            for axWindow in axWindows {
                let wid = try axWindow.cgWindowId()
                if let (title, role, subrole, isMinimized, isFullscreen) = try axWindow.windowAttributes() {
                    let size = try axWindow.size()
                    let level = wid.level()
                    if AXUIElement.isActualWindow(self, wid, level, title, subrole, role, size) {
                        let position = try axWindow.position()
                        atLeastOneActualWindow = true
                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }
                            if let window = (Windows.list.first { $0.isEqualRobust(axWindow, wid) }) {
                                window.title = window.bestEffortTitle(title)
                                window.size = size
                                window.isFullscreen = isFullscreen
                                window.isMinimized = isMinimized
                                window.position = position
                            } else {
                                let window = self.addWindow(axWindow, wid, title, isFullscreen, isMinimized, position, size)
                                App.app.refreshOpenUi([window], .refreshUiAfterExternalEvent)
                            }
                        }
                    }
                }
            }
            if (!atLeastOneActualWindow) {
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
            }
        }
    }

    func addWindowlessWindowIfNeeded() -> Window? {
        if runningApplication.activationPolicy == .regular && !runningApplication.isTerminated
               && (Windows.list.firstIndex { $0.application.pid == pid }) == nil {
            let window = Window(self)
            Windows.appendAndUpdateFocus(window)
            return window
        }
        return nil
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

    private func addWindow(_ axUiElement: AXUIElement, _ wid: CGWindowID, _ axTitle: String?, _ isFullscreen: Bool, _ isMinimized: Bool, _ position: CGPoint?, _ size: CGSize?) -> Window {
        let window = Window(axUiElement, self, wid, axTitle, isFullscreen, isMinimized, position, size)
        Windows.appendAndUpdateFocus(window)
        if App.app.appIsBeingUsed {
            Windows.cycleFocusedWindowIndex(1)
        }
        return window
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
}
