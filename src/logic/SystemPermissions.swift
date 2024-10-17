import Cocoa

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy
class SystemPermissions {
    static var preStartupPermissionsPassed = false
    static var timerPermissionsToUpdatePermissionsWindow: Timer?
    static var timerPermissionsRemovedWhileAltTabIsRunning: Timer?

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

    static func observePermissionsRemovedWhileAltTabIsRunning() {
        var counter = 0
        timerPermissionsRemovedWhileAltTabIsRunning = Timer(timeInterval: 5, repeats: true, block: { _ in
            DispatchQueue.main.async {
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
                    if counter >= 2 {
                        App.app.restart()
                    } else {
                        counter += 1
                    }
                } else {
                    counter = 0
                }
            }
        })
        timerPermissionsRemovedWhileAltTabIsRunning!.tolerance = 4.9
        CFRunLoopAddTimer(BackgroundWork.systemPermissionsThread.runLoop, timerPermissionsRemovedWhileAltTabIsRunning!, .defaultMode)
    }

    static func observePermissionsToUpdatePermissionsWindow(_ startupBlock: @escaping () -> Void) {
        if #available(macOS 10.15, *), !preStartupPermissionsPassed {
            // this call triggers the permission prompt, however it's the only way to force the app to be listed with a checkbox
            SLSRequestScreenCaptureAccess()
        }
        timerPermissionsToUpdatePermissionsWindow = Timer(timeInterval: 0.1, repeats: true) { _ in
            DispatchQueue.main.async {
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
        }
        timerPermissionsToUpdatePermissionsWindow!.tolerance = 0.09
        CFRunLoopAddTimer(BackgroundWork.systemPermissionsThread.runLoop, timerPermissionsToUpdatePermissionsWindow!, .defaultMode)
    }

    static func ensurePermissionsAreGranted(_ continueAppStartup: @escaping () -> Void) {
        let startupBlock = {
            observePermissionsRemovedWhileAltTabIsRunning()
            continueAppStartup()
        }
        if accessibilityIsGranted() != .notGranted && screenRecordingIsGranted() != .notGranted {
            preStartupPermissionsPassed = true
            startupBlock()
        } else {
            App.app.permissionsWindow.show(startupBlock)
        }
    }
}
