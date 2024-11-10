import Cocoa

class SystemAppearanceEvents {
    static func observe() {
        if #available(macOS 10.14, *) {
            DistributedNotificationCenter.default.addObserver(self, selector: #selector(handleEvent), name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        }
    }

    @objc private static func handleEvent(_ notification: Notification) {
        logger.d(notification.name.rawValue)
        logger.i(defaults.string(forKey: "AppleInterfaceStyle") ?? "Light")
        // fix layout issues by resetting components
        App.app.resetPreferencesDependentComponents()
    }
}
