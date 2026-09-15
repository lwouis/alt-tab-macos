import Foundation

class MissionControl {
    private static let stateLock = NSLock()
    private static var state_ = MissionControlState.inactive

    /// We listen to private notifications, which is accurate; `setState` writes what they report.
    static func state() -> MissionControlState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state_
    }

    static func setState(_ state: MissionControlState) {
        stateLock.lock()
        defer { stateLock.unlock() }
        state_ = state
        Logger.info { state }
    }
}
