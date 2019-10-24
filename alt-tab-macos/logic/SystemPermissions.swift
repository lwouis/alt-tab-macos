import Foundation
import Cocoa

class SystemPermissions {
    static func ensureAccessibilityCheckboxIsChecked() {
        if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) {
            debugPrint("Before using this app, you need to give permission in System Preferences > Security & Privacy > Privacy > Accessibility.",
                    "Please authorize and re-launch.",
                    "See https://help.rescuetime.com/article/59-how-do-i-enable-accessibility-permissions-on-mac-osx",
                    separator: "\n")
            NSApp.terminate(self)
        }
    }

    static func ensureScreenRecordingCheckboxIsChecked() {
        let firstWindow = cgWindows()[0]
        let windowImage = CGWindowListCreateImage(.null, .optionIncludingWindow, firstWindow[kCGWindowNumber] as! CGWindowID, [.boundsIgnoreFraming, .bestResolution])
        if windowImage == nil {
            debugPrint("Before using this app, you need to give permission in System Preferences > Security & Privacy > Privacy > Screen Recording.",
                    "Please authorize and re-launch.",
                    "See https://dropshare.zendesk.com/hc/en-us/articles/360033453434-Enabling-Screen-Recording-Permission-on-macOS-Catalina-10-15-",
                    separator: "\n")
            NSApp.terminate(self)
        }
    }
}
