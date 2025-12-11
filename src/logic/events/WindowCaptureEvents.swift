import Cocoa
import ScreenCaptureKit

@available(macOS 12.3, *)
class WindowCaptureEvents {
    private static var streams = [CGWindowID: SCStream]()
    private static var streamOutputs = [CGWindowID: StreamOutput]()

    static func toggleOn(_ windowsWhichMayHaveChanged: [Window]) {
        let windowsToShow = Set<CGWindowID>(Windows.list.filter { !$0.isWindowlessApp && $0.shouldShowTheUser }.compactMap { $0.cgWindowId })
        let windowsAlreadyStreaming = Set<CGWindowID>(streams.keys)
        let windowsToStop = windowsAlreadyStreaming.subtracting(windowsToShow)
        stopCaptures(windowsToStop)
        let windowsToStart = windowsToShow.subtracting(windowsAlreadyStreaming)
        let windowsWhichMayHaveChanged_ = windowsWhichMayHaveChanged.compactMap { $0.cgWindowId }
        if !windowsToStart.isEmpty || !windowsWhichMayHaveChanged_.isEmpty {
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { shareableContent, error in
                guard let shareableContent, error == nil else {
                    Logger.error(error, shareableContent == nil)
                    return
                }
                // this callback is executed on an undetermined queue
                // we move execution to main-thread to avoid races with starting/stopping streams and the app being shown/hidden
                DispatchQueue.main.async {
                    guard App.app.appIsBeingUsed else { return }
                    startCaptures(windowsToStart, shareableContent)
                    updateCaptures(windowsWhichMayHaveChanged_, shareableContent)
                    Logger.debug(streams.keys)
                }
            }
        }
    }

    static func toggleOff() {
        for stream in streams.values {
            stream.stopCapture { error in
                if let error { Logger.error(error) }
            }
        }
        streams.removeAll()
        streamOutputs.removeAll()
        Logger.debug()
    }

    private static func updateCaptures(_ windowsWhichMayHaveChanged: [CGWindowID], _ shareableContent: SCShareableContent) {
        for wid in windowsWhichMayHaveChanged {
            if let stream = streams[wid],
               let scWindow = shareableContent.windows.first(where: { $0.windowID == wid }) {
                stream.updateConfiguration(SCStreamConfiguration.forWindow(scWindow, true)) { error in
                    if let error { Logger.error(error) }
                }
            }
        }
    }

    private static func startCaptures(_ windowsToStart: Set<CGWindowID>, _ shareableContent: SCShareableContent) {
        for wid in windowsToStart {
            if let scWindow = shareableContent.windows.first(where: { $0.windowID == wid }) {
                startCapture(scWindow)
            }
        }
    }


    private static func startCapture(_ window: SCWindow) {
        let wid = window.windowID
        let output = StreamOutput(wid)
        let config = SCStreamConfiguration.forWindow(window, true)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: BackgroundWork.screenshotsQueue.strongUnderlyingQueue)
            stream.startCapture { error in
                if let error { Logger.error(error) }
            }
            streams[wid] = stream
            streamOutputs[wid] = output
        } catch {
            Logger.error(error)
        }
    }

    private static func stopCaptures(_ windowsToStop: Set<CGWindowID>) {
        for wid in windowsToStop {
            stopCapture(wid)
        }
    }

    private static func stopCapture(_ wid: CGWindowID) {
        if let stream = streams[wid] {
            stream.stopCapture { error in
                if let error { Logger.error(error) }
            }
            streams.removeValue(forKey: wid)
            streamOutputs.removeValue(forKey: wid)
        }
    }

    class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
        let wid: CGWindowID

        init(_ wid: CGWindowID) {
            self.wid = wid
        }

        // from SCStreamOutput; handle captured samples
        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            BackgroundWork.screenshotsQueue.trackCallbacks {
                if sampleBuffer.isValid,
                   let pixelBuffer = sampleBuffer.pixelBuffer() {
                    let wid_ = wid
                    DispatchQueue.main.async {
                        if let window = (Windows.list.first { $0.cgWindowId == wid_ }) {
                            window.refreshThumbnail(.pixelBuffer(pixelBuffer))
                        }
                    }
                }
            }
        }

        // from SCStreamDelegate; handle errors when opening a stream
        func stream(_ stream: SCStream, didStopWithError error: any Error) {
            BackgroundWork.screenshotsQueue.trackCallbacks {
                Logger.error(error)
            }
        }
    }
}

fileprivate let scStreamBackgroundColorDark = NSColor.init(white: 0.23, alpha: 1).cgColor
fileprivate let scStreamBackgroundColorLight = NSColor.white.cgColor

