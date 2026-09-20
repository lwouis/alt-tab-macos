import Cocoa
import ScreenCaptureKit

@available(macOS 14.0, *)
class WindowCaptureScreenshots {
    // SCShareableContent.getExcludingDesktopWindows is expensive for the OS; we cache as much as possible.
    // Wrapped in ConcurrentArray because reads and writes happen from different operations on
    // BackgroundWork.screenshotsQueue, which is concurrent (maxConcurrentOperationCount = 8).
    static let cachedSCWindows = ConcurrentArray<SCWindow>()
    private static let shareableContentLock = NSLock()
    private static let maxPendingShareableCaptures = 256
    private static var shareableCaptures = CaptureDiscovery<PendingCapture>(capacity: maxPendingShareableCaptures)
    private static let discoveryTimeoutSeconds = 5.0
    #if DEBUG
    private static var dropNextDiscovery = false

    static func dropNextDiscoveryForQa() {
        shareableContentLock.lock()
        dropNextDiscovery = true
        cachedSCWindows.withLock { $0.removeAll() }
        shareableContentLock.unlock()
    }
    #endif

    struct CaptureRequest {
        let window: Window
        let size: CGSize
        let scaleFactor: CGFloat
        let isFullscreen: Bool
        let fullRes: Bool
    }

    private struct PendingCapture {
        let request: CaptureRequest
        let source: RefreshCausedBy
        let prioritized: Bool
    }

    /// `fullRes: false` = thumbnail-scale captures, delivered to `Window.thumbnail`.
    /// `fullRes: true` = full-resolution Preview frames, delivered to the session's capped cache (#5861).
    static func oneTimeScreenshots(_ windowsToScreenshot: [Window], _ source: RefreshCausedBy, prioritizedIds: Set<CGWindowID>? = nil, fullRes: Bool = false) {
        // Snapshot Window state on the main thread before hopping to screenshotsQueue. Windows.byWindowId,
        // Window.size, Window.screenId, Screens.all, and NSScreen.preferred are plain (lock-free) dictionaries
        // and mutable properties touched only on main; reading them from screenshotsQueue (8-way concurrent)
        // races with main-thread mutation and can corrupt the heap.
        // Trade-off: size is fixed at call time, so a window resized between snapshot and capture will be captured
        // at the old size. Acceptable because the next refresh will re-snapshot.
        var requests = [CGWindowID: CaptureRequest]()
        for window in windowsToScreenshot {
            guard let wid = window.cgWindowId, let size = window.size else { continue }
            let scaleFactor = WindowThumbnails.captureScaleFactor(window)
            requests[wid] = CaptureRequest(window: window, size: size, scaleFactor: scaleFactor,
                isFullscreen: window.isFullscreen, fullRes: fullRes)
        }
        guard !requests.isEmpty else { return }
        let prioritized = prioritizedIds ?? []
        BackgroundWork.screenshotsQueue.addOperation {
            guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
            let (cachedWindows, notCachedWindows) = sortCachedAndNotCached(Array(requests.keys))
            Logger.debug { "cached:\(cachedWindows.map { $0.windowID }) notCached:\(notCachedWindows)" }
            // iterate prioritized windows first so they enqueue (and grab queue slots) ahead of the rest
            let sortedCached = cachedWindows.sorted { prioritized.contains($0.windowID) && !prioritized.contains($1.windowID) }
            let sortedNotCached = notCachedWindows.sorted { prioritized.contains($0) && !prioritized.contains($1) }
            handleCachedWindows(sortedCached, requests, source, prioritized)
            handleNotCachedWindows(sortedNotCached, requests, source, prioritized)
        }
    }

    private static func handleCachedWindows(_ cachedWindows: [SCWindow], _ requests: [CGWindowID: CaptureRequest], _ source: RefreshCausedBy, _ prioritized: Set<CGWindowID>) {
        guard !cachedWindows.isEmpty else { return }
        for cachedWindow in cachedWindows {
            guard let request = requests[cachedWindow.windowID] else { continue }
            oneTimeCapture(cachedWindow, request, source, prioritized.contains(cachedWindow.windowID))
        }
    }

