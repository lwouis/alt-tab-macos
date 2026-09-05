import Cocoa
import ScreenCaptureKit

@available(macOS 14.0, *)
class WindowCaptureScreenshots {
    // SCShareableContent.getExcludingDesktopWindows is expensive for the OS; we cache as much as possible.
    // Wrapped in ConcurrentArray because reads and writes happen from different operations on
    // BackgroundWork.screenshotsQueue, which is concurrent (maxConcurrentOperationCount = 8).
    static let cachedSCWindows = ConcurrentArray<SCWindow>()
    private static let cooldownLock = NSLock()
    private static var cooldownUntil = Date.distantPast
    private static let failureCooldown: TimeInterval = 15

    struct CaptureRequest {
        let window: Window
        let size: CGSize
        let scaleFactor: CGFloat
        let isFullscreen: Bool
        let fullRes: Bool
    }

    /// `fullRes: false` = thumbnail-scale captures, delivered to `Window.thumbnail`.
    /// `fullRes: true` = full-resolution Preview frames, delivered to the session's capped cache (#5861).
    static func oneTimeScreenshots(_ windowsToScreenshot: [Window], _ source: RefreshCausedBy, prioritizedIds: Set<CGWindowID>? = nil, fullRes: Bool = false) {
        guard !isCoolingDown else { return }
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
        ScreenCaptureCoordinator.shared.submit { completion in
            guard !isCoolingDown else { completion(); return }
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { shareableContent, error in
                completion()
                guard let shareableContent, error == nil else {
                    Logger.error { "\(shareableContent == nil) \(error)" }
                    beginFailureCooldown()
                    if let error { ScreenRecordingPermission.reportCaptureFailure(error) }
                    return
                }
                guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
                // this callback is executed on an undetermined queue; we move execution to screenshotsQueue
                BackgroundWork.screenshotsQueue.addOperation {
                    cachedSCWindows.withLock { $0 = shareableContent.windows }
                    guard source != .refreshOnlyThumbnailsAfterShowUi || SwitcherSession.isActive else { return }
                    for notCachedWindow in notCachedWindows {
                        guard let request = requests[notCachedWindow] else { continue }
                        if let cachedWindow = (shareableContent.windows.first { $0.windowID == notCachedWindow }) {
                            oneTimeCapture(cachedWindow, request, source, prioritized.contains(notCachedWindow))
                        } else {
                            Logger.debug { "wid:\(notCachedWindow) was not found in SCShareableContent windows" }
                        }
                    }
                }
            }
        }
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
            let config = SCStreamConfiguration.forWindow(scWindow, size, scaleFactor, request.fullRes, false)
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            // captureSampleBuffer spins up a short-lived capture stream per call; on some macOS 26 machines that
            // churn leaks WindowServer memory until the session is force-logged-out (#5786), and the per-call
            // replayd attribution work can wedge screenshots machine-wide under bursts (#5861). captureScreenshot
            // avoids the churn but fails (SCStreamError -3811) on fullscreen windows whose Space is inactive, so
            // that one case stays on captureSampleBuffer. Its CGImage copy (vs a shared IOSurface) is acceptable
            // even at full resolution now that Preview frames are fetched lazily, a few per session (#5861).
            if #available(macOS 26.0, *), !request.isFullscreen {
                captureScreenshot(filter, config, window, source, request.fullRes)
            } else {
                captureSampleBuffer(filter, config, window, source, request.fullRes)
            }
        }
    }

    @available(macOS 26.0, *)
    private static func captureScreenshot(_ filter: SCContentFilter, _ streamConfig: SCStreamConfiguration, _ window: Window, _ source: RefreshCausedBy, _ fullRes: Bool) {
        let config = SCScreenshotConfiguration()
        config.width = streamConfig.width
        config.height = streamConfig.height
        config.showsCursor = false
        config.dynamicRange = .sdr
        ScreenCaptureCoordinator.shared.submit { completion in
            guard !isCoolingDown else { completion(); return }
            SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config) { [weak window] output, error in
                completion()
                guard let window else { return }
                // no captureSampleBuffer fallback: the only known failure is a stale isFullscreen snapshot during a
                // fullscreen transition, and the next refresh re-routes it. Retrying here would silently reintroduce
                // the stream churn this path exists to avoid, and would hide new failure modes from the logs.
                guard let cgImage = output?.sdrImage, error == nil else {
                    Logger.error { "\(window.debugId) \(output == nil) \(error)" }
                    beginFailureCooldown()
                    if let error { ScreenRecordingPermission.reportCaptureFailure(error) }
                    return
                }
                deliver(window, source, .cgImage(cgImage), fullRes)
            }
        }
    }

    private static func captureSampleBuffer(_ filter: SCContentFilter, _ config: SCStreamConfiguration, _ window: Window, _ source: RefreshCausedBy, _ fullRes: Bool) {
        ScreenCaptureCoordinator.shared.submit { completion in
            guard !isCoolingDown else { completion(); return }
            SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config) { [weak window] sampleBuffer, error in
                completion()
                guard let window else { return }
                guard let sampleBuffer, error == nil else {
                    Logger.error { "\(window.debugId) \(sampleBuffer == nil) \(error)" }
                    beginFailureCooldown()
                    if let error { ScreenRecordingPermission.reportCaptureFailure(error) }
                    return
                }
                guard let pixelBuffer = sampleBuffer.pixelBuffer() ?? sampleBuffer.imageBuffer else { Logger.error { "\(window.debugId) no pixelBuffer" }; return }
                deliver(window, source, .pixelBuffer(pixelBuffer), fullRes)
            }
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

    private static var isCoolingDown: Bool {
        cooldownLock.lock()
        defer { cooldownLock.unlock() }
        return cooldownUntil > Date()
    }

    private static func beginFailureCooldown() {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 else { return }
        cooldownLock.lock()
        cooldownUntil = Date().addingTimeInterval(failureCooldown)
        cooldownLock.unlock()
        Logger.warning { "ScreenCaptureKit capture paused for \(failureCooldown)s after an error" }
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
        ActiveWindowCaptures.increment()
        defer { ActiveWindowCaptures.decrement() }
        return WindowServerCaptureFallback.capture(
            primary: {
                var windowId_ = wid
                let list = CGSHWCaptureWindowList(
                    CGS_CONNECTION, &windowId_, 1,
                    [.ignoreGlobalClipShape, .bestResolution, .fullSize]
                ).takeRetainedValue() as! [CGImage]
                return list.first
            },
            fallback: {
                Logger.debug {
                    "CGSHWCaptureWindowList returned no image for wid:\(wid); " +
                        "using legacy WindowServer capture"
                }
                return CGWindowListCreateImageLegacy(
                    .null, .optionIncludingWindow, wid,
                    [.boundsIgnoreFraming, .bestResolution]
                )?.takeRetainedValue()
            })
    }
}

