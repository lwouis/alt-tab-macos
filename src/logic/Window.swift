import Cocoa

class Window {
    var cgWindowId = CGWindowID.max
    var lastFocusOrder = Int.zero
    var title: String!
    var thumbnail: NSImage?
    var thumbnailFullSize: NSSize?
    var icon: NSImage? { get { application.icon } }
    var shouldShowTheUser = true
    var isTabbed: Bool = false
    var isHidden: Bool { get { application.isHidden } }
    var dockLabel: Int? { get { application.dockLabel.flatMap { Int($0) } } }
    var isFullscreen = false
    var isMinimized = false
    var isOnAllSpaces = false
    var isWindowlessApp = false
    var position: CGPoint?
    var size: CGSize?
    var spaceId = CGSSpaceID.max
    var spaceIndex = SpaceIndex.max
    var axUiElement: AXUIElement!
    var application: Application
    var axObserver: AXObserver?
    var row: Int?

    static let notifications = [
        kAXUIElementDestroyedNotification,
        kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXWindowResizedNotification,
        kAXWindowMovedNotification,
    ]

    init(_ axUiElement: AXUIElement, _ application: Application, _ wid: CGWindowID, _ axTitle: String?, _ isFullscreen: Bool, _ isMinimized: Bool, _ position: CGPoint?, _ size: CGSize?) {
        // TODO: make a efficient batched AXUIElementCopyMultipleAttributeValues call once for each window, and store the values
        self.axUiElement = axUiElement
        self.application = application
        self.cgWindowId = wid
        self.spaceId = Spaces.currentSpaceId
        self.spaceIndex = Spaces.currentSpaceIndex
        self.isFullscreen = isFullscreen
        self.isMinimized = isMinimized
        self.position = position
        self.size = size
        self.title = bestEffortTitle(axTitle)
        if !Preferences.hideThumbnails {
            refreshThumbnail()
        }
        application.removeWindowslessAppWindow()
        debugPrint("Adding window", cgWindowId, title ?? "nil", application.runningApplication.bundleIdentifier ?? "nil")
        observeEvents()
    }

    init(_ application: Application) {
        isWindowlessApp = true
        self.application = application
        self.title = application.runningApplication.localizedName
        debugPrint("Adding app-window", title ?? "nil", application.runningApplication.bundleIdentifier ?? "nil")
    }

    deinit {
        debugPrint("Deinit window", title ?? "nil", application.runningApplication.bundleIdentifier ?? "nil")
    }

    func isEqualRobust(_ otherWindowAxUiElement: AXUIElement, _ otherWindowWid: CGWindowID?) -> Bool {
        // the window can be deallocated by the OS, in which case its `CGWindowID` will be `-1`
        // we check for equality both on the AXUIElement, and the CGWindowID, in order to catch all scenarios
        return otherWindowAxUiElement == axUiElement || (cgWindowId != -1 && otherWindowWid == cgWindowId)
    }

    private func observeEvents() {
        AXObserverCreate(application.pid, axObserverCallback, &axObserver)
        guard let axObserver = axObserver else { return }
        for notification in Window.notifications {
            retryAxCallUntilTimeout { [weak self] in
                guard let self = self else { return }
                try self.axUiElement.subscribeToNotification(axObserver, notification, nil, nil, self.cgWindowId)
            }
        }
        CFRunLoopAddSource(BackgroundWork.accessibilityEventsThread.runLoop, AXObserverGetRunLoopSource(axObserver), .defaultMode)
    }

    func refreshThumbnail() {
        guard let cgImage = cgWindowId.screenshot() else { return }
        thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        thumbnailFullSize = thumbnail!.size
    }

    func close() {
        if isWindowlessApp { return }
        BackgroundWork.accessibilityCommandsQueue.asyncWithCap { [weak self] in
            guard let self = self else { return }
            if self.isFullscreen {
                self.axUiElement.setAttribute(kAXFullscreenAttribute, false)
            }
            if let closeButton_ = try? self.axUiElement.closeButton() {
                closeButton_.performAction(kAXPressAction)
            }
        }
    }

