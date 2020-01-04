import Cocoa
import Foundation

// This list of keys is not exhaustive; it contains only the values used by this app
// full public list: ApplicationServices.HIServices.AXAttributeConstants.swift
// Note that the String value is transformed by the getters (e.g. kAXWindowsAttribute -> AXWindows)
enum AXAttributeKey: String {
    case windows = "AXWindows"
    case minimized = "AXMinimized"
    case focusedWindow = "AXFocusedWindow"
    case subrole = "AXSubrole"
}

extension AXUIElement {
    func value<T>(_ key: AXAttributeKey, _ target: T, _ type: AXValueType) -> T? {
        if let a = attribute(key, AXValue.self) {
            var value = target
            AXValueGetValue(a, type, &value)
            return value
        }
        return nil
    }

    func attribute<T>(_ key: AXAttributeKey, _ type: T.Type) -> T? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(self, key.rawValue as CFString, &value)
        if result == .success, let value = value as? T {
            return value
        }
        return nil
    }

    func cgId() -> CGWindowID {
        var id = CGWindowID(0)
        _AXUIElementGetWindow(self, &id)
        return id
    }

    func focusedWindow() -> AXUIElement? {
        return attribute(.focusedWindow, AXUIElement.self)
    }

    func isActualWindow() -> Bool {
        let subrole = self.attribute(.subrole, String.self)
        return subrole != nil && subrole != "AXUnknown"
    }

    func windows() -> [AXUIElement]? {
        return attribute(.windows, [AXUIElement].self)
    }

    func window(_ id: CGWindowID) -> AXUIElement? {
        return windows()?.first(where: { return id == $0.cgId() })
    }

    func isMinimized() -> Bool {
        return attribute(.minimized, Bool.self) == true
    }

    func focus(_ id: CGWindowID) {
        // implementation notes: the following sequence of actions repeats some calls. This is necessary for
        // minimized windows on other spaces, and focuses windows faster (e.g. the Security & Privacy window)
        // macOS bug: when switching to a System Preferences window in another space, it switches to that space,
        // but quickly switches back to another window in that space
        // You can reproduce this buggy behaviour by clicking on the dock icon, proving it's an OS bug
        var elementConnection = UInt32(0)
        CGSGetWindowOwner(cgsMainConnectionId, id, &elementConnection)
        var psn = ProcessSerialNumber()
        CGSGetConnectionPSN(elementConnection, &psn)
        AXUIElementPerformAction(self, kAXRaiseAction as CFString)
        makeKeyWindow(psn, id)
        _SLPSSetFrontProcessWithOptions(&psn, id, .userGenerated)
        makeKeyWindow(psn, id)
        AXUIElementPerformAction(self, kAXRaiseAction as CFString)
    }

    // The following function was ported from https://github.com/Hammerspoon/hammerspoon/issues/370#issuecomment-545545468
    func makeKeyWindow(_ psn: ProcessSerialNumber, _ wid: CGWindowID) -> Void {
        var wid_ = wid
        var psn_ = psn

        var bytes1 = [UInt8](repeating: 0, count: 0xf8)
        bytes1[0x04] = 0xF8
        bytes1[0x08] = 0x01
        bytes1[0x3a] = 0x10

        var bytes2 = [UInt8](repeating: 0, count: 0xf8)
        bytes2[0x04] = 0xF8
        bytes2[0x08] = 0x02
        bytes2[0x3a] = 0x10

        memcpy(&bytes1[0x3c], &wid_, MemoryLayout<UInt32>.size)
        memset(&bytes1[0x20], 0xFF, 0x10)
        memcpy(&bytes2[0x3c], &wid_, MemoryLayout<UInt32>.size)
        memset(&bytes2[0x20], 0xFF, 0x10)

        SLPSPostEventRecordTo(&psn_, &(UnsafeMutablePointer(mutating: UnsafePointer<UInt8>(bytes1)).pointee))
        SLPSPostEventRecordTo(&psn_, &(UnsafeMutablePointer(mutating: UnsafePointer<UInt8>(bytes2)).pointee))
    }
}
