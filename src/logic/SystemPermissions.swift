import Cocoa
import ScreenCaptureKit.SCShareableContent

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy
class SystemPermissions {
    static var preStartupPermissionsPassed = false
    static var timerPermissionsToUpdatePermissionsWindow: Timer?
    static var timerPermissionsRemovedWhileAltTabIsRunning: Timer?

    static func ensurePermissionsAreGranted(_ continueAppStartup: @escaping () -> Void) {
        let startupBlock = {
            pollPermissionsRemovedWhileAltTabIsRunning()
            continueAppStartup()
        }
        if AccessibilityPermission.update() != .notGranted && ScreenRecordingPermission.update() != .notGranted {
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

    private static func pollPermissionsRemovedWhileAltTabIsRunning() {
        timerPermissionsRemovedWhileAltTabIsRunning = Timer(timeInterval: 5, repeats: true) { _ in
            DispatchQueue.main.async {
                checkPermissionsWhileAltTabIsRunning()
            }
        }
        timerPermissionsRemovedWhileAltTabIsRunning!.tolerance = 1
        CFRunLoopAddTimer(BackgroundWork.systemPermissionsThread.runLoop, timerPermissionsRemovedWhileAltTabIsRunning!, .commonModes)
    }

    private static func checkPermissionsWhileAltTabIsRunning() {
        Logger.debug(AccessibilityPermission.status, ScreenRecordingPermission.status, preStartupPermissionsPassed, ScreenRecordingPermission.status, Appearance.hideThumbnails, Preferences.previewFocusedWindow)
        AccessibilityPermission.update()
        Logger.debug(AccessibilityPermission.status)
        if AccessibilityPermission.status == .notGranted {
            Logger.info("accessibilityPermission not granted; restarting")
            App.app.restart()
        }
        if ScreenRecordingPermission.status == .skipped || (Appearance.hideThumbnails && !Preferences.previewFocusedWindow) { return }
        ScreenRecordingPermission.update()
        Logger.debug(ScreenRecordingPermission.status)
        Menubar.togglePermissionCallout(ScreenRecordingPermission.status == .skipped)
        if ScreenRecordingPermission.status == .notGranted {
            // permission check may yield a false negative during wake-up
            // we restart after 2 negative checks
            if ScreenRecordingPermission.flakyCounter >= 2 {
                Logger.info("screenRecordingPermission not granted 3 times; restarting")
                App.app.restart()
            } else {
                ScreenRecordingPermission.flakyCounter += 1
            }
        } else {
            ScreenRecordingPermission.flakyCounter = 0
        }
    }

    private static func checkPermissionsToUpdatePermissionsWindow(_ startupBlock: @escaping () -> Void) {
        AccessibilityPermission.update()
        ScreenRecordingPermission.update()
        Logger.debug(AccessibilityPermission.status, ScreenRecordingPermission.status, preStartupPermissionsPassed)
        Menubar.togglePermissionCallout(ScreenRecordingPermission.status == .skipped)
        if AccessibilityPermission.status != App.app.permissionsWindow?.accessibilityView?.permissionStatus {
            App.app.permissionsWindow?.accessibilityView.updatePermissionStatus(AccessibilityPermission.status)
        }
        if #available(macOS 10.15, *), ScreenRecordingPermission.status != App.app.permissionsWindow?.screenRecordingView?.permissionStatus {
            App.app.permissionsWindow?.screenRecordingView?.updatePermissionStatus(ScreenRecordingPermission.status)
        }
        if !preStartupPermissionsPassed {
            if AccessibilityPermission.status != .notGranted && ScreenRecordingPermission.status != .notGranted {
                preStartupPermissionsPassed = true
                App.app.permissionsWindow?.close()
                startupBlock()
            }
        } else {
            if AccessibilityPermission.status == .notGranted || ScreenRecordingPermission.status == .notGranted {
                App.app.restart()
            }
        }
    }
}

class AccessibilityPermission {
    static var status = PermissionStatus.notGranted

    @discardableResult
    static func update() -> PermissionStatus {
        status = detect()
        return status
    }

    private static func detect() -> PermissionStatus {
        return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary) ? .granted : .notGranted
    }
}

class ScreenRecordingPermission {
    static var status = PermissionStatus.notGranted
    static var flakyCounter = 0

    @discardableResult
    static func update() -> PermissionStatus {
        status = detect()
        return status
    }

    private static func detect() -> PermissionStatus {
        if #available(macOS 10.15, *) {
            return isGrantedOnSomeDisplay() ? .granted :
                (Preferences.screenRecordingPermissionSkipped ? .skipped : .notGranted)
        }
        return .granted
    }

    // workaround: public API CGPreflightScreenCaptureAccess and private API SLSRequestScreenCaptureAccess exist, but
    // their return value is not updated during the app lifetime
    // note: shows the system prompt if there's no permission
    private static func isGrantedOnSomeDisplay() -> Bool {
        if #available(macOS 12.3, *) {
            return checkWithSCShareableContent()
        } else {
            let mainDisplayID = CGMainDisplayID()
            if checkWithCGDisplayStream(mainDisplayID) {
                return true
            }
            // maybe the main screen can't produce a CGDisplayStream, but another screen can
            // a positive on any screen must mean that the permission is granted; we try on the other screens
            for screen in NSScreen.screens {
                if let id = screen.number(), id != mainDisplayID {
                    if checkWithCGDisplayStream(id) {
                        return true
                    }
                }
            }
            return false
        }
    }

    @available(macOS 12.3, *)
    private static func checkWithSCShareableContent() -> Bool {
        return runWithTimeout { completion in
            SCShareableContent.getWithCompletionHandler { shareableContent, error in
                completion(error != nil ? false : (shareableContent != nil))
            }
        }
    }

    private static func checkWithCGDisplayStream(_ id: CGDirectDisplayID) -> Bool {
        return runWithTimeout { completion in
            // this initializer can actually block for a while
            // it's undocumented but has been proven by spindumps shared by AltTab users
            let displayStream = CGDisplayStream(
                dispatchQueueDisplay: id,
                outputWidth: 1,
                outputHeight: 1,
                pixelFormat: Int32(kCVPixelFormatType_32BGRA),
                properties: nil,
                queue: .global()
            ) { _, _, _, _ in }
            completion(displayStream != nil)
        }
    }

    private static func runWithTimeout(_ block: @escaping (@escaping (Bool) -> Void) -> Void) -> Bool{
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        block { r in
            result = r
            semaphore.signal()
        }
        let timeoutResult = semaphore.wait(timeout: .now() + 1)
        if timeoutResult == .timedOut {
            return false
        }
        return result
    }
}
