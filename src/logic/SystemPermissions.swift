import Cocoa
import os

import ScreenCaptureKit

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy
class SystemPermissions {
    static var accessibilityPermission = PermissionStatus.notGranted
    static var screenRecordingPermission = PermissionStatus.notGranted
    static var preStartupPermissionsPassed = false
    static var flakyCounter = 0
    static var timerPermissionsToUpdatePermissionsWindow: Timer?
    static var timerPermissionsRemovedWhileAltTabIsRunning: Timer?

    static func ensurePermissionsAreGranted(_ continueAppStartup: @escaping () -> Void) {
        let startupBlock = {
            pollPermissionsRemovedWhileAltTabIsRunning()
            continueAppStartup()
        }
        if updateAccessibilityIsGranted() != .notGranted && updateScreenRecordingIsGranted() != .notGranted {
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
        CFRunLoopAddTimer(BackgroundWork.systemPermissionsThread.runLoop, timerPermissionsToUpdatePermissionsWindow!, .commonModes)
    }

    static func pollPermissionsRemovedWhileAltTabIsRunning() {
        timerPermissionsRemovedWhileAltTabIsRunning = Timer(timeInterval: 5, repeats: true) { _ in
            DispatchQueue.main.async {
                checkPermissionsWhileAltTabIsRunning()
            }
        }
        timerPermissionsRemovedWhileAltTabIsRunning!.tolerance = 1
        CFRunLoopAddTimer(BackgroundWork.systemPermissionsThread.runLoop, timerPermissionsRemovedWhileAltTabIsRunning!, .commonModes)
    }

    @discardableResult
    static func updateAccessibilityIsGranted() -> PermissionStatus {
        accessibilityPermission = detectAccessibilityIsGranted()
        return accessibilityPermission
    }

    @discardableResult
    static func updateScreenRecordingIsGranted() -> PermissionStatus {
        screenRecordingPermission = detectScreenRecordingIsGranted()
        return screenRecordingPermission
    }

    private static func detectAccessibilityIsGranted() -> PermissionStatus {
        if #available(macOS 10.9, *) {
            return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary) ? .granted : .notGranted
        }
        return .granted
    }

    private static func detectScreenRecordingIsGranted() -> PermissionStatus {
        // ScreenCaptureKit is available from macOS 12.0
        if #available(macOS 12.0, *) {
            return screenRecordingIsGrantedOnSomeDisplay() ? .granted :
                (Preferences.screenRecordingPermissionSkipped ? .skipped : .notGranted)
        }
        // For macOS versions older than 12.0, assume granted
        return .granted
    }

    private static func checkPermissionsWhileAltTabIsRunning() {
        Logger.debug(accessibilityPermission, screenRecordingPermission, preStartupPermissionsPassed, screenRecordingPermission, Appearance.hideThumbnails, Preferences.previewFocusedWindow)
        SystemPermissions.updateAccessibilityIsGranted()
        Logger.debug(accessibilityPermission)
        if accessibilityPermission == .notGranted {
            Logger.info("accessibilityPermission not granted; restarting")
            App.app.restart()
        }
        if screenRecordingPermission == .skipped || (Appearance.hideThumbnails && !Preferences.previewFocusedWindow) { return }
        SystemPermissions.updateScreenRecordingIsGranted()
        Logger.debug(screenRecordingPermission)
        Menubar.togglePermissionCallout(screenRecordingPermission == .skipped)
        if screenRecordingPermission == .notGranted {
            // permission check may yield a false negative during wake-up
            // we restart after 2 negative checks
            if flakyCounter >= 2 {
                Logger.info("screenRecordingPermission not granted 3 times; restarting")
                App.app.restart()
            } else {
                flakyCounter += 1
            }
        } else {
            flakyCounter = 0
        }
    }

    private static func checkPermissionsToUpdatePermissionsWindow(_ startupBlock: @escaping () -> Void) {
        updateAccessibilityIsGranted()
        updateScreenRecordingIsGranted()
        Logger.debug(accessibilityPermission, screenRecordingPermission, preStartupPermissionsPassed)
        Menubar.togglePermissionCallout(screenRecordingPermission == .skipped)
        if accessibilityPermission != App.app.permissionsWindow?.accessibilityView?.permissionStatus {
            App.app.permissionsWindow?.accessibilityView.updatePermissionStatus(accessibilityPermission)
        }
        if #available(macOS 10.15, *), screenRecordingPermission != App.app.permissionsWindow?.screenRecordingView?.permissionStatus {
            App.app.permissionsWindow?.screenRecordingView?.updatePermissionStatus(screenRecordingPermission)
        }
        if !preStartupPermissionsPassed {
            if accessibilityPermission != .notGranted && screenRecordingPermission != .notGranted {
                preStartupPermissionsPassed = true
                App.app.permissionsWindow?.close()
                startupBlock()
            }
        } else {
            if accessibilityPermission == .notGranted || screenRecordingPermission == .notGranted {
                App.app.restart()
            }
        }
    }

    // workaround: public API CGPreflightScreenCaptureAccess and private API SLSRequestScreenCaptureAccess exist, but
    // their return value is not updated during the app lifetime
    // note: shows the system prompt if there's no permission
    private static func screenRecordingIsGrantedOnSomeDisplay() -> Bool {
        // This function is only called if macOS 12.0 or later, so we can directly use ScreenCaptureKit
        let mainDisplayID = CGMainDisplayID()
        if screenRecordingIsGrantedOnDisplay(mainDisplayID) {
            return true
        }
        // maybe the main screen can't produce a CGDisplayStream, but another screen can
        // a positive on any screen must mean that the permission is granted; we try on the other screens
        for screen in NSScreen.screens {
            if let id = screen.number(), id != mainDisplayID {
                if screenRecordingIsGrantedOnDisplay(id) {
                    return true
                }
            }
        }
        return false
    }

    private static func screenRecordingIsGrantedOnDisplay(_ displayId: CGDirectDisplayID) -> Bool {
        // ScreenCaptureKit is the only method to check screen recording permissions from macOS 12.0 onwards.
        // This function is only called if macOS 12.0 or later, based on the `detectScreenRecordingIsGranted` check.
        let semaphore = DispatchSemaphore(value: 0)
        var isGranted = false
        SCShareableContent.getWithCompletionHandler { content, error in
            if let displays = content?.displays {
                isGranted = displays.contains(where: { $0.displayID == displayId })
            }
            semaphore.signal()
        }
        semaphore.wait()
        return isGranted
    }
}
// Note: The new logic uses a synchronous semaphore wait, which is safe here since this function is only used for permission detection and the legacy path will remain for older systems.