// @available(macOS 12.3, *)
// class WindowCaptureVideos {
//     private static var streams = [CGWindowID: SCStream]()
//     private static var streamOutputs = [CGWindowID: StreamOutput]()
//     // SCStream.backgroundColor is [unowned], so we must keep own these variables
//     static let scStreamBackgroundColorDark = NSColor(white: 0.23, alpha: 1).cgColor
//     static let scStreamBackgroundColorLight = NSColor.white.cgColor
//
//     static func startCapturing(_ windowsWhichMayHaveChanged: [Window]) {
//         let windowsToShow = Set<CGWindowID>(Windows.list.filter { !$0.isWindowlessApp && $0.shouldShowTheUser }.compactMap { $0.cgWindowId })
//         let windowsAlreadyStreaming = Set<CGWindowID>(streams.keys)
//         let windowsToStop = windowsAlreadyStreaming.subtracting(windowsToShow)
//         stopCaptures(windowsToStop)
//         let windowsToStart = windowsToShow.subtracting(windowsAlreadyStreaming)
//         let windowsWhichMayHaveChanged_ = windowsWhichMayHaveChanged.compactMap { $0.cgWindowId }
//         if !windowsToStart.isEmpty || !windowsWhichMayHaveChanged_.isEmpty {
//             SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { shareableContent, error in
//                 guard let shareableContent, error == nil else {
//                     Logger.error { "\(shareableContent == nil) \(error)" }
//                     return
//                 }
//                 // this callback is executed on an undetermined queue
//                 // we move execution to main-thread to avoid races with starting/stopping streams and the app being shown/hidden
//                 DispatchQueue.main.async {
//                     guard SwitcherSession.isActive else { return }
//                     startCaptures(windowsToStart, shareableContent)
//                     updateCaptures(windowsWhichMayHaveChanged_, shareableContent)
//                     Logger.debug { streams.keys }
//                 }
//             }
//         }
//     }
//
//     static func stopCapturing() {
//         Logger.debug { streams.keys }
//         for stream in streams.values {
//             stream.stopCapture()
//         }
//         streams.removeAll()
//         streamOutputs.removeAll()
//     }
//
//     private static func updateCaptures(_ windowsWhichMayHaveChanged: [CGWindowID], _ shareableContent: SCShareableContent) {
//         for wid in windowsWhichMayHaveChanged {
//             if let stream = streams[wid],
//                let scWindow = shareableContent.windows.first(where: { $0.windowID == wid }) {
//                 stream.updateConfiguration(SCStreamConfiguration.forWindow(scWindow, true)) { error in
//                     if let error { Logger.error { error } }
//                 }
//             }
//         }
//     }
//
//     private static func startCaptures(_ windowsToStart: Set<CGWindowID>, _ shareableContent: SCShareableContent) {
//         for wid in windowsToStart {
//             if let scWindow = shareableContent.windows.first(where: { $0.windowID == wid }) {
//                 startCapture(scWindow)
//             }
//         }
//     }
//
//
//     private static func startCapture(_ window: SCWindow) {
//         let wid = window.windowID
//         let output = StreamOutput(wid)
//         let config = SCStreamConfiguration.forWindow(window, true)
//         let filter = SCContentFilter(desktopIndependentWindow: window)
//         let stream = SCStream(filter: filter, configuration: config, delegate: output)
//         do {
//             try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: BackgroundWork.screenshotsQueue.strongUnderlyingQueue)
//             stream.startCapture { error in
//                 if let error { Logger.error { error } }
//             }
//             streams[wid] = stream
//             streamOutputs[wid] = output
//         } catch {
//             Logger.error { error }
//         }
//     }
//
//     private static func stopCaptures(_ windowsToStop: Set<CGWindowID>) {
//         for wid in windowsToStop {
//             stopCapture(wid)
//         }
//     }
//
//     private static func stopCapture(_ wid: CGWindowID) {
//         if let stream = streams[wid] {
//             stream.stopCapture()
//             streams.removeValue(forKey: wid)
//             streamOutputs.removeValue(forKey: wid)
//         }
//     }
//
//     class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
//         let wid: CGWindowID
//
//         init(_ wid: CGWindowID) {
//             self.wid = wid
//         }
//
//         // from SCStreamOutput; handle captured samples
//         func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
//             BackgroundWork.screenshotsQueue.trackCallbacks {
//                 if sampleBuffer.isValid,
//                    let pixelBuffer = sampleBuffer.pixelBuffer() {
//                     DispatchQueue.main.async {
//                         if let window = (Windows.list.first { $0.cgWindowId == self.wid }) {
//                             window.refreshThumbnail(.pixelBuffer(pixelBuffer))
//                         }
//                     }
//                 }
//             }
//         }
//
//         // from SCStreamDelegate; handle errors when opening a stream
//         func stream(_ stream: SCStream, didStopWithError error: any Error) {
//             BackgroundWork.screenshotsQueue.trackCallbacks {
//                 Logger.error { error }
//             }
//         }
//     }
// }

