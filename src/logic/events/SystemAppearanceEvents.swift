import Cocoa

class SystemAppearanceEvents {
    static func observe() {
        if #available(macOS 10.14, *) {
            DistributedNotificationCenter.default.addObserver(self, selector: #selector(handleEvent), name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        }
    }

    @objc private static func handleEvent(_ notification: Notification) {
        Logger.debug { notification.name.rawValue }
        Logger.info { UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light" }
        // fix layout issues by resetting components
        App.app.resetPreferencesDependentComponents()
    }
}
