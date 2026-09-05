import Cocoa
import ScreenCaptureKit.SCShareableContent

// macOS has some privacy restrictions. The user needs to grant certain permissions, app by app, in System Preferences > Security & Privacy
class SystemPermissions {
    static var preStartupPermissionsPassed = false
    private static var timer: DispatchSourceTimer!
    private static var timerIsFrequent = false
    // After permissions are granted at startup, we listen for `com.apple.accessibility.api`
    // on the distributed notification center to learn about revocation, instead of polling
    // every 5s. The notification name is undocumented by Apple and its firing behaviour across
    // every System Settings action (toggle off, remove from list, etc.) is not reliably
    // characterised in public sources, so we also keep a sparse 60s backstop timer below.
    // Infra requirements: NSDistributedNotificationCenter since 10.15 ignores nil-name
    // observers (we pass a name) and since macOS 15 silently fails for unsigned binaries
    // (AltTab is Developer ID signed). macOS 13+ has a known bug where `AXIsProcessTrusted`
    // can return stale values right after a toggle; we call `AccessibilityPermission.update()`
    // which re-runs the API rather than caching.
    private static let axRevokeNotificationName = "com.apple.accessibility.api"
    private static var distributedObserver: NSObjectProtocol?

    static func ensurePermissionsAreGranted() {
        timer = DispatchSource.makeTimerSource(queue: BackgroundWork.permissionsCheckOnTimerQueue.strongUnderlyingQueue)
        timer.setEventHandler(handler: checkPermissionsOnTimer)
        setImmediateTimer()
        timer.resume()
    }

    private static func startListeningForDistributedRevoke() {
        guard distributedObserver == nil else { return }
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(axRevokeNotificationName),
            object: nil,
            queue: nil
        ) { _ in
            BackgroundWork.permissionsCheckOnTimerQueue.addOperation {
                if AccessibilityPermission.update() == .notGranted {
                    Logger.error { "Accessibility permission revoked (distributed notification); restarting" }
                    DispatchQueue.main.async { App.restart() }
                }
            }
        }
    }

    private static func checkPermissionsOnTimer() {
        AccessibilityPermission.update()
        let isPermissionsWindowVisible = PermissionsWindow.shared?.isVisible ?? false
        if !preStartupPermissionsPassed || isPermissionsWindowVisible {
            ScreenRecordingPermission.update()
        }
        Logger.debug { "accessibility:\(AccessibilityPermission.status) screenRecording:\(ScreenRecordingPermission.status)" }
        if !preStartupPermissionsPassed {
            checkPermissionsPreStartup()
        } else {
            checkPermissionsPostStartup()
            if isPermissionsWindowVisible && !timerIsFrequent {
                setFrequentTimer()
            } else if !isPermissionsWindowVisible && timerIsFrequent {
                setInfrequentTimer()
            }
        }
        DispatchQueue.main.async {
            Menubar.refreshPermissionCallout()
            if PermissionsWindow.shared != nil {
                PermissionsWindow.updatePermissionViews()
            }
        }
    }

    private static func checkPermissionsPreStartup() {
        if AccessibilityPermission.status != .notGranted && ScreenRecordingPermission.canContinueLaunch {
            DispatchQueue.main.async {
                preStartupPermissionsPassed = true
                PermissionsWindow.shared?.close()
                setInfrequentTimer()
                startListeningForDistributedRevoke()
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

    // Post-startup, with the distributed-notification listener wired up, we only need a sparse
    // backstop poll. The notification's firing behaviour isn't fully characterised, so the 60s
    // timer is the recovery path for cases where it doesn't fire.
    static func setInfrequentTimer() {
        timerIsFrequent = false
        if preStartupPermissionsPassed && distributedObserver != nil {
            timer.schedule(deadline: .now() + 60, repeating: 60, leeway: .seconds(10))
            return
        }
        timer.schedule(deadline: .now() + 5, repeating: 5, leeway: .seconds(1))
    }

    static func setFrequentTimer() {
        timerIsFrequent = true
        timer.schedule(deadline: .now(), repeating: 0.5, leeway: .milliseconds(500))
    }

    private static func setImmediateTimer() {
        timerIsFrequent = false
        timer.schedule(deadline: .now(), repeating: .never, leeway: .never)
    }
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

    private static func detect() -> PermissionStatus {
        return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue(): false] as CFDictionary) ? .granted : .notGranted
    }
}

class ScreenRecordingPermission {
    static var status = PermissionStatus.notGranted
    private static var authorization = ScreenRecordingAuthorizationModel(wasGranted: Preferences.screenRecordingPermissionWasGranted)
    private static var confirmationWorkItems = [DispatchWorkItem]()

    static var canContinueLaunch: Bool {
        status != .notGranted || authorization.wasGranted
    }

    static var hasTrustedGrantHistory: Bool {
        authorization.wasGranted
    }

    static var shouldShowPassiveReview: Bool {
        status == .notGranted || status == .skipped
    }

