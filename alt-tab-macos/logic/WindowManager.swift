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
        let windowImage = CGWindowListCreateImage(.null, .optionIncludingWindow, cgId, [.boundsIgnoreFraming, .bestResolution])
        return NSImage(cgImage: windowImage!, size: NSSize(width: windowImage!.width, height: windowImage!.height))
    }

    func focus() {
        if let app = NSRunningApplication(processIdentifier: ownerPid!) {
            app.activate(options: [.activateIgnoringOtherApps])
            AXUIElementPerformAction(target!, kAXRaiseAction as CFString)
        }
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

func axWindows(_ cgOwnerPid: pid_t) -> [AXUIElement] {
    if let windows = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(cgOwnerPid), kAXWindowsAttribute, [AXUIElement].self) {
        return windows.filter {
            // workaround: some apps like chrome use a window to implement the search popover
            let windowBounds = AXValueGetValue($0, kAXSizeAttribute, NSSize(), .cgSize)!
            let isReasonablyBig = windowBounds.width > Preferences.minimumWindowSize && windowBounds.height > Preferences.minimumWindowSize
            return isReasonablyBig
        }
    }
    return []
}

func cgWindows() -> [NSDictionary] {
    let windows = CGWindowListCopyWindowInfo([.excludeDesktopElements, .optionOnScreenOnly], kCGNullWindowID) as! [NSDictionary]
    return windows.filter {
        // workaround: filtering this criteria seems to remove non-windows UI elements
        let isWindowNotMenubarOrOthers = $0[kCGWindowLayer] as? Int == 0
        let windowBounds = CGRect(dictionaryRepresentation: $0[kCGWindowBounds] as! NSDictionary)!
        // workaround: some apps like chrome use a window to implement the search popover
        let isReasonablyBig = windowBounds.width > Preferences.minimumWindowSize && windowBounds.height > Preferences.minimumWindowSize
        return isWindowNotMenubarOrOthers && isReasonablyBig
    }
}

func AXUIElementCopyAttributeValue<T>(_ element: AXUIElement, _ attribute: String, _ type: T.Type) -> T? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    if result == .success, let typedValue = value as? T {
        return typedValue
    }
    return nil
}

func AXValueGetValue<T>(_ element: AXUIElement, _ attribute: String, _ target: T, _ type: AXValueType) -> T? {
    if let a = AXUIElementCopyAttributeValue(element, attribute, AXValue.self) {
        var value = target
        AXValueGetValue(a, type, &value)
        return value
    }
    return nil
}
