import Foundation
import Cocoa

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy > Privacy
class SystemPermissions {
    // macOS 10.9+
    static func checkAccessibility() -> Bool {
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    // macOS 10.15+
    static func checkScreenshot() -> Bool {
        // TODO: This may false-positive if the first window we encounter happens to be owned by the app itself
        let firstWindow = CGWindow.windows(.optionOnScreenOnly)[0]
        return firstWindow.value(.number, CGWindowID.self)!.screenshot() != nil
    }
}
