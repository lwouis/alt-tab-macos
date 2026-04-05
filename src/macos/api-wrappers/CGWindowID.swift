import Cocoa

extension CGWindowID {
    func title() -> String? {
        cgProperty("kCGSWindowTitle", String.self)
    }

    func level() -> CGWindowLevel {
        var level = CGWindowLevel(0)
        CGSGetWindowLevel(CGS_CONNECTION, self, &level)
        return level
    }

    func spaces() -> [CGSSpaceID] {
        return CGSCopySpacesForWindows(CGS_CONNECTION, CGSSpaceMask.all.rawValue, [self] as CFArray) as! [CGSSpaceID]
    }

    private func cgProperty<T>(_ key: String, _ type: T.Type) -> T? {
        var value: AnyObject?
        CGSCopyWindowProperty(CGS_CONNECTION, self, key as CFString, &value)
        return value as? T
    }
}
