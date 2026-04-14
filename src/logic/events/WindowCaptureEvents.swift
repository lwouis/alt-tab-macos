import Cocoa
import ScreenCaptureKit

private func canContinueCapture(_ source: RefreshCausedBy) -> Bool {
    source != .refreshOnlyThumbnailsAfterShowUi || App.appIsBeingUsed
}

private func completeCaptureRequest(_ wid: CGWindowID, _ generation: Int, _ scheduleNext: (Int) -> Void) {
    if let nextGeneration = WindowCaptureRequestCoordinator.shared.finish(wid, generation: generation) {
        scheduleNext(nextGeneration)
    }
}

@available(macOS 14.0, *)
class WindowCaptureScreenshots {
    // SCShareableContent.getExcludingDesktopWindows is expensive for the OS; we cache as much as possible
    static var cachedSCWindows = [SCWindow]()

    static func oneTimeScreenshots(_ windowsToScreenshot: [Window], _ source: RefreshCausedBy) {
        let requestedGenerations = requestGenerations(windowsToScreenshot.compactMap { $0.cgWindowId })
        guard !requestedGenerations.isEmpty else { return }
        BackgroundWork.screenshotsQueue.addOperation {
            guard canContinueCapture(source) else { finish(Array(requestedGenerations.keys), requestedGenerations, source); return }
            let (cachedWindows, notCachedWindows) = sortCachedAndNotCached(Array(requestedGenerations.keys))
            Logger.debug { "cached:\(cachedWindows.map { $0.windowID }) notCached:\(notCachedWindows)" }
            handleCachedWindows(cachedWindows, source, requestedGenerations)
            handleNotCachedWindows(notCachedWindows, source, requestedGenerations)
        }
    }

    private static func requestGenerations(_ windows: [CGWindowID]) -> [CGWindowID: Int] {
        var requestedGenerations = [CGWindowID: Int]()
        for wid in windows {
            guard requestedGenerations[wid] == nil else { continue }
            if let generation = WindowCaptureRequestCoordinator.shared.request(wid) {
                requestedGenerations[wid] = generation
            }
        }
        return requestedGenerations
    }

    private static func handleCachedWindows(_ cachedWindows: [SCWindow], _ source: RefreshCausedBy, _ requestedGenerations: [CGWindowID: Int]) {
        guard !cachedWindows.isEmpty else { return }
        for cachedWindow in cachedWindows {
            guard let generation = requestedGenerations[cachedWindow.windowID] else { continue }
            oneTimeCapture(cachedWindow, source, generation)
        }
    }

    private static func handleNotCachedWindows(_ notCachedWindows: [CGWindowID], _ source: RefreshCausedBy, _ requestedGenerations: [CGWindowID: Int]) {
        guard !notCachedWindows.isEmpty else { return }
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { shareableContent, error in
            guard let shareableContent, error == nil else { Logger.error { "\(shareableContent == nil) \(error)" }; finish(notCachedWindows, requestedGenerations, source); return }
            guard canContinueCapture(source) else { finish(notCachedWindows, requestedGenerations, source); return }
            BackgroundWork.screenshotsQueue.addOperation {
                cachedSCWindows = shareableContent.windows
                guard canContinueCapture(source) else { finish(notCachedWindows, requestedGenerations, source); return }
                for notCachedWindow in notCachedWindows {
                    guard let generation = requestedGenerations[notCachedWindow] else { continue }
                    guard let cachedWindow = (cachedSCWindows.first { $0.windowID == notCachedWindow }) else {
                        Logger.debug { "wid:\(notCachedWindow) was not found in SCShareableContent windows" }
                        finish(notCachedWindow, generation, source)
                        continue
                    }
                    oneTimeCapture(cachedWindow, source, generation)
                }
            }
        }
    }

    private static func sortCachedAndNotCached(_ windows: [CGWindowID]) -> ([SCWindow], [CGWindowID]) {
        var cachedWindows = [SCWindow]()
        var notCachedWindows = [CGWindowID]()
        for window in windows {
            if let cachedWindow = (cachedSCWindows.first { $0.windowID == window }) {
                cachedWindows.append(cachedWindow)
            } else {
                notCachedWindows.append(window)
            }
        }
        return (cachedWindows, notCachedWindows)
    }

    private static func enqueueCapture(_ wid: CGWindowID, _ source: RefreshCausedBy, _ generation: Int) {
        BackgroundWork.screenshotsQueue.addOperation {
            guard canContinueCapture(source) else { finish(wid, generation, source); return }
            if let cachedWindow = (cachedSCWindows.first { $0.windowID == wid }) {
                oneTimeCapture(cachedWindow, source, generation)
                return
            }
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { shareableContent, error in
                guard let shareableContent, error == nil else { Logger.error { "\(shareableContent == nil) \(error)" }; finish(wid, generation, source); return }
                guard canContinueCapture(source) else { finish(wid, generation, source); return }
                BackgroundWork.screenshotsQueue.addOperation {
                    cachedSCWindows = shareableContent.windows
                    guard canContinueCapture(source) else { finish(wid, generation, source); return }
                    guard let cachedWindow = (cachedSCWindows.first { $0.windowID == wid }) else {
                        Logger.debug { "wid:\(wid) was not found in SCShareableContent windows" }
                        finish(wid, generation, source)
                        return
                    }
                    oneTimeCapture(cachedWindow, source, generation)
                }
            }
        }
    }

