import CoreGraphics

struct StageManagerCaptureMode: Equatable {
    private(set) var enabled = false
    private(set) var generation: UInt64 = 0

    mutating func update(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        generation &+= 1
    }
}

enum StageManagerCapturePolicy {
    static func allowsPublication(_ capturedMode: StageManagerCaptureMode, _ currentMode: StageManagerCaptureMode,
                                  capturedFocus: UInt64, currentFocus: UInt64, isFocused: Bool) -> Bool {
        capturedMode == currentMode && (!currentMode.enabled || (capturedFocus == currentFocus && isFocused))
    }

    static func hasNormalGeometry(_ bounds: CGRect?, _ size: CGSize) -> Bool {
        guard let bounds, bounds.width > 0, bounds.height > 0,
              size.width > 0, size.height > 0 else { return false }
        return !(bounds.width < size.width * 0.7 && bounds.height < size.height * 0.7)
    }

    static func hasUsableImage(_ image: CGImage) -> Bool {
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let visibleSamples = pixels.withUnsafeMutableBytes { bytes -> Int in
            guard let context = CGContext(data: bytes.baseAddress, width: 16, height: 16,
                bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return stride(from: 3, to: bytes.count, by: 4).filter { bytes[$0] > 16 }.count
        }
        return hasUsablePixels(CGSize(width: image.width, height: image.height), visibleSamples: visibleSamples, totalSamples: 256)
    }

    static func hasUsablePixels(_ size: CGSize, visibleSamples: Int, totalSamples: Int) -> Bool {
        size.width >= 16 && size.height >= 16 && totalSamples > 0
            && Double(visibleSamples) / Double(totalSamples) >= 0.05
    }
}
