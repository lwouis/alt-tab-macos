import Cocoa

class ScreensEvents {
    private static let throttler = Throttler(delayInMs: 200)

    static func observe() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleEvent), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private static func handleEvent(_ notification: Notification) {
        // screen notifications often arrive in groups (e.g. 2 in a row in a short time)
        throttler.throttleOrProceed {
            Logger.debug { notification.name.rawValue }
            Spaces.refresh()
            Screens.refresh()
            // a screen added or removed, or screen resolution change can mess up layout; we reset components
            App.resetPreferencesDependentComponents()
            // a screen added or removed can shuffle windows around Spaces; we refresh them
            App.refreshOpenUiAfterExternalEvent(Windows.list)
            Logger.info { "screens:\(NSScreen.screens.map { ($0.cachedUuid() ?? "nil" as CFString, $0.frame) })" }
            Logger.info { "currentSpace:\(Spaces.currentSpaceIndex) (id:\(Spaces.currentSpaceId)) spaces:\(Spaces.screenSpacesMap)" }
        }
    }
}
