import Foundation

class MissionControl {
    static func isActive() -> Bool {
        // when Mission Control is active, the Dock process spawns some windows. We observe this side-effect and infer
        var missionControlHint = false
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

enum MissionControlState {
    case inactive
    case expose
    case showDesktop
}
