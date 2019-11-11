import Cocoa
import Foundation

class CoreGraphicsApis {
    static func windows() -> [NSDictionary] {
        return (CGWindowListCopyWindowInfo([.excludeDesktopElements, .optionOnScreenOnly], kCGNullWindowID) as! [NSDictionary])
                .filter {
            // workaround: filtering this criteria seems to remove non-windows UI elements
            let isWindowNotMenubarOrOthers = value($0, kCGWindowLayer, Int(0)) == 0
            let windowBounds = CGRect(dictionaryRepresentation: value($0, kCGWindowBounds, [:] as CFDictionary))!
            // workaround: some apps like chrome use a window to implement the search popover
            let isReasonablyBig = windowBounds.width > Preferences.minimumWindowSize && windowBounds.height > Preferences.minimumWindowSize
            return isWindowNotMenubarOrOthers && isReasonablyBig
        }
    }

    static func value<T>(_ cgWindow: NSDictionary, _ key: CFString, _ fallback: T) -> T {
        return cgWindow[key] as? T ?? fallback
    }

    static func image(_ windowNumber: CGWindowID) -> CGImage? {
        return CGWindowListCreateImage(.null, .optionIncludingWindow, windowNumber, [.boundsIgnoreFraming, .bestResolution])
    }
}
