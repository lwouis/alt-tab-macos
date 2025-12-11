import Cocoa
import ScreenCaptureKit

/// LiveWindowCapture provides real-time video capture of windows using ScreenCaptureKit.
/// Singleton pattern for AppKit integration - manages SCStream instances per window.
@available(macOS 12.3, *)
@MainActor
class LiveWindowCapture: NSObject {
    static let shared = LiveWindowCapture()

    /// Active streams for each window
    private var streams: [CGWindowID: SCStream] = [:]

    /// Stream output handlers for each window
    private var streamOutputs: [CGWindowID: StreamOutput] = [:]

    /// Callback to notify when a new frame is available
    var onFrameUpdate: ((CGWindowID, CGImage) -> Void)?

    /// Flag to cancel pending stop operation
    private var stopCancelled = false

    override private init() {
        super.init()
    }

    /// Start capturing multiple windows at once (incremental - only starts/stops what's needed)
    func startCapture(windowIDs: [CGWindowID]) async {
        guard Preferences.enableLivePreview else { return }
        
        // Cancel any pending stop operation
        stopCancelled = true

        let newWindowIDsSet = Set(windowIDs)
        let existingWindowIDsSet = Set(streams.keys)

        // Stop streams for windows no longer needed
        let windowsToStop = existingWindowIDsSet.subtracting(newWindowIDsSet)
        for windowID in windowsToStop {
            await stopCapture(windowID: windowID)
        }

        // Start streams for new windows only
        let windowsToStart = newWindowIDsSet.subtracting(existingWindowIDsSet)
        guard !windowsToStart.isEmpty else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)

            // Start all streams in parallel using TaskGroup
            await withTaskGroup(of: Void.self) { group in
                for windowID in windowsToStart {
                    guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                        continue
                    }
                    group.addTask {
                        await self.startStream(for: scWindow)
                    }
                }
            }
        } catch {}
    }

    /// Start capturing a single window
    func startCapture(windowID: CGWindowID) async {
        guard Preferences.enableLivePreview else { return }
        guard streams[windowID] == nil else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                return
            }
            await startStream(for: scWindow)
        } catch {}
    }

    /// Internal method to start a stream for a specific window
    private func startStream(for window: SCWindow) async {
        let windowID = window.windowID
        let filter = SCContentFilter(desktopIndependentWindow: window)

        let quality = Preferences.livePreviewQuality
        let frameRate = Preferences.livePreviewFrameRate

        let config = SCStreamConfiguration()

        let backingScaleFactor = Int(NSScreen.main?.backingScaleFactor ?? 2.0)
        let windowWidth = Int(window.frame.width)
        let windowHeight = Int(window.frame.height)
        let maxDim = quality.maxDimension

        if quality.useFullResolution {
            let effectiveScale = quality.scaleFactor == 2 ? 2 : backingScaleFactor
            var targetWidth = windowWidth * effectiveScale
            var targetHeight = windowHeight * effectiveScale

            if maxDim > 0 {
                let aspectRatio = Double(targetWidth) / Double(targetHeight)
                if targetWidth > targetHeight {
                    targetWidth = min(targetWidth, maxDim * effectiveScale)
                    targetHeight = Int(Double(targetWidth) / aspectRatio)
                } else {
                    targetHeight = min(targetHeight, maxDim * effectiveScale)
                    targetWidth = Int(Double(targetHeight) * aspectRatio)
                }
            }

            config.width = targetWidth
            config.height = targetHeight
        } else {
            let aspectRatio = Double(windowWidth) / Double(windowHeight)
            let limitDim = maxDim > 0 ? maxDim : 640
            if aspectRatio > 1 {
                config.width = min(limitDim, windowWidth * backingScaleFactor)
                config.height = Int(Double(config.width) / aspectRatio)
            } else {
                config.height = min(limitDim, windowHeight * backingScaleFactor)
                config.width = Int(Double(config.height) * aspectRatio)
            }
        }

        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate.frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.queueDepth = 8
        config.scalesToFit = true

        do {
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)

            let output = StreamOutput { [weak self] (image: CGImage) in
                Task { @MainActor in
                    self?.onFrameUpdate?(windowID, image)
                }
            }

            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
            try await stream.startCapture()

            streams[windowID] = stream
            streamOutputs[windowID] = output
        } catch {}
    }

    /// Stop capturing a specific window
    func stopCapture(windowID: CGWindowID) async {
        if let stream = streams[windowID] {
            try? await stream.stopCapture()
            streams.removeValue(forKey: windowID)
            streamOutputs.removeValue(forKey: windowID)
        }
    }

    func stopAllCaptures() async {
        let keepAlive = Preferences.livePreviewStreamKeepAlive

        if keepAlive == 0 {
            let streamsToStop = streams
            streams.removeAll()
            streamOutputs.removeAll()
            for (_, stream) in streamsToStop {
                try? await stream.stopCapture()
            }
            return
        }

        if keepAlive < 0 {
            return
        }

        stopCancelled = false
        try? await Task.sleep(nanoseconds: UInt64(keepAlive) * 1_000_000_000)

        guard !stopCancelled else { return }

        let streamsToStop = streams
        streams.removeAll()
        streamOutputs.removeAll()

        for (_, stream) in streamsToStop {
            try? await stream.stopCapture()
        }
    }
}

/// StreamOutput handles the incoming video frames from SCStream
/// Reuses CIContext for performance
@available(macOS 12.3, *)
private class StreamOutput: NSObject, SCStreamOutput {
    private let context = CIContext()
    private let onFrame: (CGImage) -> Void

    init(onFrame: @escaping (CGImage) -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        guard let cgImage = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: width, height: height)) else {
            return
        }

        onFrame(cgImage)
    }
}
