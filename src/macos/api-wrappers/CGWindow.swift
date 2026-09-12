import Cocoa

typealias CGWindow = [CFString: Any]

extension CGWindow {
    static func windows(_ option: CGWindowListOption) -> [CGWindow] {
        return CGWindowListCopyWindowInfo([.excludeDesktopElements, option], kCGNullWindowID) as! [CGWindow]
    }

    func id() -> CGWindowID? {
        return value(kCGWindowNumber, CGWindowID.self)
    }

    func layer() -> Int? {
        return value(kCGWindowLayer, Int.self)
    }

    func bounds() -> NSRect? {
        if let cfDictionary = value(kCGWindowBounds, CFDictionary.self) {
            return NSRect(dictionaryRepresentation: cfDictionary)
        }
        return nil
    }

    func ownerPID() -> pid_t? {
        return value(kCGWindowOwnerPID, pid_t.self)
    }

    func ownerName() -> String? {
        return value(kCGWindowOwnerName, String.self)
    }

    func title() -> String? {
        return value(kCGWindowName, String.self)
    }

    private func value<T>(_ key: CFString, _ type: T.Type) -> T? {
        return self[key] as? T
    }
}
