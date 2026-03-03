import Cocoa

class SpacesEvents {
    private static let throttler = Throttler(delayInMs: 200)

    static func observe() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleEvent), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    @objc private static func handleEvent(_ notification: Notification) {
        throttler.throttleOrProceed {
            Logger.debug { notification.name.rawValue }
            // Workaround for Safari full-screen videos
            // when full-screening a video, Safari spawns a second full-screen window called "Safari"
            // this window doesn't emit resize/move events. It doesn't pass isActualWindow on creation. It's added on focusedWindowChanged
            // for such cases, we refresh isFullscreen on Space change
            Windows.updateIsFullscreenOnCurrentSpace()
            if let frontmostPid = Applications.frontmostPid,
               let frontmostApp = Applications.findOrCreate(frontmostPid, false),
               let focusedWindow = frontmostApp.focusedWindow {
                App.checkIfShortcutsShouldBeDisabled(focusedWindow, nil)
            }
            // if UI was kept open during Space transition, the Spaces may be obsolete; we refresh them
            App.refreshOpenUiAfterExternalEvent(Windows.list)
            Logger.info { "screens:\(NSScreen.screens.map { ($0.cachedUuid() ?? "nil" as CFString, $0.frame) })" }
            Logger.info { "currentSpace:\(Spaces.currentSpaceIndex) (id:\(Spaces.currentSpaceId)) spaces:\(Spaces.screenSpacesMap)" }
        }
    }
}
