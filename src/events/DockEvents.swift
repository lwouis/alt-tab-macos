import Foundation

class DockEvents {
    private static var axObserver: AXObserver?
    private static var axUiElement: AXUIElement?

    static func observe(_ dockPid: pid_t) {
        let element = AXUIElementCreateApplication(dockPid)
        var observer: AXObserver?
        let status = AXObserverCreate(dockPid, handleEvent, &observer)
        guard status == .success, let observer else {
            Logger.warning { "Dock AXObserver creation failed for pid:\(dockPid) status:\(status.rawValue)" }
            return
        }
        axUiElement = element
        axObserver = observer
        for notification in MissionControlState.allCases {
            AXCallScheduler.shared.schedule(key: "sub-dock-\(notification.rawValue)", context: "dock", pid: dockPid) {
                if try element.subscribeToNotification(observer, notification.rawValue, nil) {
                    if notification == MissionControlState.showDesktop {
                        Logger.debug { "Subscribed to Dock" }
                    }
                }
            }
        }
        CFRunLoopAddSource(BackgroundWork.missionControlThread.runLoop, AXObserverGetRunLoopSource(observer), .commonModes)
    }

    private static let handleEvent: AXObserverCallback = { _, _, notificationName, _ in
        Logger.debug { notificationName }
        let state = MissionControlState(rawValue: notificationName as String)!
        MissionControl.setState(state)
    }
}
