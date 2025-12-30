import Foundation

class DockEvents {
    private static var axObserver: AXObserver?
    private static var axUiElement: AXUIElement?

    static func observe(_ dockPid: pid_t) {
        if #available(macOS 12.0, *) {
            axUiElement = AXUIElementCreateApplication(dockPid)
            AXObserverCreate(dockPid, handleEvent, &axObserver)
            // are we sure we always get a non-nil axObserver?
            for notification in MissionControlState.allCases {
                AXUIElement.retryAxCallUntilTimeout(callType: .subscribeToDockNotification) {
                    if try axUiElement!.subscribeToNotification(axObserver!, notification.rawValue, nil) {
                        if notification == MissionControlState.showDesktop {
                            Logger.debug { "Subscribed to Dock" }
                        }
                    }
                }
            }
            CFRunLoopAddSource(BackgroundWork.missionControlThread.runLoop, AXObserverGetRunLoopSource(axObserver!), .commonModes)
        } else {
            // we could handle macOS < 12 here like yabai does. However, they poll with ax calls until they notice Mission Control stops
            // this takes up ressources when Mission Control is open. If the user keeps it open for a few hours, this would accelerate battery usage
            // SLSRegisterConnectionNotifyProc(g_connection, connection_handler, 1204, NULL);
            // then listen every 0.1f * NSEC_PER_SEC for layer == 18 and owner = "Dock"
            // when found, mission control is not active anymore
        }
    }

    private static let handleEvent: AXObserverCallback = { _, _, notificationName, _ in
        Logger.debug { notificationName }
        MissionControl.setState(MissionControlState(rawValue: notificationName as String)!)
    }
}
