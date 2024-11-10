import Cocoa

class ScreensEvents {
    static func observe() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleEvent), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private static func handleEvent(_ notification: Notification) {
        logger.d(notification.name.rawValue)
        // a screen added or removed can shuffle windows around Spaces; we refresh them
        Spaces.refreshSpacesAndWindows()
        logger.i("screens", NSScreen.screens.map { ($0.uuid() ?? "nil" as CFString, $0.frame) })
        logger.i("spaces", Spaces.screenSpacesMap)
        logger.i("current space", Spaces.currentSpaceIndex, Spaces.currentSpaceId)
        // a screen added or removed, or screen resolution change can mess up layout; we reset components
        App.app.resetPreferencesDependentComponents()
    }
}
