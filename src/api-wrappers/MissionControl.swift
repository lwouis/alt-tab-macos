import Foundation

class MissionControl {
    private static var state_ = MissionControlState.inactive
    private static var axObserver: AXObserver?
    private static var axUiElement: AXUIElement?

    static func state() -> MissionControlState {
        if #available(macOS 12.0, *) {
            return state_
        } else {
            return isActive() ? .showAllWindows : .inactive
        }
    }

    static func setState(_ state: MissionControlState) {
        state_ = state
    }

    // on macOS < 12, this is the way we used to guess if Mission Control is active
    // on macOS >= 12, we listen to private notifications, which is accurate
    // when Mission Control is active, the Dock process spawns some windows. We observe this side-effect and infer
    private static func isActive() -> Bool {
        for window in CGWindow.windows(.optionOnScreenOnly) {
            // ownerName == "Dock" && title == nil is a sign that Mission Control may be active
            if window.ownerName() == "Dock" && window.title() == nil
                       // layer == 500 can be a false positive when a user drags a file from a Dock folder
                       // see https://github.com/lwouis/alt-tab-macos/issues/706
                       && window.layer() != 500 {
                return true
            }
        }
        return false
    }

    static func observe(_ dockPid: pid_t) {
        if #available(macOS 12.0, *) {
            axUiElement = AXUIElementCreateApplication(dockPid)
            AXObserverCreate(dockPid, axObserverCallbackDock, &axObserver)
            // are we sure we always get a non-nil axObserver?
            for notification in MissionControlState.allCases {
                retryAxCallUntilTimeout {
                    try axUiElement!.subscribeToNotification(axObserver!, notification.rawValue, nil)
                }
            }
            CFRunLoopAddSource(BackgroundWork.missionControlThread.runLoop, AXObserverGetRunLoopSource(axObserver!), .defaultMode)
        } else {
            // we could handle macOS < 12 here like yabai does. However, they poll with ax calls until they notice Mission Control stops
            // this takes up ressources when Mission Control is open. If the user keeps it open for a few hours, this would accelerate battery usage
            // SLSRegisterConnectionNotifyProc(g_connection, connection_handler, 1204, NULL);
            // then listen every 0.1f * NSEC_PER_SEC for layer == 18 and owner = "Dock"
            // when found, mission control is not active anymore
        }
    }
}

fileprivate let axObserverCallbackDock: AXObserverCallback = { _, element, notificationName, _ in
    logger.d(notificationName, element)
    MissionControl.setState(MissionControlState(rawValue: notificationName as String)!)
}
