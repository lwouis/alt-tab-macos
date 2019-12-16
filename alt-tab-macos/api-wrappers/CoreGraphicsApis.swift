import Cocoa
import Foundation

class CoreGraphicsApis {
    static func windows(_ option: CGWindowListOption) -> [NSDictionary] {
        return (CGWindowListCopyWindowInfo([.excludeDesktopElements, option], kCGNullWindowID) as! [NSDictionary])
                .filter { return windowIsNotMenubarOrOthers($0) && windowIsReasonablyBig($0) }
    }

    // workaround: filtering this criteria seems to remove non-windows UI elements
    private static func windowIsNotMenubarOrOthers(_ window: NSDictionary) -> Bool {
        return value(window, kCGWindowLayer, Int(0)) == 0
    }

    // workaround: some apps like chrome use a window to implement the search popover
    private static func windowIsReasonablyBig(_ window: NSDictionary) -> Bool {
        let windowBounds = CGRect(dictionaryRepresentation: value(window, kCGWindowBounds, [:] as CFDictionary))!
        return windowBounds.width > Preferences.minimumWindowSize && windowBounds.height > Preferences.minimumWindowSize
    }

    static func value<T>(_ cgWindow: NSDictionary, _ key: CFString, _ fallback: T) -> T {
        return cgWindow[key] as? T ?? fallback
    }

    static func image(_ windowNumber: CGWindowID) -> CGImage? {
        return CGWindowListCreateImage(.null, .optionIncludingWindow, windowNumber, [.boundsIgnoreFraming, .bestResolution])
    }
}
