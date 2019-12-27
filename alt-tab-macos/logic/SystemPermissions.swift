import Foundation
import Cocoa

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy > Privacy
class SystemPermissions {
    // macOS 10.9+
    static func ensureAccessibilityCheckboxIsChecked() {
        if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
            debugPrint("Before using this app, you need to give permission in System Preferences > Security & Privacy > Privacy > Accessibility.",
                    "Please authorize and re-launch.",
                    "See https://help.rescuetime.com/article/59-how-do-i-enable-accessibility-permissions-on-mac-osx",
                    separator: "\n")
            NSApp.terminate(self)
        }
    }

    // macOS 10.15+
    static func ensureScreenRecordingCheckboxIsChecked() {
        let firstWindow = CGWindow.windows(.optionOnScreenOnly)[0]
        if let cgId = firstWindow.value(.number, CGWindowID.self), cgId.screenshot() == nil {
            debugPrint("Before using this app, you need to give permission in System Preferences > Security & Privacy > Privacy > Screen Recording.",
                    "Please authorize and re-launch.",
                    "See https://dropshare.zendesk.com/hc/en-us/articles/360033453434-Enabling-Screen-Recording-Permission-on-macOS-Catalina-10-15-",
                    separator: "\n")
            NSApp.terminate(self)
        }
    }
}
