import Cocoa

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy
class SystemPermissions {
    static var preStartupPermissionsPassed = false
    static var flakyCounter = 0
    static var timerPermissionsToUpdatePermissionsWindow: Timer?
    static var timerPermissionsRemovedWhileAltTabIsRunning: Timer?

    static func ensurePermissionsAreGranted(_ continueAppStartup: @escaping () -> Void) {
        let startupBlock = {
            pollPermissionsRemovedWhileAltTabIsRunning()
            continueAppStartup()
        }
        if accessibilityIsGranted() != .notGranted && screenRecordingIsGranted() != .notGranted {
            preStartupPermissionsPassed = true
            startupBlock()
        } else {
            App.app.permissionsWindow.show(startupBlock)
        }
    }

    static func pollPermissionsToUpdatePermissionsWindow(_ startupBlock: @escaping () -> Void) {
        timerPermissionsToUpdatePermissionsWindow = Timer(timeInterval: 0.1, repeats: true) { _ in
            DispatchQueue.main.async {
                checkPermissionsToUpdatePermissionsWindow(startupBlock)
            }
        }
        timerPermissionsToUpdatePermissionsWindow!.tolerance = 0.1
        CFRunLoopAddTimer(BackgroundWork.systemPermissionsThread.runLoop, timerPermissionsToUpdatePermissionsWindow!, .defaultMode)
    }

    static func pollPermissionsRemovedWhileAltTabIsRunning() {
        timerPermissionsRemovedWhileAltTabIsRunning = Timer(timeInterval: 5, repeats: true) { _ in
            DispatchQueue.main.async {
                checkPermissionsWhileAltTabIsRunning()
            }
        }
        timerPermissionsRemovedWhileAltTabIsRunning!.tolerance = 1
        CFRunLoopAddTimer(BackgroundWork.systemPermissionsThread.runLoop, timerPermissionsRemovedWhileAltTabIsRunning!, .defaultMode)
    }

    static func accessibilityIsGranted() -> PermissionStatus {
        if #available(macOS 10.9, *) {
            return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary) ? .granted : .notGranted
        }
        return .granted
    }

    static func screenRecordingIsGranted() -> PermissionStatus {
        if #available(macOS 10.15, *) {
            return screenRecordingIsGranted_() ? .granted :
                    (Preferences.screenRecordingPermissionSkipped ? .skipped : .notGranted)
        }
        return .granted
    }

    private static func checkPermissionsWhileAltTabIsRunning() {
        let accessibility = accessibilityIsGranted()
        let screenRecording = screenRecordingIsGranted()
        logger.d(accessibility, screenRecording, preStartupPermissionsPassed)
        Menubar.permissionCalloutMenuItems?.forEach {
            $0.isHidden = screenRecording != .skipped
        }
        if accessibility == .notGranted {
            App.app.restart()
        }
        if screenRecording == .notGranted {
            // permission check may yield a false negative during wake-up
            // we restart after 2 negative checks
            if flakyCounter >= 2 {
                App.app.restart()
            } else {
                flakyCounter += 1
            }
        } else {
            flakyCounter = 0
        }
    }

    private static func checkPermissionsToUpdatePermissionsWindow(_ startupBlock: @escaping () -> Void) {
        let accessibility = accessibilityIsGranted()
        let screenRecording = screenRecordingIsGranted()
        logger.d(accessibility, screenRecording, preStartupPermissionsPassed)
        Menubar.permissionCalloutMenuItems?.forEach {
            $0.isHidden = screenRecording != .skipped
        }
        if accessibility != App.app.permissionsWindow?.accessibilityView?.permissionStatus {
            App.app.permissionsWindow?.accessibilityView.updatePermissionStatus(accessibility)
        }

        if #available(macOS 10.15, *), screenRecording != App.app.permissionsWindow?.screenRecordingView?.permissionStatus {
            App.app.permissionsWindow?.screenRecordingView?.updatePermissionStatus(screenRecording)
        }
        if !preStartupPermissionsPassed {
            if accessibility != .notGranted && screenRecording != .notGranted {
                preStartupPermissionsPassed = true
                App.app.permissionsWindow?.close()
                startupBlock()
            }
        } else {
            if accessibility == .notGranted || screenRecording == .notGranted {
                App.app.restart()
            }
        }
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
}