    func minDemin() {
        if isWindowlessApp { return }
        BackgroundWork.accessibilityCommandsQueue.asyncWithCap { [weak self] in
            guard let self = self else { return }
            if self.isFullscreen {
                self.axUiElement.setAttribute(kAXFullscreenAttribute, false)
                // minimizing is ignored if sent immediatly; we wait for the de-fullscreen animation to be over
                BackgroundWork.accessibilityCommandsQueue.asyncWithCap(.now() + .seconds(1)) { [weak self] in
                    guard let self = self else { return }
                    self.axUiElement.setAttribute(kAXMinimizedAttribute, true)
                }
            } else {
                self.axUiElement.setAttribute(kAXMinimizedAttribute, !self.isMinimized)
            }
        }
    }

    func toggleFullscreen() {
        if isWindowlessApp { return }
        BackgroundWork.accessibilityCommandsQueue.asyncWithCap { [weak self] in
            guard let self = self else { return }
            self.axUiElement.setAttribute(kAXFullscreenAttribute, !self.isFullscreen)
        }
    }

    func quitApp() {
        // prevent users from quitting Finder
        if application.runningApplication.bundleIdentifier == "com.apple.finder" { return }
        BackgroundWork.accessibilityCommandsQueue.asyncWithCap { [weak self] in
            self?.application.runningApplication.terminate()
        }
    }

    func hideShowApp() {
        BackgroundWork.accessibilityCommandsQueue.asyncWithCap { [weak self] in
            guard let self = self else { return }
            if self.application.runningApplication.isHidden {
                self.application.runningApplication.unhide()
            } else {
                self.application.runningApplication.hide()
            }
        }
    }

    func focus() {
        if isWindowlessApp {
            if let bundleID = application.runningApplication.bundleIdentifier {
                NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleID, additionalEventParamDescriptor: nil, launchIdentifier: nil)
            } else {
                application.runningApplication.activate(options: .activateIgnoringOtherApps)
            }
        } else {
            // macOS bug: when switching to a System Preferences window in another space, it switches to that space,
            // but quickly switches back to another window in that space
            // You can reproduce this buggy behaviour by clicking on the dock icon, proving it's an OS bug
            BackgroundWork.accessibilityCommandsQueue.asyncWithCap { [weak self] in
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
        [bytes1, bytes2].forEach { bytes in
            _ = bytes.withUnsafeBufferPointer() { pointer in
                SLPSPostEventRecordTo(&psn_, &UnsafeMutablePointer(mutating: pointer.baseAddress)!.pointee)
            }
        }
    }

    // for some windows (e.g. Slack), the AX API doesn't return a title; we try CG API; finally we resort to the app name
    func bestEffortTitle(_ axTitle: String?) -> String {
        if let axTitle = axTitle, !axTitle.isEmpty {
            return axTitle
        }
        if let cgTitle = cgWindowId.title(), !cgTitle.isEmpty {
            return cgTitle
        }
        return application.runningApplication.localizedName ?? ""
    }

    func updatesWindowSpace() {
        // macOS bug: if you tab a window, then move the tab group to another space, other tabs from the tab group will stay on the current space
        // you can use the Dock to focus one of the other tabs and it will teleport that tab in the current space, proving that it's a macOS bug
        // note: for some reason, it behaves differently if you minimize the tab group after moving it to another space
        let spaceIds = cgWindowId.spaces()
        if spaceIds.count == 1 {
            spaceId = spaceIds.first!
            spaceIndex = Spaces.idsAndIndexes.first { $0.0 == spaceIds.first! }!.1
        } else if spaceIds.count > 1 {
            spaceId = Spaces.currentSpaceId
            spaceIndex = Spaces.currentSpaceIndex
            isOnAllSpaces = true
        }
    }

    func isOnScreen(_ screen: NSScreen) -> Bool {
        if NSScreen.screensHaveSeparateSpaces {
            if let screenUuid = screen.uuid(), let screenSpaces = Spaces.screenSpacesMap[screenUuid] {
                return screenSpaces.contains { $0 == spaceId }
            }
        } else {
            if let topLeftCorner = position, let size = size {
                var screenFrameInQuartzCoordinates = screen.frame
                screenFrameInQuartzCoordinates.origin.y = NSMaxY(NSScreen.screens[0].frame) - NSMaxY(screen.frame)
                let windowRect = CGRect(origin: topLeftCorner, size: size)
                return windowRect.intersects(screenFrameInQuartzCoordinates) && Spaces.visibleSpaces.contains(spaceId)
            }
        }
        return true
    }
}

