import Foundation
import Cocoa

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy
class SystemPermissions {
    static func ensureAccessibilityCheckboxIsChecked() {
        guard #available(OSX 10.9, *) else { return }
        if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
            debugPrint("Before using this app, you need to give permission in System Preferences > Security & Privacy > Privacy > Accessibility.",
                    "Please authorize and re-launch.",
                    "See https://help.rescuetime.com/article/59-how-do-i-enable-accessibility-permissions-on-mac-osx",
                    separator: "\n")
            App.shared.terminate(self)
        }
    }

    static func ensureScreenRecordingCheckboxIsChecked() {
        guard #available(OSX 10.15, *) else { return }
        if SLSRequestScreenCaptureAccess() != 1 {
            debugPrint("Before using this app, you need to give permission in System Preferences > Security & Privacy > Privacy > Screen Recording.",
                    "Please authorize and re-launch.",
                    "See https://dropshare.zendesk.com/hc/en-us/articles/360033453434-Enabling-Screen-Recording-Permission-on-macOS-Catalina-10-15-",
                    separator: "\n")
            App.shared.terminate(self)
        }
    }
}
