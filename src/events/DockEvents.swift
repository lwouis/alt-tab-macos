import Foundation

class DockEvents {
    private static var axObserver: AXObserver?
    private static var axUiElement: AXUIElement?

    static func observe(_ dockPid: pid_t) {
        axUiElement = AXUIElementCreateApplication(dockPid)
        AXObserverCreate(dockPid, handleEvent, &axObserver)
        // are we sure we always get a non-nil axObserver?
        for notification in MissionControlState.allCases {
            AXCallScheduler.shared.schedule(key: "sub-dock-\(notification.rawValue)", context: "dock", pid: dockPid) {
                if try axUiElement!.subscribeToNotification(axObserver!, notification.rawValue, nil) {
                    if notification == MissionControlState.showDesktop {
                        Logger.debug { "Subscribed to Dock" }
                    }
                }
            }
        }
        CFRunLoopAddSource(BackgroundWork.missionControlThread.runLoop, AXObserverGetRunLoopSource(axObserver!), .commonModes)
    }

    private static let handleEvent: AXObserverCallback = { _, _, notificationName, _ in
        Logger.debug { notificationName }
        let state = MissionControlState(rawValue: notificationName as String)!
        MissionControl.setState(state)
    }
}
