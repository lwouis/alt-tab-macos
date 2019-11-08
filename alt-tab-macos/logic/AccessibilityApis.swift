import Cocoa
import Foundation

class AccessibilityApis {
    static func windows(_ cgOwnerPid: pid_t) -> [AXUIElement] {
        if let windows = attribute(AXUIElementCreateApplication(cgOwnerPid), kAXWindowsAttribute, [AXUIElement].self) {
            return windows.filter {
                // workaround: some apps like chrome use a window to implement the search popover
                let windowBounds = value($0, kAXSizeAttribute, NSSize(), .cgSize)!
                let isReasonablyBig = windowBounds.width > Preferences.minimumWindowSize && windowBounds.height > Preferences.minimumWindowSize
                return isReasonablyBig
            }
        }
        return []
    }

    static func rect(_ element: AXUIElement) -> CGRect {
        let sizeBefore = value(element, kAXSizeAttribute, NSSize(), .cgSize)!
        let positionBefore = value(element, kAXPositionAttribute, NSPoint(), .cgPoint)!
        return CGRect(x: positionBefore.x, y: positionBefore.y, width: sizeBefore.width, height: sizeBefore.height)
    }

    static func focus(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    private static func attribute<T>(_ element: AXUIElement, _ key: String, _ type: T.Type) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        if result == .success, let typedValue = value as? T {
            return typedValue
        }
        return nil
    }

    static func setAttribute<T>(_ element: AXUIElement, _ value: T, _ attribute: String, _ type: AXValueType) {
        var v = value
        AXUIElementSetAttributeValue(element, attribute as CFString, AXValueCreate(type, &v)!)
    }

    static func value<T>(_ element: AXUIElement, _ key: String, _ target: T, _ type: AXValueType) -> T? {
        if let a = attribute(element, key, AXValue.self) {
            var value = target
            AXValueGetValue(a, type, &value)
            return value
        }
        return nil
    }
}