@available(macOS 12.3, *)
extension SCStreamConfiguration {
    static func forWindow(_ window: SCWindow, _ video: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.setWindowSize(window)
        // ~60% memory reduction compared to kCVPixelFormatType_32BGRA
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        // kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange doesn't have transparency, so we end up with an opaque background color around the window corners
        // we use a background color that try and hide these corners as much as possible
        config.backgroundColor = Appearance.currentTheme == .dark ? scStreamBackgroundColorDark : scStreamBackgroundColorLight
        config.showsCursor = false
        if video {
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(60))
            config.queueDepth = 8
        }
        // config.scalesToFit = true
        return config
    }

    private func setWindowSize(_ window: SCWindow) {
        let backingScaleFactor = Int(NSScreen.preferred.backingScaleFactor)
        width = Int(window.frame.width) * backingScaleFactor
        height = Int(window.frame.height) * backingScaleFactor
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

class WindowCapture {
    @available(macOS 14.0, *)
    static func oneTimeScreenshots(_ windowsToScreenshot: [Window], _ source: RefreshCausedBy) {
        let windows = windowsToScreenshot.compactMap { $0.cgWindowId }
        if !windows.isEmpty {
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { shareableContent, error in
                guard let shareableContent, error == nil else {
                    Logger.error(error, shareableContent == nil)
                    return
                }
                if source == .refreshOnlyThumbnailsAfterShowUi && !App.app.appIsBeingUsed { return }
                // this callback is executed on an undetermined queue
                // we move execution to main-thread to avoid races with starting/stopping streams and the app being shown/hidden
                DispatchQueue.main.async {
                    if source == .refreshOnlyThumbnailsAfterShowUi && !App.app.appIsBeingUsed { return }
                    oneTimeCaptures(windows, shareableContent, source)
                    Logger.debug(windows)
                }
            }
        }
    }

    @available(macOS 14.0, *)
    private static func oneTimeCaptures(_ windows: [CGWindowID], _ shareableContent: SCShareableContent, _ source: RefreshCausedBy) {
        for wid in windows {
            if let scWindow = shareableContent.windows.first(where: { $0.windowID == wid }) {
                oneTimeCapture(scWindow, source)
            }
        }
    }

    @available(macOS 14.0, *)
    private static func oneTimeCapture(_ scWindow: SCWindow, _ source: RefreshCausedBy) {
        let config = SCStreamConfiguration.forWindow(scWindow, false)
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        SCScreenshotManager.captureSampleBuffer(contentFilter: filter, configuration: config) { sampleBuffer, error in
            if let error {
                Logger.error(error)
                return
            }
            if source == .refreshOnlyThumbnailsAfterShowUi && !App.app.appIsBeingUsed { return }
            if let sampleBuffer, sampleBuffer.isValid, let pixelBuffer = sampleBuffer.imageBuffer {
                let wid = scWindow.windowID
                DispatchQueue.main.async {
                    if source == .refreshOnlyThumbnailsAfterShowUi && !App.app.appIsBeingUsed { return }
                    if let window = (Windows.list.first { $0.cgWindowId == wid }) {
                        window.refreshThumbnail(.pixelBuffer(pixelBuffer))
                    }
                }
            }
        }
    }

    static func oneTimeScreenshotsPrivateApi(_ eligibleWindows: [Window], _ source: RefreshCausedBy) {
        for window in eligibleWindows {
            BackgroundWork.screenshotsQueue.addOperation { [weak window] in
                if source == .refreshOnlyThumbnailsAfterShowUi && !App.app.appIsBeingUsed { return }
                if let wid = window?.cgWindowId, let cgImage = oneTimeCapturePrivateApi(wid) {
                    if source == .refreshOnlyThumbnailsAfterShowUi && !App.app.appIsBeingUsed { return }
                    DispatchQueue.main.async { [weak window] in
                        if source == .refreshOnlyThumbnailsAfterShowUi && !App.app.appIsBeingUsed { return }
                        window?.refreshThumbnail(.cgImage(cgImage))
                    }
                }
            }
        }
    }

    private static func oneTimeCapturePrivateApi(_ wid: CGWindowID) -> CGImage? {
        // we use CGSHWCaptureWindowList because it can screenshot minimized windows, which CGWindowListCreateImage can't
        var windowId_ = wid
        let list = CGSHWCaptureWindowList(CGS_CONNECTION, &windowId_, 1, [.ignoreGlobalClipShape, .bestResolution, .fullSize]).takeRetainedValue() as! [CGImage]
        return list.first
    }
}