@available(macOS 12.3, *)
extension SCStreamConfiguration {
    // size/scaleFactor are snapshotted on the main thread by the caller; we do not touch Window state here
    // (Window properties are mutated on main and would race with this background work).
    static func forWindow(_ scWindow: SCWindow, _ size: CGSize, _ scaleFactor: CGFloat, _ fullRes: Bool, _ video: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.setWindowSize(size, scaleFactor, fullRes)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        // if video {
        //     config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(60))
        //     config.queueDepth = 8
        //     // ~60% memory reduction compared to kCVPixelFormatType_32BGRA
        //     config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        //     // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange doesn't have transparency, so we end up with an opaque background color around the window corners
        //     // we use a background color that try and hide these corners as much as possible
        //     config.backgroundColor = Appearance.currentTheme == .dark ? WindowCaptureVideos.scStreamBackgroundColorDark : WindowCaptureVideos.scStreamBackgroundColorLight
        // }
        // config.scalesToFit = true
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

    @available(macOS 12.3, *)
    func metalTexture(_ device: MTLDevice) -> MTLTexture? {
        guard let pixelBuffer = pixelBuffer(),
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            mipmapped: false
        )
        return device.makeTexture(descriptor: desc, iosurface: surface, plane: 0)
    }
}

class ActiveWindowCaptures {
    private static var _count: Int32 = 0

    static func increment() { OSAtomicIncrement32(&_count) }
    static func decrement() { OSAtomicDecrement32(&_count) }
    static func value() -> Int { Int(OSAtomicAdd32(0, &_count)) + ScreenCaptureCoordinator.shared.inFlightCount }
}