    private static func oneTimeCapture(_ scWindow: SCWindow, _ source: RefreshCausedBy, _ generation: Int) {
        guard !App.isTerminating, let window = (Windows.list.first { $0.cgWindowId == scWindow.windowID }), window.size != nil else { finish(scWindow.windowID, generation, source); return }
        let config = SCStreamConfiguration.forWindow(scWindow, window, false)
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        ActiveWindowCaptures.increment()
        SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config) { sampleBuffer, error in
            ActiveWindowCaptures.decrement()
            guard let sampleBuffer, error == nil else { Logger.error { "\(window.debugId) \(sampleBuffer == nil) \(error)" }; finish(scWindow.windowID, generation, source); return }
            guard canContinueCapture(source) else { finish(scWindow.windowID, generation, source); return }
            let pixelBuffer: CVPixelBuffer? = sampleBuffer.pixelBuffer() ?? sampleBuffer.imageBuffer
            guard let pixelBuffer else { Logger.error { "\(window.debugId) no pixelBuffer" }; finish(scWindow.windowID, generation, source); return }
            DispatchQueue.main.async {
                if canContinueCapture(source),
                   WindowCaptureRequestCoordinator.shared.shouldApplyResult(for: scWindow.windowID, generation: generation),
                   let window = (Windows.list.first { $0.cgWindowId == scWindow.windowID }) {
                    window.refreshThumbnail(.pixelBuffer(pixelBuffer))
                }
                finish(scWindow.windowID, generation, source)
            }
        }
    }

    private static func finish(_ windows: [CGWindowID], _ requestedGenerations: [CGWindowID: Int], _ source: RefreshCausedBy) {
        for wid in windows {
            guard let generation = requestedGenerations[wid] else { continue }
            finish(wid, generation, source)
        }
    }

    private static func finish(_ wid: CGWindowID, _ generation: Int, _ source: RefreshCausedBy) {
        completeCaptureRequest(wid, generation) { enqueueCapture(wid, source, $0) }
    }
}

class WindowCaptureScreenshotsPrivateApi {
    static func oneTimeScreenshots(_ eligibleWindows: [Window], _ source: RefreshCausedBy) {
        var requestedWindows = Set<CGWindowID>()
        for window in eligibleWindows {
            guard let wid = window.cgWindowId, !requestedWindows.contains(wid), let generation = WindowCaptureRequestCoordinator.shared.request(wid) else { continue }
            requestedWindows.insert(wid)
            enqueueCapture(wid, source, generation)
        }
    }

    private static func enqueueCapture(_ wid: CGWindowID, _ source: RefreshCausedBy, _ generation: Int) {
        BackgroundWork.screenshotsQueue.addOperation {
            guard canContinueCapture(source) else { finish(wid, generation, source); return }
            guard let cgImage = oneTimeCapture(wid) else { finish(wid, generation, source); return }
            guard canContinueCapture(source) else { finish(wid, generation, source); return }
            DispatchQueue.main.async {
                if canContinueCapture(source),
                   WindowCaptureRequestCoordinator.shared.shouldApplyResult(for: wid, generation: generation),
                   let window = (Windows.list.first { $0.cgWindowId == wid }) {
                    window.refreshThumbnail(.cgImage(cgImage))
                }
                finish(wid, generation, source)
            }
        }
    }

    private static func oneTimeCapture(_ wid: CGWindowID) -> CGImage? {
        guard !App.isTerminating else { return nil }
        // we use CGSHWCaptureWindowList because it can screenshot minimized windows, which CGWindowListCreateImage can't
        var windowId_ = wid
        ActiveWindowCaptures.increment()
        let list = CGSHWCaptureWindowList(CGS_CONNECTION, &windowId_, 1, [.ignoreGlobalClipShape, .bestResolution, .fullSize]).takeRetainedValue() as! [CGImage]
        ActiveWindowCaptures.decrement()
        return list.first
    }

    private static func finish(_ wid: CGWindowID, _ generation: Int, _ source: RefreshCausedBy) {
        completeCaptureRequest(wid, generation) { enqueueCapture(wid, source, $0) }
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
//                     guard App.appIsBeingUsed else { return }
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
    static func forWindow(_ scWindow: SCWindow, _ window: Window, _ video: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.setWindowSize(scWindow, window)
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

    private func windowScaleFactor(_ window: Window) -> CGFloat {
        if let screenId = window.screenId,
           let screen = Screens.all[screenId] {
            return screen.backingScaleFactor
        }
        return NSScreen.preferred.backingScaleFactor
    }

    private func setWindowSize(_ scWindow: SCWindow, _ window: Window) {
        let scaleFactor = windowScaleFactor(window)
        // we use window.size and not scWindow.frame, as scWindow is cached thus its size can be stale. window.size is always up-to-date
        let size = window.size! // we checked non-nil earlier, up the stack
        // window.size shows logical size. It doesn't change when the scaleFactor changes. We need to correct for this as we need to capture more and less pixels depending on DPI
        let originalSize = NSSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        guard originalSize.width > 0, originalSize.height > 0 else { return }
        if Preferences.previewSelectedWindow {
            width = Int(originalSize.width)
            height = Int(originalSize.height)
        } else {
            // capture screenshots as small as needed for the thumbnails
            let maxSize = TilesPanel.maxPossibleThumbnailSize
            guard maxSize.width > 0, maxSize.height > 0 else { return }
            let scale = min(1.0, maxSize.width / originalSize.width, maxSize.height / originalSize.height)
            width = Int((originalSize.width * scale).rounded())
            height = Int((originalSize.height * scale).rounded())
        }
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
    static func value() -> Int { Int(OSAtomicAdd32(0, &_count)) }
}
