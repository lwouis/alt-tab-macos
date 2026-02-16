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
    var debugId: String

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

    /// Converting NSImage to CGImage may seem simple, but it's actually very tricky. Lots of time has been put to make it work robustly
    /// The RunningApplication.icon can have store bitmaps or vectors. We have to rasterize into pixels. This is not easy as there are many APIs:
    ///   * icon.cgImage(forProposedRect:) > context.draw -> only API which works
    ///   * icon.cgImage(forProposedRect:) > cgImage.draw -> returns nil for some users (could never reproduce it locally)
    ///   * icon.draw() -> returns nil for some users (could never reproduce it locally)
    ///   * icon.bestRepresentation() > bestRep.draw(in:) -> returns nil for some users (could never reproduce it locally)
    /// MacOS Big Sur also introduced a constant padding around app icons. It was later increased with Tahoe. We have to crop it
    static func appIconWithoutPadding(_ icon: NSImage?) -> CGImage? {
        guard let icon else { return nil }
        let finalWidth = max(TilesPanel.maxPossibleAppIconSize.width, TilesPanel.maxPossibleAppIconSize.height)
        // we hardcode cropping values based on a reference 1024 icon, and depending on the macOS version
        let padding = appIconPadding * (finalWidth / (1024 - appIconPadding * 2))
        // we need a bigger image size, since we'll crop to reach finalWidth
        let sourceWidth = finalWidth + padding * 2
        // we ask the NSImage for the closest image it has to our desired size. It's likely to return a 1024x1024 or 512x512 image; whichever is closest
        var proposedRect = CGRect(origin: .zero, size: NSSize(width: sourceWidth, height: sourceWidth))
        // this convoluted style avoids a crash on macOS 10.13 (see #5255)
        let hints : [NSImageRep.HintKey : NSNumber] = [.interpolation : NSNumber(value: NSImageInterpolation.high.rawValue)]
        guard let cgImage = icon.cgImage(forProposedRect: &proposedRect, context: nil, hints: hints) else { return nil }
        // we have to crop this image; let's scale our intended padding, given the image size we got
        let paddingScaled = padding * (CGFloat(cgImage.width) / sourceWidth)
        guard let image = cgImage.cropping(to: CGRect(x: paddingScaled, y: paddingScaled, width: CGFloat(cgImage.width) - paddingScaled * 2, height: CGFloat(cgImage.height) - paddingScaled * 2).integral),
              let context = CGContext(data: nil, width: Int(finalWidth), height: Int(finalWidth), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little).rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: NSSize(width: finalWidth, height: finalWidth)))
        return context.makeImage()
    }

    init(_ runningApplication: NSRunningApplication) {
        self.runningApplication = runningApplication
        pid = runningApplication.processIdentifier
        isHidden = runningApplication.isHidden
        hasBeenActiveOnce = runningApplication.isActive
        localizedName = runningApplication.localizedName
        bundleIdentifier = runningApplication.bundleIdentifier
        bundleURL = runningApplication.bundleURL
        executableURL = runningApplication.executableURL
        debugId = "(pid:\(pid) \(bundleIdentifier ?? bundleURL?.absoluteString ?? executableURL?.absoluteString ?? localizedName))"
        super.init()
        BackgroundWork.screenshotsQueue.addOperation { [weak self] in
            guard let self else { return }
            let r = Application.appIconWithoutPadding(runningApplication.icon)
            DispatchQueue.main.async { [weak self] in
                self?.icon = r
            }
        }
        Logger.info { self.debugId }
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
        Logger.info { self.debugId }
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
        AXUIElement.retryAxCallUntilTimeout(context: debugId, pid: pid, callType: .subscribeToAppNotification) { [weak self] in
            guard let self, !self.isReallyFinishedLaunching else { return }
            if try self.axUiElement!.subscribeToNotification(axObserver, Application.notifications.first!) {
                Logger.debug { "Subscribed to app: \(self.debugId)" }
                if !self.isReallyFinishedLaunching {
                    // some apps have `isFinishedLaunching == true` but are actually not finished, and will return .cannotComplete
                    // we consider them ready when the first subscription succeeds
                    // windows opened before that point won't send a notification, so check those windows manually here
                    self.isReallyFinishedLaunching = true
                    for notification in Application.notifications.dropFirst() {
                        AXUIElement.retryAxCallUntilTimeout(context: self.debugId, pid: self.pid, callType: .subscribeToAppNotification) { [weak self] in
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
        AXUIElement.retryAxCallUntilTimeout(context: debugId, pid: pid, callType: .updateAppWindows) { [weak self] in
            guard let self, let axUiElement = self.axUiElement else { return }
            let axWindows = try axUiElement.allWindows(self.pid)
            guard !axWindows.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.addWindowlessWindowIfNeeded() != nil {
                        App.app.refreshOpenUiAfterExternalEvent([])
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
                guard let wid = try? axWindow.cgWindowId() else { continue }
                AXUIElement.retryAxCallUntilTimeout(context: debugId, pid: pid, wid: wid, callType: .updateWindowFromManualDiscovery) { [weak self] in
                    try self?.manuallyUpdateWindow(axWindow, wid)
                }
            }
        }
    }

    func manuallyUpdateWindow(_ axWindow: AXUIElement, _ wid: CGWindowID) throws {
        guard wid != 0 && wid != App.app.tilesPanel.windowNumber else { return } // some bogus "windows" have wid 0
        let level = wid.level()
        let a = try axWindow.attributes([kAXTitleAttribute, kAXSubroleAttribute, kAXRoleAttribute, kAXSizeAttribute, kAXPositionAttribute, kAXFullscreenAttribute, kAXMinimizedAttribute])
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let findOrCreate = Windows.findOrCreate(axWindow, wid, self, level, a.title, a.subrole, a.role, a.size, a.position, a.isFullscreen, a.isMinimized)
            guard let window = findOrCreate.0 else { return }
            if findOrCreate.1 {
                Logger.info { "manuallyUpdateWindows found a new window:\(window.debugId)" }
                App.app.refreshOpenUiAfterExternalEvent([window])
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
        App.app.refreshOpenUiAfterExternalEvent([])
        return window
    }

    func removeWindowlessAppWindow() {
        guard let windowlessAppWindow = (Windows.list.first { $0.isWindowlessApp == true && $0.application.pid == pid }) else { return }
        Windows.removeWindows([windowlessAppWindow], false)
        App.app.refreshOpenUiAfterExternalEvent([])
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
