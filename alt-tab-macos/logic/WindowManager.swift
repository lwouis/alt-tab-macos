import Cocoa
import Foundation

class OpenWindow {
    var target: AXUIElement?
    var ownerPid: pid_t?
    var cgId: CGWindowID
    var cgTitle: String
    lazy var thumbnail: NSImage = computeThumbnail()
    lazy var icon: NSImage? = computeIcon()

    init(_ target: AXUIElement?, _ ownerPid: pid_t?, _ cgId: CGWindowID, _ cgTitle: String) {
        self.target = target
        self.ownerPid = ownerPid
        self.cgId = cgId
        self.cgTitle = cgTitle
    }

    func computeIcon() -> NSImage? {
        return NSRunningApplication(processIdentifier: ownerPid!)?.icon
    }

    func computeThumbnail() -> NSImage {
        let windowImage = CoreGraphicsApis.image(cgId)
        return NSImage(cgImage: windowImage!, size: NSSize(width: windowImage!.width, height: windowImage!.height))
    }

    func focus() {
        if let app = NSRunningApplication(processIdentifier: ownerPid!) {
            app.activate(options: [.activateIgnoringOtherApps])
            AccessibilityApis.focus(target!)
        }
    }

    func moveTo(_ position: WindowPosition) {
        let screenSize = Screen.screenContaining(AccessibilityApis.rect(target!))!.visibleFrame.size
        let screenMidX = screenSize.width / 2
        AccessibilityApis.setAttribute(target!, NSSize(width: screenMidX, height: screenSize.height), kAXSizeAttribute, .cgSize)
        AccessibilityApis.setAttribute(target!, NSPoint(x: position == .leftHalf ? 0 : screenMidX, y: 0), kAXPositionAttribute, .cgPoint)
    }
}

func computeDownscaledSize(_ image: NSImage, _ screen: NSScreen) -> (Int, Int) {
    let imageRatio = image.size.width / image.size.height
    let thumbnailMaxSize = Screen.thumbnailMaxSize(screen)
    let thumbnailWidth = Int(floor(thumbnailMaxSize.height * imageRatio))
    if thumbnailWidth <= Int(thumbnailMaxSize.width) {
        return (thumbnailWidth, Int(thumbnailMaxSize.height))
    } else {
        return (Int(thumbnailMaxSize.width), Int(floor(thumbnailMaxSize.width / imageRatio)))
    }
}
