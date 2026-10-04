import Cocoa

// Main-thread owner of the protection mode and capture publication checks.
enum StageManagerCaptureGuard {
    private static let windowManagerDefaults = UserDefaults(suiteName: "com.apple.WindowManager")
    private static var mode = StageManagerCaptureMode()
    private(set) static var focusGeneration: UInt64 = 0
    private static var retries = [CGWindowID: Int]()

    static func focusChanged() {
        focusGeneration &+= 1
        retries.removeAll()
    }

    static func currentMode() -> StageManagerCaptureMode {
        let enabled: Bool
        if #available(macOS 26.0, *) {
            enabled = Preferences.preventDistortedStageManagerPreviews
                && (windowManagerDefaults?.object(forKey: "GloballyEnabled") as? Bool ?? false)
        } else {
            enabled = false
        }
        let wasEnabled = mode.enabled
        mode.update(enabled)
        if wasEnabled != enabled { retries.removeAll() }
        if enabled && !wasEnabled {
            // Unverified frames may contain the sidebar transform; verified ordinary captures survive.
            for window in Windows.list where !window.stageManagerThumbnailIsTrusted {
                window.thumbnail = nil
            }
            SwitcherSession.current?.removeUntrustedPreviewFrames()
            PreviewPanel.refreshAfterProtectionChange()
            DispatchQueue.main.async { App.refreshOpenUiAfterExternalEvent([]) }
        }
        return mode
    }

    static func isFocused(_ window: Window) -> Bool {
        Applications.frontmostPid == window.application.pid
            && window.application.focusedWindow === window
            && !window.isMinimized && !window.isHidden && !window.isTabbed
    }

    static func allowsPublication(_ window: Window, _ capturedMode: StageManagerCaptureMode, _ capturedFocusGeneration: UInt64) -> Bool {
        let current = currentMode()
        guard let wid = window.cgWindowId,
              Windows.byWindowId[wid] === window else { return false }
        return StageManagerCapturePolicy.allowsPublication(capturedMode, current,
            capturedFocus: capturedFocusGeneration, currentFocus: focusGeneration, isFocused: isFocused(window))
    }

    static func captureAccepted(_ wid: CGWindowID) {
        retries[wid] = nil
    }

    static func retryCapture(_ window: Window, _ capturedMode: StageManagerCaptureMode, _ capturedFocusGeneration: UInt64) {
        guard capturedMode.enabled, allowsPublication(window, capturedMode, capturedFocusGeneration),
              let wid = window.cgWindowId, retries[wid, default: 0] < 3 else { return }
        retries[wid, default: 0] += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak window] in
            guard let window, allowsPublication(window, capturedMode, capturedFocusGeneration) else { return }
            WindowThumbnails.refreshAsync([window], .refreshUiAfterExternalEvent, force: true)
        }
    }

    static func preferenceChanged() {
        _ = currentMode()
        App.refreshOpenUiAfterExternalEvent(Windows.list)
    }
}