    private static func handleNotCachedWindows(_ notCachedWindows: [CGWindowID], _ requests: [CGWindowID: CaptureRequest], _ source: RefreshCausedBy, _ prioritized: Set<CGWindowID>) {
        guard !notCachedWindows.isEmpty else { return }
        var dropped = 0
        shareableContentLock.lock()
        for wid in notCachedWindows {
            guard let request = requests[wid] else { continue }
            let key = CaptureDiscoveryKey(wid: wid, fullRes: request.fullRes)
            let next = PendingCapture(request: request, source: source, prioritized: prioritized.contains(wid))
            dropped += shareableCaptures.insert(key, next, prioritized: next.prioritized, merge: merge)
        }
        let generation = shareableCaptures.begin()
        shareableContentLock.unlock()
        if dropped > 0 { Logger.warning { "dropped \(dropped) queued shareable-content captures at the \(maxPendingShareableCaptures)-request cap" } }
        guard let generation else { return }
        refreshShareableContent(generation)
    }

    private static func refreshShareableContent(_ generation: UInt64) {
        let watchdog = DispatchWorkItem {
            if finishShareableContent(generation, nil, nil) {
                Logger.warning { "shareable-content discovery timed out after \(Int(discoveryTimeoutSeconds))s" }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + discoveryTimeoutSeconds, execute: watchdog)
        #if DEBUG
        shareableContentLock.lock()
        let drop = dropNextDiscovery
        dropNextDiscovery = false
        shareableContentLock.unlock()
        #endif
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { shareableContent, error in
            #if DEBUG
            if drop {
                Logger.info { "QA: dropping shareable-content discovery callback generation=\(generation)" }
                return
            }
            #endif
            BackgroundWork.screenshotsQueue.addOperation {
                _ = finishShareableContent(generation, shareableContent, error)
                watchdog.cancel()
            }
        }
    }

    /// Timeout and callback race under the same lock. Only the winning generation can replace the cache
    /// or release pending requests; a late OS response cannot interfere with recovery.
    private static func finishShareableContent(_ generation: UInt64, _ content: SCShareableContent?,
                                              _ error: Error?) -> Bool {
        var windowsById = [CGWindowID: SCWindow]()
        if let content, error == nil {
            for window in content.windows { windowsById[window.windowID] = window }
        }
        shareableContentLock.lock()
        guard let pending = shareableCaptures.finish(generation: generation, contains: { windowsById[$0.wid] != nil }) else {
            shareableContentLock.unlock()
            return false
        }
        if let content, error == nil { cachedSCWindows.withLock { $0 = content.windows } }
        let next = shareableCaptures.begin()
        shareableContentLock.unlock()
        if let next { refreshShareableContent(next) }
        guard content != nil, error == nil else {
            if let error { Logger.error { error } }
            return true
        }
        for (key, capture) in pending.sorted(by: { $0.value.prioritized && !$1.value.prioritized }) {
            guard capture.source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { continue }
            if let window = windowsById[key.wid] {
                oneTimeCapture(window, capture.request, capture.source, capture.prioritized)
            } else {
                Logger.debug { "wid:\(key.wid) was not found in SCShareableContent windows" }
            }
        }
        return true
    }

    private static func merge(_ previous: PendingCapture, _ next: PendingCapture) -> PendingCapture {
        let source: RefreshCausedBy
        switch (previous.source, next.source) {
            case (.refreshUiAfterExternalEvent, _), (_, .refreshUiAfterExternalEvent):
                source = .refreshUiAfterExternalEvent
            default:
                source = .refreshOnlyThumbnailsAfterShowUi
        }
        return PendingCapture(request: next.request, source: source,
                              prioritized: previous.prioritized || next.prioritized)
    }

    private static func sortCachedAndNotCached(_ windows: [CGWindowID]) -> ([SCWindow], [CGWindowID]) {
        return cachedSCWindows.withLock { cache in
            var cachedWindows = [SCWindow]()
            var notCachedWindows = [CGWindowID]()
            for window in windows {
                if let cachedWindow = (cache.first { $0.windowID == window }) {
                    cachedWindows.append(cachedWindow)
                } else {
                    notCachedWindows.append(window)
                }
            }
            return (cachedWindows, notCachedWindows)
        }
    }

    private static func oneTimeCapture(_ scWindow: SCWindow, _ request: CaptureRequest, _ source: RefreshCausedBy, _ isPrioritized: Bool = false) {
        let size = request.size
        let scaleFactor = request.scaleFactor
        // distinct key per resolution: a preview fetch must not be coalesced away by the thumbnail
        // capture of the same window submitted milliseconds earlier at show time
        let keyPrefix = request.fullRes ? "preview" : "capture"
        // [weak window] avoids keeping a closed Window alive while the capture is queued or in-flight with the OS
        Applications.screenshotThrottler.throttleOrProceed(key: "\(keyPrefix)-wid-\(scWindow.windowID)", queue: BackgroundWork.screenshotsQueue, priority: isPrioritized ? .high : .normal) { [weak window = request.window] in
            guard !App.isTerminating, !ScreenLockEvents.isScreenLocked, let window else { return }
            let config = SCStreamConfiguration.forWindow(size, scaleFactor, request.fullRes)
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            // Through the gate, not merely counted: these APIs are ASYNCHRONOUS, so the `screenshotsQueue`
            // slot frees the moment the request is handed to the OS, and a show of 60 windows fired 60
            // simultaneous requests — the burst #5861 blames for wedging replayd machine-wide.
            ActiveWindowCaptures.run { finish in
                guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else {
                    finish()
                    return
                }
                // captureSampleBuffer spins up a short-lived capture stream per call; on some macOS 26 machines that
                // churn leaks WindowServer memory until the session is force-logged-out (#5786), and the per-call
                // replayd attribution work can wedge screenshots machine-wide under bursts (#5861). captureScreenshot
                // avoids the churn but fails (SCStreamError -3811) on fullscreen windows whose Space is inactive, so
                // that one case stays on captureSampleBuffer. Its CGImage copy (vs a shared IOSurface) is acceptable
                // even at full resolution now that Preview frames are fetched lazily, a few per session (#5861).
                if #available(macOS 26.0, *), !request.isFullscreen {
                    captureScreenshot(filter, config, window, source, request.fullRes, finish)
                } else {
                    captureSampleBuffer(filter, config, window, source, request.fullRes, finish)
                }
            }
        }
    }

