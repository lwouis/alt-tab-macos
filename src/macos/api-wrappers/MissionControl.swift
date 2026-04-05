import Foundation

class MissionControl {
    private static let stateLock = NSLock()
    private static var state_ = MissionControlState.inactive

    static func state() -> MissionControlState {
        if #available(macOS 12.0, *) {
            stateLock.lock()
            defer { stateLock.unlock() }
            return state_
        } else {
            return isActive() ? .showAllWindows : .inactive
        }
    }

    static func setState(_ state: MissionControlState) {
        stateLock.lock()
        defer { stateLock.unlock() }
        state_ = state
        Logger.info { state }
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
}
