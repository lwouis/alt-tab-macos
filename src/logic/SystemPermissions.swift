import Cocoa

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy
class SystemPermissions {
    static var changeCallback: (() -> Void)!
    static var screenRecordingObserver: Timer!
    static var permissionsWindow: PermissionsWindow!

    static func accessibilityIsGranted() -> Bool {
        if #available(OSX 10.9, *) {
            return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary)
        }
        return true
    }

    static func screenRecordingIsGranted() -> Bool {
        if #available(OSX 10.15, *) {
            return screenRecordingIsGranted_()
        }
        return true
    }

    // there is no official API to check the status of the Screen Recording permission
    // there is the private API SLSRequestScreenCaptureAccess, but its value is not updated during the app lifetime
    // workaround: we check if we can get the title of at least one window, except from AltTab or the Dock
    private static func screenRecordingIsGranted_() -> Bool {
        let appPid = NSRunningApplication.current.processIdentifier
        if let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [CGWindow],
           let _ = windows.first(where: { (window) -> Bool in
               if let windowPid = window.ownerPID(),
                  windowPid != appPid,
                  let windowRunningApplication = NSRunningApplication(processIdentifier: windowPid),
                  windowRunningApplication.executableURL?.lastPathComponent != "Dock",
                  let _ = window.title() {
                   return true
               }
               return false
           }) {
            return true
        }
        return false
    }

    static func observePermissionsPostStartup() {
        screenRecordingObserver = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { _ in
            if !(accessibilityIsGranted() && screenRecordingIsGranted()) {
                App.app.restart()
            }
        })
    }

    static func observePermissionsPreStartup(_ startupBlock: @escaping () -> Void) {
        // this call triggers the permission prompt, however it's the only way to force the app to be listed with a checkbox
        SLSRequestScreenCaptureAccess()
        screenRecordingObserver = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { _ in
            let accessibility = accessibilityIsGranted()
            let screenRecording = screenRecordingIsGranted()
            if accessibility && screenRecording {
                permissionsWindow.close()
                screenRecordingObserver.invalidate()
                startupBlock()
            } else {
                if accessibility != permissionsWindow.accessibilityView.isPermissionGranted {
                    permissionsWindow.accessibilityView.updatePermissionStatus(accessibility)
                }
                if #available(OSX 10.15, *), screenRecording != permissionsWindow.screenRecordingView.isPermissionGranted {
                    permissionsWindow.screenRecordingView.updatePermissionStatus(screenRecording)
                }
            }
        })
    }

    static func ensurePermissionsAreGranted(_ continueAppStartup: @escaping () -> Void) {
        let startupBlock = {
            observePermissionsPostStartup()
            continueAppStartup()
        }
        if accessibilityIsGranted() && screenRecordingIsGranted() {
            startupBlock()
        } else {
            permissionsWindow = PermissionsWindow()
            permissionsWindow.show()
            observePermissionsPreStartup(startupBlock)
        }
    }
}
