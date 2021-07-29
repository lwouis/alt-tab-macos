import Cocoa

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy
class SystemPermissions {
    static var changeCallback: (() -> Void)!
    static var timer: Timer!
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

    // workaround: public API CGPreflightScreenCaptureAccess and private API SLSRequestScreenCaptureAccess exist, but
    // their return value is not updated during the app lifetime
    // note: shows the system prompt if there's no permission
    private static func screenRecordingIsGranted_() -> Bool {
        return CGDisplayStream(
            dispatchQueueDisplay: CGMainDisplayID(),
            outputWidth: 1,
            outputHeight: 1,
            pixelFormat: Int32(kCVPixelFormatType_32BGRA),
            properties: nil,
            queue: .global(),
            handler: { _, _, _, _ in }
        ) != nil
    }

    static func observePermissionsPostStartup() {
        var counter = 0
        timer = Timer(timeInterval: 5, repeats: true, block: { _ in
            if !accessibilityIsGranted() {
                App.app.restart()
            }
            if !screenRecordingIsGranted() {
                // permission check may yield a false negative during wake-up
                // we restart after 2 negative checks
                if counter >= 2 {
                    App.app.restart()
                } else {
                    counter += 1
                }
            } else {
                counter = 0
            }
        })
        timer.tolerance = 4.9
        CFRunLoopAddTimer(BackgroundWork.systemPermissionsThread.runLoop, timer, .defaultMode)
    }

    static func observePermissionsPreStartup(_ startupBlock: @escaping () -> Void) {
        if #available(OSX 10.15, *) {
            // this call triggers the permission prompt, however it's the only way to force the app to be listed with a checkbox
            SLSRequestScreenCaptureAccess()
        }
        timer = Timer(timeInterval: 0.1, repeats: true) { _ in
            let accessibility = accessibilityIsGranted()
            let screenRecording = screenRecordingIsGranted()
            DispatchQueue.main.async {
                if accessibility && screenRecording {
                    timer.invalidate()
                    permissionsWindow?.close()
                    startupBlock()
                } else {
                    if accessibility != permissionsWindow.accessibilityView.isPermissionGranted {
                        permissionsWindow.accessibilityView.updatePermissionStatus(accessibility)
                    }
                    if #available(OSX 10.15, *), screenRecording != permissionsWindow.screenRecordingView.isPermissionGranted {
                        permissionsWindow.screenRecordingView.updatePermissionStatus(screenRecording)
                    }
                }
            }
        }
        timer.tolerance = 0.09
        CFRunLoopAddTimer(BackgroundWork.systemPermissionsThread.runLoop, timer, .defaultMode)
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
            permissionsWindow.center()
            App.shared.activate(ignoringOtherApps: true)
            permissionsWindow.makeKeyAndOrderFront(nil)
            observePermissionsPreStartup(startupBlock)
        }
    }
}
