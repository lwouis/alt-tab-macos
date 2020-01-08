import Cocoa
import Foundation

class Window {
    var cgWindowId: CGWindowID
    var title: String
    var thumbnail: NSImage?
    var icon: NSImage?
    var isHidden: Bool
    var isMinimized: Bool
    var spaceId: CGSSpaceID?
    var spaceIndex: SpaceIndex?
    var axUiElement: AXUIElement
    var application: Application
    var axObserver: AXObserver?

    init(_ axUiElement: AXUIElement, _ application: Application) {
        // TODO: make a efficient batched AXUIElementCopyMultipleAttributeValues call once for each window, and store the values
        self.axUiElement = axUiElement
        self.application = application
        self.cgWindowId = axUiElement.cgWindowId()
        self.icon = application.runningApplication.icon
        self.isHidden = application.runningApplication.isHidden
        self.isMinimized = axUiElement.isMinimized()
        self.spaceId = Spaces.currentSpaceId
        self.spaceIndex = Spaces.currentSpaceIndex
        self.title = Window.bestEffortTitle(axUiElement, cgWindowId, application)
        debugPrint("Adding window: " + title, application.runningApplication.bundleIdentifier, Spaces.currentSpaceId, Spaces.currentSpaceIndex)
        observeEvents()
    }

    private func observeEvents() {
        AXObserverCreate(application.runningApplication.processIdentifier, axObserverWindowCallback, &axObserver)
        guard let axObserver = axObserver else { return }
        AXObserverAddNotification(axObserver, axUiElement, kAXUIElementDestroyedNotification as CFString, nil)
        AXObserverAddNotification(axObserver, axUiElement, kAXTitleChangedNotification as CFString, nil)
        AXObserverAddNotification(axObserver, axUiElement, kAXWindowMiniaturizedNotification as CFString, nil)
        AXObserverAddNotification(axObserver, axUiElement, kAXWindowDeminiaturizedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
    }

    func refreshThumbnail() {
        guard let cgImage = cgWindowId.screenshot() else { return }
        thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func focus() {
        // implementation notes: the following sequence of actions repeats some calls. This is necessary for
        // minimized windows on other spaces, and focuses windows faster (e.g. the Security & Privacy window)
        // macOS bug: when switching to a System Preferences window in another space, it switches to that space,
        // but quickly switches back to another window in that space
        // You can reproduce this buggy behaviour by clicking on the dock icon, proving it's an OS bug
        DispatchQueues.focusActions.async {
            var elementConnection = UInt32(0)
            CGSGetWindowOwner(cgsMainConnectionId, self.cgWindowId, &elementConnection)
            var psn = ProcessSerialNumber()
            CGSGetConnectionPSN(elementConnection, &psn)
            AXUIElementPerformAction(self.axUiElement, kAXRaiseAction as CFString)
            self.makeKeyWindow(psn)
            _SLPSSetFrontProcessWithOptions(&psn, self.cgWindowId, .userGenerated)
            self.makeKeyWindow(psn)
            AXUIElementPerformAction(self.axUiElement, kAXRaiseAction as CFString)
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

func axObserverWindowCallback(observer: AXObserver, element: AXUIElement, notificationName: CFString, _: UnsafeMutableRawPointer?) -> Void {
    let type = notificationName as String
    debugPrint("OS event: " + type, element.title())
    switch type {
        case kAXUIElementDestroyedNotification:
            guard let existingIndex = Windows.listRecentlyUsedFirst.firstIndexThatMatches(element) else { return }
            Windows.listRecentlyUsedFirst.remove(at: existingIndex)
            guard Windows.listRecentlyUsedFirst.count > 0 else { (App.shared as! App).hideUi(); return }
            Windows.moveFocusedWindowIndexAfterWindowDestroyedInBackground(existingIndex)
            (App.shared as! App).refreshOpenUi()
        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            guard let window = Windows.listRecentlyUsedFirst.firstWindowThatMatches(element) else { return }
            window.isMinimized = type == kAXWindowMiniaturizedNotification
            // TODO: find a better way to get thumbnail of the new window (when AltTab is triggered min/demin animation)
            window.refreshThumbnail()
            (App.shared as! App).refreshOpenUi()
        case kAXTitleChangedNotification:
            guard element.isActualWindow(),
                  let window = Windows.listRecentlyUsedFirst.firstWindowThatMatches(element),
                  let newTitle = window.axUiElement.title(),
                  newTitle != window.title else { return }
            window.title = newTitle
            (App.shared as! App).refreshOpenUi()
        default: return
    }
}
