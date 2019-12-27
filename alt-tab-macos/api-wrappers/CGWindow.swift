import Cocoa
import Foundation

typealias CGWindow = [CGWindowKey.RawValue: Any]

extension CGWindow {
    static func windows(_ option: CGWindowListOption) -> [CGWindow] {
        return CGWindowListCopyWindowInfo([.excludeDesktopElements, option], kCGNullWindowID) as! [CGWindow]
    }

    func value<T>(_ key: CGWindowKey, _ type: T.Type) -> T? {
        return self[key.rawValue] as? T
    }

    // workaround: filtering this criteria seems to remove non-windows UI elements
    func isNotMenubarOrOthers() -> Bool {
        return value(.layer, Int.self) == 0
    }

    // workaround: some apps like chrome use a window to implement the search popover
    func isReasonablyBig() -> Bool {
        let windowBounds = CGRect(dictionaryRepresentation: value(.bounds, CFDictionary.self)!)!
        return windowBounds.width > Preferences.minimumWindowSize && windowBounds.height > Preferences.minimumWindowSize
    }
}

// This list of keys is not exhaustive; it contains only the values used by this app
// full public list: CoreGraphics.CGWindow.swift
enum CGWindowKey: String {
    case number = "kCGWindowNumber"
    case layer = "kCGWindowLayer"
    case bounds = "kCGWindowBounds"
    case ownerPID = "kCGWindowOwnerPID"
    case ownerName = "kCGWindowOwnerName"
    case name = "kCGWindowName"
}