    @available(macOS 26.0, *)
    private static func captureScreenshot(_ filter: SCContentFilter, _ streamConfig: SCStreamConfiguration, _ window: Window, _ source: RefreshCausedBy, _ fullRes: Bool, _ finish: @escaping () -> Void) {
        let config = SCScreenshotConfiguration()
        config.width = streamConfig.width
        config.height = streamConfig.height
        config.showsCursor = false
        config.dynamicRange = .sdr
        SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config) { [weak window] output, error in
            finish()
            guard let window else { return }
            // no captureSampleBuffer fallback: the only known failure is a stale isFullscreen snapshot during a
            // fullscreen transition, and the next refresh re-routes it. Retrying here would silently reintroduce
            // the stream churn this path exists to avoid, and would hide new failure modes from the logs.
            guard let cgImage = output?.sdrImage, error == nil else { Logger.error { "\(window.debugId) \(output == nil) \(error)" }; return }
            deliver(window, source, .cgImage(cgImage), fullRes)
        }
    }

    private static func captureSampleBuffer(_ filter: SCContentFilter, _ config: SCStreamConfiguration, _ window: Window, _ source: RefreshCausedBy, _ fullRes: Bool, _ finish: @escaping () -> Void) {
        SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config) { [weak window] sampleBuffer, error in
            finish()
            guard let window else { return }
            guard let sampleBuffer, error == nil else { Logger.error { "\(window.debugId) \(sampleBuffer == nil) \(error)" }; return }
            guard let pixelBuffer = sampleBuffer.pixelBuffer() ?? sampleBuffer.imageBuffer else { Logger.error { "\(window.debugId) no pixelBuffer" }; return }
            deliver(window, source, .pixelBuffer(pixelBuffer), fullRes)
        }
    }

    private static func deliver(_ window: Window, _ source: RefreshCausedBy, _ contents: CALayerContents, _ fullRes: Bool) {
        guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
        DispatchQueue.main.async { [weak window] in
            guard let window, source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
            if fullRes {
                // full-res Preview frames go to the session's capped cache, not Window.thumbnail, so they
                // are released when the session ends; swap the sharp frame in if it's the one being previewed
                guard let session = SwitcherSession.current, let wid = window.cgWindowId else { return }
                // a mid-animation frame is refused here too; leaving the cache empty makes the next selection
                // move re-fetch it, and the thumbnail stands in as the Preview's placeholder meanwhile
                guard !WindowThumbnails.isPartialFrame(window, contents, fullRes: true) else { return }
                session.storePreviewFrame(wid, contents)
                if let position = window.position, let size = window.size {
                    PreviewPanel.updateIfShowing(wid, contents, position, size)
                }
            } else {
                window.refreshThumbnail(contents)
            }
        }
    }
}

