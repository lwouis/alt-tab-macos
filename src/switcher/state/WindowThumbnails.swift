import Cocoa

/// Off-main-thread screenshot capture for window thumbnails, plus the
/// "preview the selected window" overlay shown next to the switcher panel.
enum WindowThumbnails {
    static func previewSelectedIfNeeded() {
        if let session = SwitcherSession.current, ScreenRecordingPermission.status == .granted
               && Preferences.effectivePreviewSelectedWindow(session.shortcutIndex)
               && TilesPanel.shared.isKeyWindow,
           let window = Windows.selectedWindow(),
           let id = window.cgWindowId,
           let thumbnail = window.thumbnail,
           let position = window.position,
           let size = window.size {
            PreviewPanel.show(id, thumbnail, position, size)
        } else {
            PreviewPanel.shared.orderOut(nil)
        }
    }

    // dispatch screenshot requests off the main-thread, then wait for completion
    static func refreshAsync(_ windows: [Window], _ source: RefreshCausedBy, windowRemoved: Bool = false, prioritizedIds: Set<CGWindowID>? = nil) {
        let shortcutIndex = SwitcherSession.activeShortcutIndex
        guard (!windows.isEmpty || windowRemoved) && ScreenRecordingPermission.status == .granted
               && !ScreenLockEvents.isScreenLocked
               && (!Appearance.hideThumbnails || Preferences.effectivePreviewSelectedWindow(shortcutIndex))
               && (Preferences.captureWindowsInBackground || SwitcherSession.isActive) else { return }
        var eligibleWindows = [Window]()
        for window in windows {
            if !window.isWindowlessApp, let cgWindowId = window.cgWindowId, cgWindowId != CGWindowID(bitPattern: -1) {
                eligibleWindows.append(window)
            }
        }
        guard (!eligibleWindows.isEmpty || windowRemoved) else { return }
        if #available(macOS 14.0, *),
           // mitigate macOS 15 bugs with ScreenCapture Kit (see https://github.com/lwouis/alt-tab-macos/issues/5190)
           ProcessInfo.processInfo.operatingSystemVersion.majorVersion != 15 {
            WindowCaptureScreenshots.oneTimeScreenshots(eligibleWindows, source, prioritizedIds: prioritizedIds)
        } else {
            WindowCaptureScreenshotsPrivateApi.oneTimeScreenshots(eligibleWindows, source, prioritizedIds: prioritizedIds)
        }
    }
}
