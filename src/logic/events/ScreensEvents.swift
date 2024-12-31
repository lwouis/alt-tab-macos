import Cocoa

class ScreensEvents {
    static func observe() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleEvent), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private static func handleEvent(_ notification: Notification) {
        Logger.debug(notification.name.rawValue)
        // a screen added or removed can shuffle windows around Spaces; we refresh them
        App.app.refreshOpenUi(Windows.list)
        Logger.info("screens", NSScreen.screens.map { ($0.uuid() ?? "nil" as CFString, $0.frame) })
        Logger.info("spaces", Spaces.screenSpacesMap)
        Logger.info("current space", Spaces.currentSpaceIndex, Spaces.currentSpaceId)
        // a screen added or removed, or screen resolution change can mess up layout; we reset components
        App.app.resetPreferencesDependentComponents()
    }
}
