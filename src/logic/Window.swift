import Cocoa

class Window {
    var cgWindowId: CGWindowID
    var title: String
    var thumbnail: NSImage?
    var icon: NSImage?
    var shouldShowTheUser = true
    var isTabbed: Bool
    var isHidden: Bool
    var isMinimized: Bool
    var isOnAllSpaces: Bool
    var spaceId: CGSSpaceID?
    var spaceIndex: SpaceIndex?
    var axUiElement: AXUIElement
    var application: Application
    var axObserver: AXObserver?
    var row: Int?

    static let notifications = [
        kAXUIElementDestroyedNotification,
        kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXWindowResizedNotification,
    ]

    static func stopSubscriptionRetries(_ notification: String, _ cgWindowId: CGWindowID) {
        Windows.windowsInSubscriptionRetryLoop.removeAll { (subscription: String) -> Bool in
            subscription == String(cgWindowId) + notification
        }
    }

    init(_ axUiElement: AXUIElement, _ application: Application) {
        // TODO: make a efficient batched AXUIElementCopyMultipleAttributeValues call once for each window, and store the values
        self.axUiElement = axUiElement
        self.application = application
        self.cgWindowId = axUiElement.cgWindowId()
        self.icon = application.runningApplication.icon
        self.isTabbed = application.axUiElement!.isTabbed(axUiElement)
        self.isHidden = application.runningApplication.isHidden
        self.isMinimized = axUiElement.isMinimized()
        self.spaceId = Spaces.currentSpaceId
        self.spaceIndex = Spaces.currentSpaceIndex
        self.isOnAllSpaces = false
        self.title = Window.bestEffortTitle(axUiElement, cgWindowId, application)
        debugPrint("Adding window", cgWindowId, title, application.runningApplication.bundleIdentifier ?? "nil", Spaces.currentSpaceId, Spaces.currentSpaceIndex)
        observeEvents()
    }

    deinit {
        // some windows never finish launching; subscription retries should be stopped to avoid infinite loops
        Window.notifications.forEach { Window.stopSubscriptionRetries($0, cgWindowId) }
    }

    private func observeEvents() {
        AXObserverCreate(application.runningApplication.processIdentifier, axObserverCallback, &axObserver)
        guard let axObserver = axObserver else { return }
        for notification in Window.notifications {
            Windows.windowsInSubscriptionRetryLoop.append(String(cgWindowId) + String(notification))
            axUiElement.subscribeWithRetry(axObserver, notification, nil, nil, nil, cgWindowId)
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
    }

    func refreshThumbnail() {
        guard let cgImage = cgWindowId.screenshot() else { return }
        thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func close() {
        DispatchQueues.accessibilityCommands.async { [weak self] in
            self?.axUiElement.closeWindow()
        }
    }

    func minDemin() {
        DispatchQueues.accessibilityCommands.async { [weak self] in
            self?.axUiElement.minDeminWindow()
        }
    }

    func quitApp() {
        DispatchQueues.accessibilityCommands.async { [weak self] in
            self?.application.runningApplication.terminate()
        }
    }

    func hideShowApp() {
        DispatchQueues.accessibilityCommands.async { [weak self] in
            guard let self = self else { return }
            if self.application.runningApplication.isHidden {
                self.application.runningApplication.unhide()
            } else {
                self.application.runningApplication.hide()
            }
        }
    }

    func focus() {
        // macOS bug: when switching to a System Preferences window in another space, it switches to that space,
        // but quickly switches back to another window in that space
        // You can reproduce this buggy behaviour by clicking on the dock icon, proving it's an OS bug
        DispatchQueues.accessibilityCommands.async { [weak self] in
            guard let self = self else { return }
            var elementConnection = UInt32(0)
            CGSGetWindowOwner(cgsMainConnectionId, self.cgWindowId, &elementConnection)
            var psn = ProcessSerialNumber()
            CGSGetConnectionPSN(elementConnection, &psn)
            _SLPSSetFrontProcessWithOptions(&psn, self.cgWindowId, .userGenerated)
            self.makeKeyWindow(psn)
            self.axUiElement.focusWindow()
        }
    }

    // The following function was ported from https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468
    func makeKeyWindow(_ psn: ProcessSerialNumber) -> Void {
        var psn_ = psn
        var bytes1 = [UInt8](repeating: 0, count: 0xf8)
        bytes1[0x04] = 0xF8
        bytes1[0x08] = 0x01
        bytes1[0x3a] = 0x10
        var bytes2 = [UInt8](repeating: 0, count: 0xf8)
        bytes2[0x04] = 0xF8
        bytes2[0x08] = 0x02
        bytes2[0x3a] = 0x10
        memcpy(&bytes1[0x3c], &cgWindowId, MemoryLayout<UInt32>.size)
        memset(&bytes1[0x20], 0xFF, 0x10)
        memcpy(&bytes2[0x3c], &cgWindowId, MemoryLayout<UInt32>.size)
        memset(&bytes2[0x20], 0xFF, 0x10)
        SLPSPostEventRecordTo(&psn_, &(UnsafeMutablePointer(mutating: UnsafePointer<UInt8>(bytes1)).pointee))
        SLPSPostEventRecordTo(&psn_, &(UnsafeMutablePointer(mutating: UnsafePointer<UInt8>(bytes2)).pointee))
    }

    // for some windows (e.g. Slack), the AX API doesn't return a title; we try CG API; finally we resort to the app name
    static func bestEffortTitle(_ axUiElement: AXUIElement, _ cgWindowId: CGWindowID, _ application: Application) -> String {
        if let axTitle = axUiElement.title(), !axTitle.isEmpty {
            return axTitle
        }
        if let cgTitle = cgWindowId.title(), !cgTitle.isEmpty {
            return cgTitle
        }
        return application.runningApplication.localizedName ?? ""
    }
}
