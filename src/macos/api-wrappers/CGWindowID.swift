import Cocoa

extension CGWindowID {
    func title() -> String? {
        cgProperty("kCGSWindowTitle", String.self)
    }

    private func cgProperty<T>(_ key: String, _ type: T.Type) -> T? {
        var value: AnyObject?
        CGSCopyWindowProperty(CGS_CONNECTION, self, key as CFString, &value)
        return value as? T
    }
}
