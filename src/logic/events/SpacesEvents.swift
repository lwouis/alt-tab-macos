import Cocoa

class SpacesEvents {
    static func observe() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleEvent), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    @objc private static func handleEvent(_ notification: Notification) {
        ScreensEvents.debouncerScreenAndSpace.debounce(.spaceEvent) {
            Logger.debug { notification.name.rawValue }
            // Workaround for Safari full-screen videos
            // when full-screening a video, Safari spawns a second full-screen window called "Safari"
            // this window doesn't emit resize/move events. It doesn't pass isActualWindow on creation. It's added on focusedWindowChanged
            // for such cases, we refresh isFullscreen on Space change
            Windows.updateIsFullscreenOnCurrentSpace()
        }
    }
}
