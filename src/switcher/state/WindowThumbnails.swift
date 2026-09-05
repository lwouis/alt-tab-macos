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
           // the session's full-res frame if already fetched, else the thumbnail upscaled while
           // fetchPreviewFrames' capture is in flight (it swaps in via PreviewPanel.updateIfShowing)
           let preview = session.previewFrame(id) ?? window.thumbnail,
           let position = window.position,
           let size = window.size {
            PreviewPanel.show(id, preview, position, size)
        } else {
            PreviewPanel.hide()
        }
    }

    /// ≤1 background capture of a given focused window per 800ms.
    static let focusedCaptureThrottler = ThrottlerWithKey(delayInMs: 800)

    /// Capture the just-focused window's thumbnail in the BACKGROUND (switcher closed). When that window later
    /// backgrounds as a new tab takes over, its tile is kept visible (`windowsHeldVisibleForTab`) but a
    /// backgrounded window can't be screenshotted — and with the switcher closed it may never have been
    /// captured — so without this it renders as the app icon through the ~640ms new-tab discovery gap. Grabbing
    /// its thumbnail while it's still frontmost lets that tile show a real screenshot instead. No-op while the
    /// switcher is open (the normal refresh captures then); throttled per wid; obeys the screenshot guards below.
    static func captureFocusedInBackground(_ window: Window) {
        guard !SwitcherSession.isActive, Preferences.captureWindowsInBackground,
              let wid = window.cgWindowId, wid != CGWindowID(bitPattern: -1) else { return }
        focusedCaptureThrottler.throttleOrProceed(key: "\(wid)") {
            refreshAsync([window], .refreshUiAfterExternalEvent)
        }
    }

    /// How many pixels a capture of a window that size should come back with. Shared by the capture request
    /// (which configures ScreenCaptureKit with it) and by `acceptCapture` below, so what we ask for and what
    /// we expect back can't drift apart.
    /// `fullRes` = no thumbnail downscale: full resolution is only for windows the Preview panel may
    /// imminently show (the selected window and its cycling neighbors, decided by the caller). Capturing
    /// every window full-res floods the system capture path and can wedge screenshots machine-wide (#5861).
    static func capturePixelSize(_ size: CGSize, _ scaleFactor: CGFloat, _ fullRes: Bool) -> CGSize? {
        // window.size is the logical size and doesn't change with scaleFactor. We need to correct for this as we need to capture more or less pixels depending on DPI.
        let pixels = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        guard pixels.width > 0, pixels.height > 0 else { return nil }
        if fullRes { return pixels }
        // capture screenshots as small as needed for the thumbnails
        let maxSize = TilesPanel.maxPossibleThumbnailSize
        guard maxSize.width > 0, maxSize.height > 0 else { return nil }
        let scale = min(1.0, maxSize.width / pixels.width, maxSize.height / pixels.height)
        return CGSize(width: (pixels.width * scale).rounded(), height: (pixels.height * scale).rounded())
    }

    /// The backing scale of the screen the window is on; captures are configured in pixels. Main-thread only
    /// (`Screens.all` and `window.screenId` are plain mutable state owned by main).
    static func captureScaleFactor(_ window: Window) -> CGFloat {
        if let screenId = window.screenId, let screen = Screens.all[screenId] {
            return screen.backingScaleFactor
        }
        return NSScreen.preferred.backingScaleFactor
    }

    /// Windows whose restore animation is still running. Nothing captures them until it ends.
    private static var restoringWids = Set<CGWindowID>()
    /// How long the OS takes to draw a window back out of the Dock. Measured on macOS 26 (and unchanged for
    /// as long as the genie has existed): the WindowServer's minimized tag clears ~644ms after the order-in
    /// that starts the animation. Rounded up, since capturing a beat late costs nothing and capturing a beat
    /// early costs the frame.
    private static let restoreAnimationDuration = 0.7

    /// Hold this window's captures until its restore animation is over, then take one.
    /// A window being un-minimized is drawn scaled down for the whole animation, so a capture taken inside it
    /// is a mini window in a transparent frame — and the un-minimize is exactly what triggers a re-capture
    /// (the WindowServer geometry query that follows the order-in), so without this the switcher reliably
    /// replaces a correct thumbnail with that one. `refreshAsync` skips a window while it is in here, which
    /// covers the captures the un-minimize itself sets off AND anything else asking meanwhile (a show, a
    /// neighbouring event); the one capture below stands in for all of them.
    static func deferCaptureUntilRestoreEnds(_ window: Window) {
        guard let wid = window.cgWindowId, !restoringWids.contains(wid) else { return }
        restoringWids.insert(wid)
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreAnimationDuration) { [weak window] in
            restoringWids.remove(wid)
            guard let window else { return }
            // This capture obeys the background-capture setting. If it is dropped, the next show captures
            // every window.
            refreshAsync([window], .refreshUiAfterExternalEvent)
        }
    }

    /// wid → how many partial frames in a row we refused. Cleared as soon as one is accepted.
    private static var partialFrameRetries = [CGWindowID: Int]()
    private static let maxPartialFrameRetries = 3
    /// long enough to outlast the rest of a restore animation (~0.6s over 3 retries), short enough that a
    /// thumbnail the user is looking at is only briefly stale
    private static let partialFrameRetryDelay = 0.25
    /// captures land a pixel or two off the size we asked for; only a materially smaller frame is partial
    private static let partialFrameRatio = 0.9

    /// The OS can hand us a frame drawn much smaller than the window it is of, because it was still animating
    /// when it drew: un-minimizing is the reported case, where the restore animation is still running when the
    /// capture it triggered is taken, and the tile turns into a mini window floating in transparent pixels.
    /// Compare what came back against what a capture of this window should measure now — the window's CURRENT
    /// size, not the one snapshotted when the request was queued, so a request made off a mid-animation frame
    /// is caught too. Main-thread only (it reads live `Window` state).
    static func isPartialFrame(_ window: Window, _ contents: CALayerContents, fullRes: Bool) -> Bool {
        // Only the ScreenCaptureKit path is judged: there the capture is configured with the exact pixel size
        // we expect back, so a smaller frame is the OS's own admission that it drew a partial one. Below
        // macOS 26 captures go through `CGSHWCaptureWindowList`, which sizes its output itself — there is no
        // exact expectation to compare against, and a wrong one would loop every capture through the retries.
        guard #available(macOS 26.0, *) else { return false }
        guard let size = window.size, let actual = contents.size(),
              let expected = capturePixelSize(size, captureScaleFactor(window), fullRes)
        else { return false }
        let partial = actual.width < expected.width * partialFrameRatio
            || actual.height < expected.height * partialFrameRatio
        if partial { Logger.debug { "\(window.debugId) partial frame \(actual) expected \(expected) fullRes:\(fullRes)" } }
        return partial
    }

    /// Whether a freshly captured thumbnail is worth showing. A stale-but-correct thumbnail beats a partial
    /// frame, so that one is dropped and another capture asked for a beat later. Bounded by
    /// `maxPartialFrameRetries`, then the frame is taken as-is: "smaller than expected" is a heuristic, and a
    /// tile stuck forever on a stale thumbnail would be worse than one that is briefly off.
    static func acceptCapture(_ window: Window, _ contents: CALayerContents) -> Bool {
        guard let wid = window.cgWindowId else { return true }
        guard isPartialFrame(window, contents, fullRes: false) else {
            partialFrameRetries[wid] = nil
            return true
        }
        let retries = partialFrameRetries[wid] ?? 0
        guard retries < maxPartialFrameRetries else {
            Logger.debug { "\(window.debugId) giving up on partial frames after \(retries) retries" }
            partialFrameRetries[wid] = nil
            return true
        }
        partialFrameRetries[wid] = retries + 1
        // This re-capture obeys the background-capture setting. A closed switcher drops it when background
        // capture is disabled.
        DispatchQueue.main.asyncAfter(deadline: .now() + partialFrameRetryDelay) { [weak window] in
            guard let window else { return }
            refreshAsync([window], .refreshUiAfterExternalEvent)
        }
        return false
    }

    /// Dispatch screenshot requests off the main-thread. These captures are thumbnail-scale ONLY (on
    /// macOS 26+): full-resolution frames for the Preview panel are fetched separately and just-in-time
    /// by `fetchPreviewFrames` into the session's capped cache, so idle RAM stays small and a show
    /// doesn't burst N full-res captures at the system capture path (#5861).
    static func refreshAsync(_ windows: [Window], _ source: RefreshCausedBy, windowRemoved: Bool = false, prioritizedIds: Set<CGWindowID>? = nil) {
        guard (!windows.isEmpty || windowRemoved) && ScreenRecordingPermission.status == .granted
               && !ScreenLockEvents.isScreenLocked
               && Preferences.anyShortcutShowsWindowCaptures else { return }
        let backend = WindowCaptureRouting.backend(
            macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            kind: .thumbnail,
            hasTrustedGrantHistory: ScreenRecordingPermission.hasTrustedGrantHistory,
            switcherIsActive: SwitcherSession.isActive,
            backgroundCaptureIsEnabled: Preferences.captureWindowsInBackground)
        guard let backend else { return }
        var eligibleWindows = [Window]()
        for window in windows {
            if !window.isWindowlessApp, let cgWindowId = window.cgWindowId, cgWindowId != CGWindowID(bitPattern: -1),
               // mid-restore-animation the OS draws the window scaled down; `deferCaptureUntilRestoreEnds`
               // takes the one capture that matters once it is over
               !restoringWids.contains(cgWindowId) {
                eligibleWindows.append(window)
            }
        }
        guard (!eligibleWindows.isEmpty || windowRemoved) else { return }
        switch backend {
            case .screenCaptureKit:
                if #available(macOS 14.0, *) {
                    WindowCaptureScreenshots.oneTimeScreenshots(eligibleWindows, source, prioritizedIds: prioritizedIds)
                }
            case .windowServer:
                WindowCaptureScreenshotsPrivateApi.oneTimeScreenshots(eligibleWindows, source, prioritizedIds: prioritizedIds)
        }
    }

    /// Fetch just-in-time full-resolution Preview frames for the selected window and its ±2 cycling
    /// neighbors (so quick Tab presses land on a sharp Preview). Frames go to the session's capped cache,
    /// not `Window.thumbnail`, and die with the session. Called on show and on every selection move; the
    /// cache and the per-wid throttler keep re-requests cheap. No-op below macOS 26, where
    /// CGSHWCaptureWindowList always captures full-size, so `Window.thumbnail` is already sharp.
    static func fetchPreviewFrames() {
        guard #available(macOS 26.0, *), let session = SwitcherSession.current,
              ScreenRecordingPermission.status == .granted, !ScreenLockEvents.isScreenLocked,
              Preferences.effectivePreviewSelectedWindow(session.shortcutIndex) else { return }
        let backend = WindowCaptureRouting.backend(
            macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            kind: .focusedPreview,
            hasTrustedGrantHistory: ScreenRecordingPermission.hasTrustedGrantHistory,
            switcherIsActive: true,
            backgroundCaptureIsEnabled: Preferences.captureWindowsInBackground)
        guard backend == .screenCaptureKit else { return }
        let missingIds = Windows.selectedNeighborhoodIds().filter { !session.hasPreviewFrame($0) && !restoringWids.contains($0) }
        guard !missingIds.isEmpty else { return }
        let windowsToFetch = Windows.list.filter { $0.cgWindowId.map { missingIds.contains($0) } ?? false }
        let selectedId = Windows.selectedWindow()?.cgWindowId
        WindowCaptureScreenshots.oneTimeScreenshots(windowsToFetch, .refreshOnlyThumbnailsAfterShowUi,
            prioritizedIds: selectedId.map { [$0] } ?? [], fullRes: true)
    }
}
