import Cocoa
import Foundation

class OpenWindow {
    var target: AXUIElement?
    var ownerPid: pid_t?
    var cgId: CGWindowID
    var cgTitle: String
    lazy var thumbnail: NSImage = computeThumbnail()
    lazy var icon: NSImage = computeIcon()

    init(target: AXUIElement?, ownerPid: pid_t?, cgId: CGWindowID, cgTitle: String) {
        self.target = target
        self.ownerPid = ownerPid
        self.cgId = cgId
        self.cgTitle = cgTitle
    }

    func computeIcon() -> NSImage {
        return NSRunningApplication(processIdentifier: ownerPid!)!.icon!
    }

    func computeThumbnail() -> NSImage {
        let windowImage = CGWindowListCreateImage(.null, .optionIncludingWindow, cgId, [.boundsIgnoreFraming, .bestResolution])
        return NSImage(cgImage: windowImage!, size: NSSize(width: windowImage!.width, height: windowImage!.height))
    }

    func focus() {
        NSRunningApplication(processIdentifier: ownerPid!)!.activate(options: [.activateIgnoringOtherApps])
        AXUIElementPerformAction(target!, kAXRaiseAction as CFString)
    }
}

func computeDownscaledSize(_ image: NSImage) -> (Int, Int) {
    let imageRatio = image.size.width / image.size.height
    let thumbnailWidth = Int(floor(thumbnailMaxHeight * imageRatio))
    if thumbnailWidth <= Int(thumbnailMaxWidth) {
        return (thumbnailWidth, Int(thumbnailMaxHeight))
    } else {
        return (Int(thumbnailMaxWidth), Int(floor(thumbnailMaxWidth / imageRatio)))
    }
}

func cgMakeshiftId(_ window: NSDictionary) -> (String, pid_t, CGWindowID, String) {
    let cgId = window[kCGWindowNumber] as! CGWindowID
    let cgOwnerPid = window[kCGWindowOwnerPID] as! pid_t
    let cgBounds = window[kCGWindowBounds] as! [String: Int]
    let cgTitle = String(window[kCGWindowName] as! NSString)
    let cgMakeshiftId = String(cgBounds["X"]!) + String(cgBounds["Y"]!)
            + String(cgBounds["Width"]!) + String(cgBounds["Height"]!)
            + cgTitle
    return (cgMakeshiftId, cgOwnerPid, cgId, cgTitle)
}

func axMakeshiftId(_ element: AXUIElement) -> String {
    let titleAttribute = AXUIElementCopyAttributeValue(element, kAXTitleAttribute, String.self)!
    let pos = AXValueGetValue(element, kAXPositionAttribute, NSPoint(), AXValueType.cgPoint)!
    let size = AXValueGetValue(element, kAXSizeAttribute, NSSize(), AXValueType.cgSize)!
    return String(Int(pos.x)) + String(Int(pos.y))
            + String(Int(size.width)) + String(Int(size.height))
            + titleAttribute
}

func axWindows(_ cgOwnerPid: pid_t) -> [AXUIElement] {
    if let windows = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(cgOwnerPid), kAXWindowsAttribute, [AXUIElement].self) {
        return windows.filter {
            let hasTitle = !(AXUIElementCopyAttributeValue($0, kAXTitleAttribute, String.self) ?? "").isEmpty
            return hasTitle
        }
    }
    return []
}

func cgWindows() -> [NSDictionary] {
    let windows = CGWindowListCopyWindowInfo([.excludeDesktopElements, .optionOnScreenOnly], kCGNullWindowID) as! [NSDictionary]
    return windows.filter {
        let isWindowNotMenubarOrOthers = $0[kCGWindowLayer] as? Int == 0
        let hasTitle = !(($0[kCGWindowName] as? String ?? "").isEmpty)
        return isWindowNotMenubarOrOthers && hasTitle
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
