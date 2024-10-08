import Cocoa

typealias CGWindow = [CFString: Any]

extension CGWindow {
    static let normalLevel = CGWindowLevelForKey(.normalWindow)
    static let floatingWindow = CGWindowLevelForKey(.floatingWindow)

    static func windows(_ option: CGWindowListOption) -> [CGWindow] {
        return CGWindowListCopyWindowInfo([.excludeDesktopElements, option], kCGNullWindowID) as! [CGWindow]
    }

    // periphery:ignore
    // workaround: filtering this criteria seems to remove non-windows UI elements
    func isNotMenubarOrOthers() -> Bool {
        return layer() == 0
    }

    // periphery:ignore
    func id() -> CGWindowID? {
        return value(kCGWindowNumber, CGWindowID.self)
    }

    func layer() -> Int? {
        return value(kCGWindowLayer, Int.self)
    }

    // periphery:ignore
    func bounds() -> CFDictionary? {
        return value(kCGWindowBounds, CFDictionary.self)
    }

    // periphery:ignore
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