    @discardableResult
    static func update() -> PermissionStatus {
        guard confirmationWorkItems.isEmpty else { return status }
        if #available(macOS 10.15, *) {
            if Preferences.screenRecordingPermissionSkipped {
                if CGPreflightScreenCaptureAccess() {
                    receive(.granted)
                } else {
                    cancelConfirmations()
                    status = .skipped
                }
            } else if authorization.wasGranted {
                receive(nonPromptingProbe())
            } else {
                receive(firstUseProbe())
            }
        } else {
            receive(.granted)
        }
        return status
    }

    static func reportCaptureFailure(_ error: Error) {
        guard #available(macOS 10.15, *), authorization.wasGranted else { return }
        let nsError = error as NSError
        Logger.error { "ScreenCaptureKit capture failed domain:\(nsError.domain) code:\(nsError.code)" }
        BackgroundWork.permissionsCheckOnTimerQueue.addOperation {
            guard confirmationWorkItems.isEmpty else { return }
            // A successful preflight proves that the capture error is not a permission revocation.
            // Keep the trusted state. Capture routing applies its own cooldown.
            guard !CGPreflightScreenCaptureAccess() else { return }
            receive(.temporarilyUnavailable(.screenCaptureKit(domain: nsError.domain, code: nsError.code)))
        }
    }

    private static func nonPromptingProbe() -> ScreenRecordingProbeResult {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess() ? .granted : .notGranted
        }
        return .granted
    }

    // This first-use probe can show the normal macOS permission prompt. No post-grant or background
    // path calls it. Known grants use only CGPreflightScreenCaptureAccess above.
    private static func firstUseProbe() -> ScreenRecordingProbeResult {
        if #available(macOS 12.3, *) {
            return checkWithSCShareableContent()
        } else {
            let mainDisplayID = CGMainDisplayID()
            var lastFailure = checkWithCGDisplayStream(mainDisplayID)
            if lastFailure == .granted { return .granted }
            for screen in NSScreen.screens {
                if let id = screen.number(), id != mainDisplayID {
                    let result = checkWithCGDisplayStream(id)
                    if result == .granted { return .granted }
                    if case .temporarilyUnavailable = result { lastFailure = result }
                }
            }
            return lastFailure
        }
    }

    @available(macOS 12.3, *)
    private static func checkWithSCShareableContent() -> ScreenRecordingProbeResult {
        return runWithTimeout { completion in
            ScreenCaptureCoordinator.shared.submit { captureCompletion in
                SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { shareableContent, error in
                    captureCompletion()
                    if #available(macOS 14.0, *), let shareableContent, error == nil {
                        BackgroundWork.screenshotsQueue.addOperation {
                            WindowCaptureScreenshots.cachedSCWindows.withLock { $0 = shareableContent.windows }
                        }
                    }
                    if let error {
                        let nsError = error as NSError
                        if nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.Code.userDeclined.rawValue {
                            completion(.notGranted)
                        } else {
                            completion(.temporarilyUnavailable(.screenCaptureKit(domain: nsError.domain, code: nsError.code)))
                        }
                    } else {
                        completion(shareableContent == nil
                            ? .temporarilyUnavailable(.screenCaptureKit(domain: SCStreamErrorDomain, code: -1))
                            : .granted)
                    }
                }
            }
        }
    }

    private static func checkWithCGDisplayStream(_ id: CGDirectDisplayID) -> ScreenRecordingProbeResult {
        return runWithTimeout { completion in
            let displayStream = CGDisplayStream(
                dispatchQueueDisplay: id,
                outputWidth: 1,
                outputHeight: 1,
                pixelFormat: Int32(kCVPixelFormatType_32BGRA),
                properties: nil,
                queue: .global()
            ) { _, _, _, _ in }
            completion(displayStream == nil ? .notGranted : .granted)
        }
    }

    private static func runWithTimeout(_ block: @escaping (@escaping (ScreenRecordingProbeResult) -> Void) -> Void) -> ScreenRecordingProbeResult {
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var result: ScreenRecordingProbeResult?
        BackgroundWork.permissionsSystemCallsQueue.addOperation {
            block { r in
                lock.lock()
                result = r
                lock.unlock()
                semaphore.signal()
            }
        }
        let timeoutResult = semaphore.wait(timeout: .now() + 6)
        if timeoutResult == .timedOut {
            Logger.error { "Screen-recording permission call timed out after 6s" }
            return .temporarilyUnavailable(.timeout)
        }
        lock.lock()
        defer { lock.unlock() }
        return result ?? .temporarilyUnavailable(.timeout)
    }

    private static func receive(_ result: ScreenRecordingProbeResult) {
        if case let .temporarilyUnavailable(failure) = result {
            Logger.error { "Screen-recording permission probe is temporarily unavailable: \(failure)" }
        }
        let effects = authorization.receive(result)
        switch authorization.state {
            case .unknown: status = .temporarilyUnavailable
            case .granted: status = .granted
            case .temporarilyUnavailable: status = .temporarilyUnavailable
            case .needsUserReview: status = .notGranted
        }
        apply(effects)
        refreshPermissionUi()
    }

    private static func apply(_ effects: [ScreenRecordingAuthorizationEffect]) {
        for effect in effects {
            switch effect {
                case .persistGrant:
                    Preferences.set("screenRecordingPermissionWasGranted", "true", false)
                case let .scheduleConfirmation(after: delay):
                    scheduleConfirmation(after: delay)
                case .cancelConfirmations:
                    cancelConfirmations()
                case .openOnboarding:
                    break
                case .showPassiveReview:
                    cancelConfirmations()
            }
        }
    }

    private static func scheduleConfirmation(after delay: TimeInterval) {
        let workItem = DispatchWorkItem {
            receive(nonPromptingProbe())
        }
        confirmationWorkItems.append(workItem)
        BackgroundWork.permissionsCheckOnTimerQueue.strongUnderlyingQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private static func cancelConfirmations() {
        confirmationWorkItems.forEach { $0.cancel() }
        confirmationWorkItems.removeAll()
    }

    private static func refreshPermissionUi() {
        DispatchQueue.main.async {
            Menubar.refreshPermissionCallout()
            if PermissionsWindow.shared != nil { PermissionsWindow.updatePermissionViews() }
        }
    }
}
