import CoreGraphics

/// One stateful policy per tracked window, owned by the main thread. Static image analysis runs off-main.
struct ThumbnailCapturePolicy {
    struct Geometry: Equatable {
        let size: CGSize
        let scaleFactor: CGFloat
        let isFullscreen: Bool
    }

    enum Decision: Equatable {
        case accept
        case retry(UInt64)
        case discard
    }

    private var expectedSize: CGSize?
    private var geometry: Geometry?
    private var referenceCoverage: CGSize?
    private var retries = 0
    private var generation: UInt64 = 0
    private var pendingRetry: UInt64?
    private static let maxRetries = 3
    private static let partialFrameRatio = 0.9
    private static let minimumRelativeCoverage = 0.55

    static func isPartial(_ actual: CGSize, _ expected: CGSize) -> Bool {
        actual.width < expected.width * partialFrameRatio || actual.height < expected.height *
            partialFrameRatio
    }

    static func contentPixelSize(_ rect: CGRect, scaleFactor: CGFloat, frameSize: CGSize) -> CGSize? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
              rect.width > 0, rect.height > 0, scaleFactor.isFinite, scaleFactor > 0,
              frameSize.width.isFinite, frameSize.height.isFinite, frameSize.width > 0,
              frameSize.height > 0 else { return nil }
        let pixels = CGRect(x: rect.minX * scaleFactor, y: rect.minY * scaleFactor,
                            width: rect.width * scaleFactor, height: rect.height * scaleFactor)
        guard pixels.origin.x.isFinite, pixels.origin.y.isFinite, pixels.width.isFinite,
              pixels.height.isFinite else { return nil }
        let clipped = pixels.intersection(CGRect(origin: .zero, size: frameSize))
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        return clipped.size
    }

    /// Alpha measures drawn bounds, not whether they are correct. Callers compare with this window's
    /// established coverage; an intentionally transparent window can have the same bounds as a shelf image.
    static func contentPixelSize(_ image: CGImage) -> CGSize? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return nil
        default: break
        }
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return nil }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            let samples = bytes.bindMemory(to: UInt8.self)
            var peak: UInt8 = 0
            for offset in stride(from: 3, to: samples.count, by: 4) { peak = max(peak, samples[offset]) }
            guard peak > 0 else { return nil }
            let threshold = max(UInt8(1), peak / 8)
            var minX = side
            var minY = side
            var maxX = -1
            var maxY = -1
            for y in 0 ..< side {
                for x in 0 ..< side where samples[(y * side + x) * 4 + 3] >= threshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGSize(width: CGFloat(maxX - minX + 1) * CGFloat(image.width) / CGFloat(side),
                          height: CGFloat(maxY - minY + 1) * CGFloat(image.height) / CGFloat(side))
        }
    }

    func isPartial(actual: CGSize, expected: CGSize, contentSize: CGSize? = nil,
                   allowsContentChange: Bool = false, geometry: Geometry? = nil) -> Bool {
        if Self.isPartial(actual, expected) {
            return true
        }
        guard !allowsContentChange, self.geometry == geometry,
              let referenceCoverage, let coverage = Self.coverage(contentSize, actual) else { return false }
        return coverage.width * coverage.height < referenceCoverage.width * referenceCoverage.height *
            Self.minimumRelativeCoverage
    }

    mutating func evaluate(actual: CGSize, expected: CGSize, contentSize: CGSize? = nil,
                           allowsContentChange: Bool = false, geometry: Geometry? = nil) -> Decision {
        if expectedSize != expected || self.geometry != geometry {
            expectedSize = expected
            self.geometry = geometry
            referenceCoverage = nil
            reset()
        }
        guard isPartial(actual: actual, expected: expected, contentSize: contentSize,
                        allowsContentChange: allowsContentChange, geometry: geometry) else {
            rememberCoverage(contentSize, actual, allowsContentChange)
            reset()
            return .accept
        }
        guard pendingRetry == nil, retries < Self.maxRetries else { return .discard }
        retries += 1
        generation &+= 1
        pendingRetry = generation
        return .retry(generation)
    }

    private static func coverage(_ contentSize: CGSize?, _ actual: CGSize) -> CGSize? {
        guard let contentSize, actual.width > 0, actual.height > 0,
              contentSize.width.isFinite, contentSize.height.isFinite,
              contentSize.width > 0, contentSize.height > 0 else { return nil }
        return CGSize(
            width: min(1, contentSize.width / actual.width),
            height: min(1, contentSize.height / actual.height)
        )
    }

    private mutating func rememberCoverage(
        _ contentSize: CGSize?,
        _ actual: CGSize,
        _ allowsContentChange: Bool
    ) {
        guard let coverage = Self.coverage(contentSize, actual) else {
            referenceCoverage = nil
            return
        }
        guard !allowsContentChange, let referenceCoverage else {
            referenceCoverage = coverage
            return
        }
        if coverage.width * coverage.height > referenceCoverage.width *
            referenceCoverage.height {
            self.referenceCoverage = coverage
        }
    }

    mutating func takeRetry(_ token: UInt64) -> Bool {
        guard pendingRetry == token else { return false }
        pendingRetry = nil
        return true
    }

    private mutating func reset() {
        retries = 0
        pendingRetry = nil
        generation &+= 1
    }
}
