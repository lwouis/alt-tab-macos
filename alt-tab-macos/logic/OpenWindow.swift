import Cocoa
import Foundation

class OpenWindow {
    var cgWindow: NSDictionary
    var ownerPid: Int32
    var cgId: CGWindowID
    var cgTitle: String
    var cgRect: CGRect
    var thumbnail: NSImage?
    var icon: NSImage?
    var app: NSRunningApplication?
    var axWindow: AXUIElement?
    var isMinimized: Bool

    init(_ cgWindow: NSDictionary, _ cgId: CGWindowID, _ isMinimized: Bool, _ axWindow: AXUIElement?) {
        self.cgWindow = cgWindow
        self.cgId = cgId
        self.ownerPid = CoreGraphicsApis.value(cgWindow, kCGWindowOwnerPID, Int32(0))
        let cgTitle = CoreGraphicsApis.value(cgWindow, kCGWindowName, "")
        let cgOwnerName = CoreGraphicsApis.value(cgWindow, kCGWindowOwnerName, "")
        self.cgTitle = cgTitle.isEmpty ? cgOwnerName : cgTitle
        self.app = NSRunningApplication(processIdentifier: ownerPid)
        self.icon = self.app?.icon
        self.cgRect = CGRect(dictionaryRepresentation: cgWindow[kCGWindowBounds] as! NSDictionary)!
        let cgImage = PreferredApis.windowScreenshot(cgId, .CGSHWCaptureWindowList)
        self.thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        self.axWindow = axWindow
        self.isMinimized = isMinimized
    }

    func focus() {
        if axWindow == nil {
            axWindow = AccessibilityApis.windowThatMatchCgWindow(ownerPid, cgId)
        }
        if axWindow != nil {
            PreferredApis.focusWindow(axWindow!, cgId, nil, ._SLPSSetFrontProcessWithOptions)
        }
    }
}
