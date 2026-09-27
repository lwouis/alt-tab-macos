import Cocoa
import notify
import ScreenCaptureKit.SCShareableContent

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy
// There is no public API to observe permission changes. tccd posts the Darwin notification `com.apple.tcc.access.changed` right
// after each write to its database, for any app and service, in both directions (measured on macOS 27: ~30ms after the toggle;
// zero spontaneous posts while idle). `sandboxd` subscribes to it in its launchd plist, in copies from 2020 already. We re-read both
// permissions on each post, coalesced while a check waits to start. A timed-out read gets three bounded retries; resolved checks do no background work.
// We don't listen to the distributed `com.apple.accessibility.api`: System Settings posts it before tccd writes, see `AccessibilityPermission`.
class SystemPermissions {
    static var preStartupPermissionsPassed = false
    private static var notifyToken = NOTIFY_TOKEN_INVALID
    private static var permissionRetry = PermissionCheckRetry()
    private static let pendingCheckLock = NSLock()
    private static var checkIsPending = false

    static func ensurePermissionsAreGranted() {
        notify_register_dispatch("com.apple.tcc.access.changed", &notifyToken, BackgroundWork.permissionsCheckQueue.strongUnderlyingQueue) { _ in
            checkPermissionsSoon()
        }
        checkPermissionsSoon()
    }

    /// tccd posts once per write, so a burst of writes (a profile install, an app asking for several services) posts
    /// as many times. A check that hasn't started yet will read the latest state anyway, so later requests join it.
    /// The flag clears as the check starts: a write landing during the reads gets a check of its own.
    static func checkPermissionsSoon() {
        guard markCheckPending() else { return }
        BackgroundWork.permissionsCheckQueue.addOperation {
            pendingCheckLock.lock()
            checkIsPending = false
            pendingCheckLock.unlock()
            permissionRetry.begin()
            checkPermissions()
        }
    }

    private static func markCheckPending() -> Bool {
        pendingCheckLock.lock()
        defer { pendingCheckLock.unlock() }
        guard !checkIsPending else { return false }
        checkIsPending = true
        return true
    }

    private static func checkPermissions() {
        AccessibilityPermission.update()
        let recording = ScreenRecordingPermission.update()
        retryUnknownPermissionCheck(recording == nil)
        Logger.debug { "accessibility:\(AccessibilityPermission.status) screenRecording:\(ScreenRecordingPermission.status)" }
        if !preStartupPermissionsPassed {
            checkPermissionsPreStartup()
        } else {
            checkPermissionsPostStartup()
        }
        DispatchQueue.main.async {
            Menubar.refreshPermissionCallout()
            if PermissionsWindow.shared != nil {
                PermissionsWindow.updatePermissionViews()
            }
        }
    }

    private static func retryUnknownPermissionCheck(_ unknown: Bool) {
        guard let delay = permissionRetry.nextDelay(unknown: unknown) else { return }
        let generation = permissionRetry.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            BackgroundWork.permissionsCheckQueue.addOperation {
                guard permissionRetry.generation == generation else { return }
                checkPermissions()
            }
        }
    }

    private static func checkPermissionsPreStartup() {
        if PermissionFlow.isComplete(accessibility: AccessibilityPermission.status, screenRecording: ScreenRecordingPermission.status) {
            DispatchQueue.main.async {
                guard !preStartupPermissionsPassed else { return }
                preStartupPermissionsPassed = true
                PermissionsWindow.shared?.close()
                App.continueAppLaunchAfterPermissionsAreGranted()
            }
        } else {
            DispatchQueue.main.async {
                App.showPermissionsWindow()
            }
        }
    }

    private static func checkPermissionsPostStartup() {
        if AccessibilityPermission.status == .notGranted {
            Logger.error { "Accessibility permission revoked while AltTab was running; restarting" }
            DispatchQueue.main.async { App.restart() }
        }
    }

    /// macOS shows a permission's prompt only while the app has no entry in that list. Once it has one, switched on or
    /// off, the request returns without showing anything, so we open the pane instead. `TCCAccessPreflight` answers 2
    /// while there is no entry, and 0 once there is, either way (measured on macOS 27).
    static func promptOrOpenPane(_ service: String, _ paneUrl: String, _ prompt: @escaping () -> Void) {
        BackgroundWork.permissionsCheckQueue.addOperation {
            let neverAsked = hasNoEntry(service) ?? true
            DispatchQueue.main.async {
                if neverAsked {
                    prompt()
                } else {
                    NSWorkspace.shared.open(URL(string: paneUrl)!)
                }
            }
        }
    }

    /// Whether the app has no entry in `service`'s list, or nil if TCC can't say. `TCCAccessPreflight` answers 2 while
    /// there is no entry, and 0 once there is, switched on or off (measured on macOS 27).
    static func hasNoEntry(_ service: String) -> Bool? {
        return tccAccessPreflight.map { $0(service as CFString, nil) == 2 }
    }

    private typealias TCCAccessPreflight = @convention(c) (CFString, CFDictionary?) -> Int32

    private static let tccAccessPreflight: TCCAccessPreflight? = {
        guard let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY),
              let symbol = dlsym(tcc, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: TCCAccessPreflight.self)
    }()
}

