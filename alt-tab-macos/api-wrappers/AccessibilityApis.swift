import Cocoa
import Foundation

class AccessibilityApis {
    static func windows(_ cgOwnerPid: pid_t) -> [AXUIElement] {
        return attribute(AXUIElementCreateApplication(cgOwnerPid), kAXWindowsAttribute, [AXUIElement].self) ?? []
    }

    static func windowThatMatchCgWindow(_ ownerPid: pid_t, _ cgId: CGWindowID) -> AXUIElement? {
        return AccessibilityApis.windows(ownerPid).first(where: { return windowId($0) == cgId })
    }

    private static func windowId(_ window: AXUIElement) -> CGWindowID {
        var id = UInt32(0)
        _AXUIElementGetWindow(window, &id)
        return id
    }

    static func rect(_ element: AXUIElement) -> CGRect {
        let sizeBefore = value(element, kAXSizeAttribute, NSSize(), .cgSize)!
        let positionBefore = value(element, kAXPositionAttribute, NSPoint(), .cgPoint)!
        return CGRect(x: positionBefore.x, y: positionBefore.y, width: sizeBefore.width, height: sizeBefore.height)
    }

    static func focus(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
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

    static func attribute<T>(_ element: AXUIElement, _ key: String, _ type: T.Type) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        if result == .success, let typedValue = value as? T {
            return typedValue
        }
        return nil
    }
}