class WindowCaptureScreenshotsPrivateApi {
    static func oneTimeScreenshots(_ eligibleWindows: [Window], _ source: RefreshCausedBy, prioritizedIds: Set<CGWindowID>? = nil) {
        let prioritized = prioritizedIds ?? []
        // iterate prioritized windows first so they enqueue (and grab queue slots) ahead of the rest
        let sorted = eligibleWindows.sorted { a, b in
            let aPri = a.cgWindowId.map { prioritized.contains($0) } ?? false
            let bPri = b.cgWindowId.map { prioritized.contains($0) } ?? false
            return aPri && !bPri
        }
        for window in sorted {
            guard let wid = window.cgWindowId else { continue }
            let isPrioritized = prioritized.contains(wid)
            Applications.screenshotThrottler.throttleOrProceed(key: "capture-wid-\(wid)", queue: BackgroundWork.screenshotsQueue, priority: isPrioritized ? .high : .normal) { [weak window] in
                guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
                guard let wid = window?.cgWindowId, let cgImage = oneTimeCapture(wid) else { return }
                guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
                DispatchQueue.main.async { [weak window] in
                    guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
                    window?.refreshThumbnail(.cgImage(cgImage))
                }
            }
        }
    }

    private static func oneTimeCapture(_ wid: CGWindowID) -> CGImage? {
        guard !App.isTerminating, !ScreenLockEvents.isScreenLocked else { return nil }
        // we use CGSHWCaptureWindowList because it can screenshot minimized windows, which CGWindowListCreateImage can't
        var windowId_ = wid
        // Synchronous, so it was already bounded by the 8-wide `screenshotsQueue`; through the same gate
        // anyway, so in-flight captures have ONE accounting whichever path took them.
        var list = [CGImage]()
        ActiveWindowCaptures.runSync {
            list = CGSHWCaptureWindowList(CGS_CONNECTION, &windowId_, 1, [.ignoreGlobalClipShape, .bestResolution, .fullSize]).takeRetainedValue() as! [CGImage]
        }
        return list.first
    }
}

@available(macOS 12.3, *)
extension SCStreamConfiguration {
    // size/scaleFactor are snapshotted on the main thread by the caller; we do not touch Window state here
    // (Window properties are mutated on main and would race with this background work).
    static func forWindow(_ size: CGSize, _ scaleFactor: CGFloat, _ fullRes: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.setWindowSize(size, scaleFactor, fullRes)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        return config
    }

    private func setWindowSize(_ size: CGSize, _ scaleFactor: CGFloat, _ fullRes: Bool) {
        guard let pixels = WindowThumbnails.capturePixelSize(size, scaleFactor, fullRes) else { return }
        width = Int(pixels.width)
        height = Int(pixels.height)
    }
}

extension CMSampleBuffer {
    @available(macOS 12.3, *)
    func pixelBuffer() -> CVPixelBuffer? {
        if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let attachments = attachmentsArray.first,
           let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRawValue),
           status == .complete || status == .started { // new frame was generated
            return imageBuffer
        }
        return nil
    }
}

