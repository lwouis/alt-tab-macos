import Cocoa

class ScreensEvents {
    static func observe() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil, using: { notification in
            logger.i(notification.name, NSScreen.screens.map { ($0.uuid(), $0.frame) })
            Spaces.refreshAllIdsAndIndexes()
        })
    }
}
