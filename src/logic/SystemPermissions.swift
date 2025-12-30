import Cocoa
import ScreenCaptureKit.SCShareableContent

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy
class SystemPermissions {
    static var preStartupPermissionsPassed = false
    private static var timer: DispatchSourceTimer!

    static func ensurePermissionsAreGranted() {
        timer = DispatchSource.makeTimerSource(queue: BackgroundWork.permissionsCheckOnTimerQueue.strongUnderlyingQueue)
        timer.setEventHandler(handler: checkPermissionsOnTimer)
        setImmediateTimer()
        timer.resume()
    }

    private static func checkPermissionsOnTimer() {
        AccessibilityPermission.update()
        ScreenRecordingPermission.update()
        if !preStartupPermissionsPassed {
            checkPermissionsPreStartup()
        } else {
            checkPermissionsPostStartup()
        }
        DispatchQueue.main.async {
            Menubar.togglePermissionCallout(ScreenRecordingPermission.status == .skipped)
            App.app.permissionsWindow.updatePermissionViews()
        }
    }

    private static func checkPermissionsPreStartup() {
        Logger.info { "accessibility:\(AccessibilityPermission.status) screenRecording:\(ScreenRecordingPermission.status)" }
        if AccessibilityPermission.status != .notGranted && ScreenRecordingPermission.status != .notGranted {
            DispatchQueue.main.async {
                preStartupPermissionsPassed = true
                App.app.permissionsWindow?.close()
                setInfrequentTimer()
                App.app.continueAppLaunchAfterPermissionsAreGranted()
            }
        } else {
            DispatchQueue.main.async {
                App.app.permissionsWindow.show()
            }
        }
    }

    private static func checkPermissionsPostStartup() {
        Logger.debug { "accessibility:\(AccessibilityPermission.status) screenRecording:\(ScreenRecordingPermission.status)" }
        if AccessibilityPermission.status == .notGranted {
            Logger.error { "Accessibility permission revoked while AltTab was running; restarting" }
            DispatchQueue.main.async { App.app.restart() }
        }
        if ScreenRecordingPermission.status == .notGranted {
            // permission check may yield a false negative during wake-up; we restart after 2 negative checks
            if ScreenRecordingPermission.flakyCounter >= 2 {
                Logger.error { "Screen-recording permission revoked while AltTab was running (checked 2 times); restarting" }
                DispatchQueue.main.async { App.app.restart() }
            } else {
                ScreenRecordingPermission.flakyCounter += 1
            }
        } else {
            ScreenRecordingPermission.flakyCounter = 0
        }
    }

    static func setInfrequentTimer() {
        timer.schedule(deadline: .now() + 5, repeating: 5, leeway: .seconds(1))
    }

    static func setFrequentTimer() {
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(500))
    }

    private static func setImmediateTimer() {
        timer.schedule(deadline: .now(), repeating: .never, leeway: .never)
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
                // this callback runs on a GCD queue, not on the thread that called getWithCompletionHandler
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

    private static func runWithTimeout(_ block: @escaping (@escaping (Bool) -> Void) -> Void) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        BackgroundWork.permissionsSystemCallsQueue.addOperation {
            block { r in
                result = r
                semaphore.signal()
            }
        }
        let timeoutResult = semaphore.wait(timeout: .now() + 6)
        if timeoutResult == .timedOut {
            Logger.error { "Screen-recording permission call timed out after 6s" }
            return false
        }
        return result
    }
}