/// **The gate on in-flight window captures**, and the counter `main.swift` drains at quit (macOS pops
/// permission dialogs for a capture still outstanding when the process dies, #5106).
///
/// It became a gate because the ScreenCaptureKit path is ASYNCHRONOUS: `SCScreenshotManager` hands the
/// request to the OS and returns, freeing its `screenshotsQueue` slot at once, so the 8-wide queue bounded
/// nothing and a show of 60 windows fired 60 simultaneous requests. The private-API path never had that
/// problem — `CGSHWCaptureWindowList` blocks, so the queue width WAS its bound — and the bound was simply
/// never carried over when ScreenCaptureKit became the macOS 26 path. `maxInFlight` restores it.
class ActiveWindowCaptures {
    /// Parity with the `screenshotsQueue` width, which is the bound the synchronous path always had.
    private static let maxInFlight = 8
    private static let maxWaiting = 256
    /// A capture the OS never answers must not hold its slot for the life of the session: #5861 has replayd
    /// wedging machine-wide under bursts, which is exactly when a lost callback is likeliest and exactly when
    /// the remaining slots matter most. Generous, because a slow capture is not a lost one — this is the
    /// pathological case only, and it matches the drain budget `makeSureAllCapturesAreFinished` allows.
    private static let watchdogSeconds = 5.0

    private static let lock = NSLock()
    private static var inFlight = 0
    private static var waiting = [(@escaping () -> Void) -> Void]()

    /// Run `capture` once a slot is free. `capture` receives a `finish` closure it MUST call when the OS
    /// answers; calling it more than once is safe and calling it late (after the watchdog fired) is a no-op.
    static func run(_ capture: @escaping (@escaping () -> Void) -> Void) {
        lock.lock()
        guard inFlight < maxInFlight else {
            guard waiting.count < maxWaiting else {
                lock.unlock()
                Logger.warning { "dropped a window capture at the \(maxWaiting)-request waiting cap" }
                return
            }
            waiting.append(capture)
            lock.unlock()
            return
        }
        inFlight += 1
        lock.unlock()
        start(capture)
    }

    /// For the synchronous private-API path: counts, runs, releases. It does not WAIT for a slot and does
    /// not need a watchdog — a blocking call cannot lose its answer, and the 8-wide queue it runs on is
    /// already the bound. Here only so both paths report through one counter at quit.
    static func runSync(_ capture: () -> Void) {
        lock.lock()
        inFlight += 1
        lock.unlock()
        capture()
        release()
    }

    private static func start(_ capture: @escaping (@escaping () -> Void) -> Void) {
        // one-shot: whoever gets there first (the OS callback or the watchdog) releases the slot exactly once
        let done = FinishOnce()
        // CANCELLED on the normal path, not just neutered by `done`. An `asyncAfter` block that has lost the
        // race still exists and still wakes the process at its deadline, so a 60-window show used to leave 60
        // wakeups behind it, all firing seconds after the switcher was gone. `done` still guards the race;
        // `cancel` is what keeps an idle AltTab idle.
        let watchdog = DispatchWorkItem {
            guard done.claim() else { return }
            Logger.warning { "a window capture never answered after \(Int(watchdogSeconds))s; releasing its slot" }
            release()
        }
        let finish = {
            watchdog.cancel()
            if done.claim() { release() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + watchdogSeconds, execute: watchdog)
        capture(finish)
    }

    private static func release() {
        lock.lock()
        inFlight -= 1
        var next: ((@escaping () -> Void) -> Void)?
        // Nothing queued may still be started once we are shutting down: the whole reason quit drains this
        // counter is that macOS pops permission dialogs for a capture outstanding when the process dies.
        if App.isTerminating {
            waiting.removeAll()
        } else if !waiting.isEmpty {
            next = waiting.removeFirst()
            inFlight += 1
        }
        lock.unlock()
        if let next { start(next) }
    }

    static func value() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return inFlight
    }

    private class FinishOnce {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }
}