class AccessibilityPermission {
    static var status = PermissionStatus.notGranted

    @discardableResult
    static func update() -> PermissionStatus {
        let previous = status
        status = detect()
        if previous == .notGranted, status == .granted, SystemPermissions.preStartupPermissionsPassed {
            AxObserverRegistry.shared.accessibilityPermissionRestored()
        }
        return status
    }

    // `AXIsProcessTrusted` answers from an in-process cache, refreshed when the distributed `com.apple.accessibility.api`
    // arrives. System Settings posts that notification before tccd writes the change, so the refresh can capture the old
    // value, which then sticks until the next post (measured on macOS 27, in both directions). The private
    // `TCCAccessCheckAuditToken` asks tccd each time (~10ms) and is already correct when `com.apple.tcc.access.changed`
    // arrives. It's exported since at least macOS 10.11; we fall back to `AXIsProcessTrusted` if it's ever gone.
    private static func detect() -> PermissionStatus {
        if let tccAccessCheckAuditToken {
            return tccAccessCheckAuditToken("kTCCServiceAccessibility" as CFString, ownAuditToken, nil) ? .granted : .notGranted
        }
        return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary) ? .granted : .notGranted
    }

    /// The macOS prompt, whose "Open System Settings" button adds AltTab to the Accessibility list
    /// (switched off) and opens the pane on it.
    static func request() {
        SystemPermissions.promptOrOpenPane("kTCCServiceAccessibility", "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary)
        }
    }

    private typealias TCCAccessCheckAuditToken = @convention(c) (CFString, audit_token_t, CFDictionary?) -> Bool

    private static let tccAccessCheckAuditToken: TCCAccessCheckAuditToken? = {
        guard let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_LAZY),
              let symbol = dlsym(tcc, "TCCAccessCheckAuditToken") else { return nil }
        return unsafeBitCast(symbol, to: TCCAccessCheckAuditToken.self)
    }()

    private static let ownAuditToken: audit_token_t = {
        var token = audit_token_t()
        var count = mach_msg_type_number_t(MemoryLayout<audit_token_t>.size / MemoryLayout<natural_t>.size)
        _ = withUnsafeMutablePointer(to: &token) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_AUDIT_TOKEN), $0, &count) }
        }
        return token
    }()
}

class ScreenRecordingPermission {
    static var status = PermissionStatus.notGranted

    @discardableResult
    static func update() -> PermissionStatus? {
        let detected = detect()
        if let detected { status = detected }
        return detected
    }

