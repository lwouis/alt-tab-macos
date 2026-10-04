import XCTest

final class StageManagerCapturePolicyTests: XCTestCase {
    private let size = CGSize(width: 1000, height: 800)

    func testSidebarGeometryIsRejectedEvenWhenCaptureOutputIsRescaled() {
        XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(CGRect(x: 0, y: 0, width: 180, height: 120), size))
        XCTAssertTrue(StageManagerCapturePolicy.hasNormalGeometry(CGRect(origin: .zero, size: size), size))
    }

    func testBothDimensionsMustBeScaledToIdentifySidebarGeometry() {
        XCTAssertTrue(StageManagerCapturePolicy.hasNormalGeometry(CGRect(x: 0, y: 0, width: 699, height: 800), size))
        XCTAssertTrue(StageManagerCapturePolicy.hasNormalGeometry(CGRect(x: 0, y: 0, width: 700, height: 560), size))
        XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(CGRect(x: 0, y: 0, width: 699, height: 559), size))
    }

    func testUnknownGeometryDoesNotOverwriteLastGoodFrame() {
        XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(nil, size))
        XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(.zero, size))
        XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(CGRect(origin: .zero, size: size), .zero))
    }

    func testNonFiniteGeometryDoesNotOverwriteLastGoodFrame() {
        let normal = CGRect(origin: .zero, size: size)
        for invalid in [CGFloat.nan, .infinity, -.infinity] {
            for invalidSize in [CGSize(width: invalid, height: size.height), CGSize(width: size.width, height: invalid)] {
                XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(CGRect(origin: .zero, size: invalidSize), size))
                XCTAssertFalse(StageManagerCapturePolicy.hasNormalGeometry(normal, invalidSize))
            }
        }
    }

    func testTransparentOrTinyFramesDoNotBecomeCachedPreviews() {
        XCTAssertFalse(StageManagerCapturePolicy.hasUsablePixels(size, visibleSamples: 12, totalSamples: 256))
        XCTAssertTrue(StageManagerCapturePolicy.hasUsablePixels(size, visibleSamples: 13, totalSamples: 256))
        XCTAssertFalse(StageManagerCapturePolicy.hasUsablePixels(CGSize(width: 15, height: 800), visibleSamples: 256, totalSamples: 256))
        XCTAssertFalse(StageManagerCapturePolicy.hasUsablePixels(size, visibleSamples: 0, totalSamples: 0))
    }

    func testImageSamplingDistinguishesEmptyCaptureFromNormalPreview() {
        let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
            bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        XCTAssertFalse(StageManagerCapturePolicy.hasUsableImage(context.makeImage()!))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        XCTAssertTrue(StageManagerCapturePolicy.hasUsableImage(context.makeImage()!))
    }

    func testCaptureFromBeforeOffOnToggleCannotPublishInNewMode() {
        var mode = StageManagerCaptureMode()
        mode.update(true)
        let captureMode = mode
        mode.update(false)
        mode.update(true)
        XCTAssertNotEqual(captureMode, mode)
        XCTAssertTrue(mode.enabled)
    }

    func testProtectedCaptureCannotPublishAfterWindowLostFocusAndReturned() {
        var mode = StageManagerCaptureMode()
        mode.update(true)
        XCTAssertFalse(StageManagerCapturePolicy.allowsPublication(mode, mode,
            capturedFocus: 1, currentFocus: 3, isFocused: true))
        XCTAssertFalse(StageManagerCapturePolicy.allowsPublication(mode, mode,
            capturedFocus: 1, currentFocus: 1, isFocused: false))
        XCTAssertTrue(StageManagerCapturePolicy.allowsPublication(mode, mode,
            capturedFocus: 1, currentFocus: 1, isFocused: true))
    }

    func testProtectionOffPreservesBackgroundCaptureBehavior() {
        let mode = StageManagerCaptureMode()
        XCTAssertTrue(StageManagerCapturePolicy.allowsPublication(mode, mode,
            capturedFocus: 1, currentFocus: 3, isFocused: false))
    }

    func testUnchangedModeKeepsQueuedCapturesValid() {
        var mode = StageManagerCaptureMode()
        let captureMode = mode
        mode.update(false)
        XCTAssertEqual(captureMode, mode)
        mode.update(true)
        let protectedCaptureMode = mode
        mode.update(true)
        XCTAssertEqual(protectedCaptureMode, mode)
    }
}