    // `CGPreflightScreenCaptureAccess` and tccd's own checks keep answering "denied" after a mid-session grant, but
    // WindowServer applies the change at once: other apps' window titles appear or vanish, and SCShareableContent works
    // without a relaunch (measured on macOS 27). So titles are the cheap, silent read; SCShareableContent confirms when
    // no other app has a titled window.
    private static func detect() -> PermissionStatus? {
        if otherAppsWindowTitlesAreVisible() {
            return .granted
        }
        // The user opted out of the prompt (#5548), so we must not call isGrantedOnSomeDisplay(): it shows the system
        // prompt when ungranted. The skip flag only downgrades .notGranted to .skipped to suppress nagging; it never
        // masks a real grant (#5739). CGPreflightScreenCaptureAccess is frozen per-process, so it only covers the
        // launch state; a later grant is seen through the titles above.
        guard !Preferences.screenRecordingPermissionSkipped else {
            return CGPreflightScreenCaptureAccess() ? .granted : .skipped
        }
        // No entry means not granted. Asking anyway shows the macOS prompt, which puts AltTab back in the list the moment
        // the user removes it. Prompting is the Grant button's job
        if SystemPermissions.hasNoEntry("kTCCServiceScreenCapture") == true {
            return .notGranted
        }
        return isGrantedOnSomeDisplay().map { $0 ? .granted : .notGranted }
    }

    /// Same prompt as `AccessibilityPermission.request()`, for the Screen Recording list.
    static func request() {
        SystemPermissions.promptOrOpenPane("kTCCServiceScreenCapture", "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            CGRequestScreenCaptureAccess()
        }
    }

    /// The user chose "Continue without thumbnails". Recorded as a preference, which `detect()` then
    /// reports as `.skipped` — enough for `PermissionFlow` to move past the step, and never enough
    /// to mask a real grant that arrives later.
    static func waive() {
        Preferences.set("screenRecordingPermissionSkipped", "true")
        SystemPermissions.checkPermissionsSoon()
    }

    /// The user changed their mind after skipping. The step turns live again, so the window offers to grant
    /// or to skip once more.
    static func unwaive() {
        Preferences.remove("screenRecordingPermissionSkipped")
        SystemPermissions.checkPermissionsSoon()
    }

    // Without the permission, WindowServer blanks the title of every normal window from another process. Some
    // system windows on other layers keep theirs, hence the layer filter
    private static func otherAppsWindowTitlesAreVisible() -> Bool {
        let ownPid = ProcessInfo.processInfo.processIdentifier
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains {
            ($0[kCGWindowOwnerPID as String] as? pid_t) != ownPid
                && ($0[kCGWindowLayer as String] as? Int) == 0
                && !(($0[kCGWindowName as String] as? String) ?? "").isEmpty
        }
    }

    // note: shows the system prompt if there's no permission
    private static func isGrantedOnSomeDisplay() -> Bool? {
        if #available(macOS 12.3, *) {
            return checkWithSCShareableContent()
        } else {
            let mainDisplayID = CGMainDisplayID()
            let mainResult = checkWithCGDisplayStream(mainDisplayID)
            var unknown = mainResult == nil
            if mainResult == true {
                return true
            }
            // maybe the main screen can't produce a CGDisplayStream, but another screen can
            // a positive on any screen must mean that the permission is granted; we try on the other screens
            for screen in NSScreen.screens {
                if let id = screen.number(), id != mainDisplayID {
                    let result = checkWithCGDisplayStream(id)
                    unknown = unknown || result == nil
                    if result == true {
                        return true
                    }
                }
            }
            return unknown ? nil : false
        }
    }

    @available(macOS 12.3, *)
    private static func checkWithSCShareableContent() -> Bool? {
        return runWithTimeout { completion in
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { shareableContent, error in
                // this callback runs on a GCD queue, not on the thread that called getWithCompletionHandler
                if #available(macOS 14.0, *), let shareableContent, error == nil {
                    BackgroundWork.screenshotsQueue.addOperation {
                        WindowCaptureScreenshots.cachedSCWindows.withLock { $0 = shareableContent.windows }
                    }
                }
                completion(error != nil ? false : (shareableContent != nil))
            }
        }
    }

    private static func checkWithCGDisplayStream(_ id: CGDirectDisplayID) -> Bool? {
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

    private static func runWithTimeout(_ block: @escaping (@escaping (Bool) -> Void) -> Void) -> Bool? {
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
            return nil
        }
        return result
    }
}
