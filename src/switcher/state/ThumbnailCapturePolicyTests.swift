import AppKit
import CoreGraphics
import XCTest

final class ThumbnailCapturePolicyTests: XCTestCase {
    private let expected = CGSize(width: 400, height: 300)
    private let partial = CGSize(width: 100, height: 75)

    private func retry(_ policy: inout ThumbnailCapturePolicy, actual: CGSize,
                       expected: CGSize) throws -> UInt64 {
        guard case let .retry(token) = policy.evaluate(actual: actual, expected: expected) else {
            XCTFail("A partial frame with retry budget must request a retry")
            throw NSError(domain: "ThumbnailCapturePolicyTests", code: 1)
        }
        return token
    }

    func testFirstPartialFrameIsNotAccepted() throws {
        var policy = ThumbnailCapturePolicy()
        _ = try retry(&policy, actual: partial, expected: expected)
    }

    func testExhaustionKeepsGoodThumbnailAndDoesNotRestartRetries() throws {
        var policy = ThumbnailCapturePolicy()
        XCTAssertEqual(policy.evaluate(actual: expected, expected: expected), .accept)
        var displayed = expected
        for _ in 0 ..< 3 {
            let token = try retry(&policy, actual: partial, expected: expected)
            XCTAssertTrue(policy.takeRetry(token))
        }
        for _ in 0 ..< 20 {
            let decision = policy.evaluate(actual: partial, expected: expected)
            if decision == .accept {
                displayed = partial
            }
            XCTAssertEqual(decision, .discard)
        }
        XCTAssertEqual(displayed, expected)
    }

    func testConcurrentPartialResultsShareOnePendingRetry() throws {
        var policy = ThumbnailCapturePolicy()
        let token = try retry(&policy, actual: partial, expected: expected)
        for _ in 0 ..< 8 { XCTAssertEqual(policy.evaluate(actual: partial, expected: expected), .discard) }
        XCTAssertTrue(policy.takeRetry(token))
        XCTAssertFalse(policy.takeRetry(token))
        _ = try retry(&policy, actual: partial, expected: expected)
    }

    func testGoodFrameInvalidatesPendingRetryAndRestoresBudget() throws {
        var policy = ThumbnailCapturePolicy()
        let old = try retry(&policy, actual: partial, expected: expected)
        XCTAssertEqual(policy.evaluate(actual: expected, expected: expected), .accept)
        let current = try retry(&policy, actual: partial, expected: expected)
        XCTAssertFalse(policy.takeRetry(old))
        XCTAssertTrue(policy.takeRetry(current))
    }

    func testResizeAcceptsLegitimatelySmallerWindow() throws {
        var policy = ThumbnailCapturePolicy()
        let old = try retry(&policy, actual: partial, expected: expected)
        XCTAssertEqual(policy.evaluate(actual: partial, expected: partial), .accept)
        XCTAssertFalse(policy.takeRetry(old))
    }

    func testGeometryChangeInvalidatesRetryAndResetsExhaustedBudget() throws {
        var policy = ThumbnailCapturePolicy()
        for _ in 0 ..< 3 {
            let token = try retry(&policy, actual: partial, expected: expected)
            XCTAssertTrue(policy.takeRetry(token))
        }
        XCTAssertEqual(policy.evaluate(actual: partial, expected: expected), .discard)
        let larger = CGSize(width: 800, height: 600)
        let old = try retry(&policy, actual: partial, expected: larger)
        let current = try retry(&policy, actual: partial, expected: expected)
        XCTAssertFalse(policy.takeRetry(old))
        XCTAssertTrue(policy.takeRetry(current))
    }

    func testGradualDegradationIsComparedToExpectedSize() {
        var policy = ThumbnailCapturePolicy()
        XCTAssertEqual(policy.evaluate(actual: expected, expected: expected), .accept)
        XCTAssertEqual(policy.evaluate(actual: CGSize(width: 360, height: 270), expected: expected), .accept)
        XCTAssertNotEqual(
            policy.evaluate(actual: CGSize(width: 324, height: 243), expected: expected),
            .accept
        )
    }

    func testRoundingAndLargerCapturesRemainAcceptable() {
        var policy = ThumbnailCapturePolicy()
        XCTAssertEqual(policy.evaluate(actual: CGSize(width: 399, height: 299), expected: expected), .accept)
        XCTAssertEqual(policy.evaluate(actual: CGSize(width: 800, height: 600), expected: expected), .accept)
        XCTAssertNotEqual(
            policy.evaluate(actual: CGSize(width: 400, height: 100), expected: expected),
            .accept
        )
    }

    func testNewWindowDoesNotInheritExhaustedPolicy() throws {
        var old = ThumbnailCapturePolicy()
        for _ in 0 ..< 3 {
            let token = try retry(&old, actual: partial, expected: expected)
            XCTAssertTrue(old.takeRetry(token))
        }
        var replacement = ThumbnailCapturePolicy()
        _ = try retry(&replacement, actual: partial, expected: expected)
    }

    func testSmallContentInsideFullCanvasPreservesEstablishedThumbnail() throws {
        let image = try image(content: CGRect(x: 16, y: 12, width: 32, height: 24))
        let content = try XCTUnwrap(ThumbnailCapturePolicy.contentPixelSize(image))
        XCTAssertEqual(image.width, 128)
        XCTAssertEqual(image.height, 96)
        XCTAssertEqual(content.width, 32, accuracy: 2)
        XCTAssertEqual(content.height, 24, accuracy: 2)
        var policy = ThumbnailCapturePolicy()
        let frame = CGSize(width: 128, height: 96)
        XCTAssertEqual(policy.evaluate(actual: frame, expected: frame, contentSize: frame), .accept)
        guard case .retry = policy.evaluate(actual: frame, expected: frame, contentSize: content) else {
            return XCTFail("A shelf-sized drawing must not replace an established full thumbnail")
        }
    }

    func testFullContentInAlphaImageIsAccepted() throws {
        let image = try image(content: CGRect(x: 0, y: 0, width: 128, height: 96))
        let content = try XCTUnwrap(ThumbnailCapturePolicy.contentPixelSize(image))
        var policy = ThumbnailCapturePolicy()
        XCTAssertEqual(policy.evaluate(actual: content, expected: CGSize(width: 128, height: 96)), .accept)
    }

    func testFaintShadowDoesNotMakeTinyContentLookFullSize() throws {
        let image = try image(content: CGRect(x: 16, y: 12, width: 32, height: 24), backgroundAlpha: 0.03)
        let content = try XCTUnwrap(ThumbnailCapturePolicy.contentPixelSize(image))
        XCTAssertEqual(content.width, 32, accuracy: 2)
        XCTAssertEqual(content.height, 24, accuracy: 2)
    }

    func testTransparentCaptureDoesNotClaimToProvePartialContent() throws {
        let image = try image(content: .zero)
        XCTAssertNil(ThumbnailCapturePolicy.contentPixelSize(image))
    }

    func testOpaqueImageUsesImageDimensionsInsteadOfAlphaSampling() throws {
        let image = try image(content: CGRect(x: 0, y: 0, width: 128, height: 96), opaque: true)
        XCTAssertNil(ThumbnailCapturePolicy.contentPixelSize(image))
    }

    func testLowOpacityFullWindowIsNotPartial() throws {
        let image = try image(content: .zero, backgroundAlpha: 0.05)
        let content = ThumbnailCapturePolicy.contentPixelSize(image) ?? CGSize(width: 128, height: 96)
        XCTAssertFalse(ThumbnailCapturePolicy.isPartial(content, CGSize(width: 128, height: 96)))
    }

    func testFullyClearWindowDoesNotPreserveObsoleteContent() throws {
        let image = try image(content: .zero)
        let content = ThumbnailCapturePolicy.contentPixelSize(image) ?? CGSize(width: 128, height: 96)
        XCTAssertFalse(ThumbnailCapturePolicy.isPartial(content, CGSize(width: 128, height: 96)))
    }

    func testLegitimateTransparentMarginsCanEstablishAndRefreshAThumbnail() {
        var policy = ThumbnailCapturePolicy()
        for _ in 0 ..< 12 {
            XCTAssertEqual(
                policy.evaluate(actual: expected, expected: expected, contentSize: partial),
                .accept
            )
        }
    }

    func testFocusedContentChangeReplacesAnExhaustedReference() {
        var policy = ThumbnailCapturePolicy()
        XCTAssertEqual(policy.evaluate(actual: expected, expected: expected, contentSize: expected), .accept)
        for _ in 0 ..< 3 {
            guard case let .retry(token) = policy.evaluate(
                actual: expected,
                expected: expected,
                contentSize: partial
            ) else {
                return XCTFail("Expected a bounded recovery request")
            }
            XCTAssertTrue(policy.takeRetry(token))
        }
        XCTAssertEqual(policy.evaluate(actual: expected, expected: expected, contentSize: partial), .discard)
        XCTAssertEqual(
            policy.evaluate(actual: expected, expected: expected, contentSize: partial,
                            allowsContentChange: true),
            .accept
        )
        XCTAssertEqual(policy.evaluate(actual: expected, expected: expected, contentSize: partial), .accept)
    }

    func testFocusedContentChangeInvalidatesPendingRetry() {
        var policy = ThumbnailCapturePolicy()
        XCTAssertEqual(policy.evaluate(actual: expected, expected: expected, contentSize: expected), .accept)
        guard case let .retry(token) = policy.evaluate(
            actual: expected,
            expected: expected,
            contentSize: partial
        ) else {
            return XCTFail("Expected a pending recovery")
        }
        XCTAssertEqual(
            policy.evaluate(actual: expected, expected: expected, contentSize: partial,
                            allowsContentChange: true),
            .accept
        )
        XCTAssertFalse(policy.takeRetry(token))
    }

    func testBackgroundAlphaCoverageCannotRatchetDownTheReference() {
        var policy = ThumbnailCapturePolicy()
        XCTAssertEqual(policy.evaluate(actual: expected, expected: expected, contentSize: expected), .accept)
        XCTAssertEqual(
            policy.evaluate(actual: expected, expected: expected, contentSize: CGSize(
                width: 320,
                height: 240
            )),
            .accept
        )
        XCTAssertNotEqual(
            policy.evaluate(actual: expected, expected: expected, contentSize: CGSize(
                width: 256,
                height: 192
            )),
            .accept
        )
    }

    func testMissingOrClearAlphaDoesNotKeepOldContentForever() {
        var policy = ThumbnailCapturePolicy()
        XCTAssertEqual(policy.evaluate(actual: expected, expected: expected, contentSize: expected), .accept)
        XCTAssertNotEqual(
            policy.evaluate(actual: expected, expected: expected, contentSize: partial),
            .accept
        )
        XCTAssertEqual(policy.evaluate(actual: expected, expected: expected, contentSize: nil), .accept)
        XCTAssertEqual(policy.evaluate(actual: expected, expected: expected, contentSize: partial), .accept)
    }

    func testPreviewAssessmentDoesNotConsumeThumbnailRetries() {
        var policy = ThumbnailCapturePolicy()
        XCTAssertEqual(policy.evaluate(actual: expected, expected: expected, contentSize: expected), .accept)
        let preview = CGSize(width: 1600, height: 1200)
        for _ in 0 ..< 20 {
            XCTAssertTrue(policy.isPartial(actual: preview, expected: preview, contentSize: partial))
        }
        guard case .retry = policy.evaluate(actual: expected, expected: expected, contentSize: partial) else {
            return XCTFail("Preview checks must not exhaust thumbnail recovery")
        }
    }

    func testDisplayScaleAndFullscreenChangesInvalidatePendingRecovery() {
        let geometries = [
            ThumbnailCapturePolicy.Geometry(
                size: CGSize(width: 800, height: 600),
                scaleFactor: 1,
                isFullscreen: false
            ),
            ThumbnailCapturePolicy.Geometry(
                size: CGSize(width: 800, height: 600),
                scaleFactor: 2,
                isFullscreen: false
            ),
            ThumbnailCapturePolicy.Geometry(
                size: CGSize(width: 800, height: 600),
                scaleFactor: 2,
                isFullscreen: true
            ),
            ThumbnailCapturePolicy.Geometry(
                size: CGSize(width: 1600, height: 1200),
                scaleFactor: 2,
                isFullscreen: false
            ),
        ]
        var policy = ThumbnailCapturePolicy()
        for geometry in geometries {
            XCTAssertEqual(
                policy.evaluate(actual: expected, expected: expected, contentSize: expected,
                                geometry: geometry),
                .accept
            )
            guard case let .retry(token) = policy.evaluate(
                actual: expected,
                expected: expected,
                contentSize: partial,
                geometry: geometry
            ) else {
                return XCTFail("Expected recovery for the old geometry")
            }
            let changed = ThumbnailCapturePolicy.Geometry(
                size: geometry.size,
                scaleFactor: geometry.scaleFactor + 1,
                isFullscreen: !geometry.isFullscreen
            )
            XCTAssertNotEqual(geometry, changed)
            XCTAssertEqual(
                policy.evaluate(actual: expected, expected: expected, contentSize: partial,
                                geometry: changed),
                .accept
            )
            XCTAssertFalse(policy.takeRetry(token))
        }
    }

    func testMinimizeRestoreRejectsPartialFramesThenRecovers() throws {
        var policy = ThumbnailCapturePolicy()
        XCTAssertEqual(policy.evaluate(actual: expected, expected: expected, contentSize: expected), .accept)
        for _ in 0 ..< 3 {
            let token = try retry(&policy, actual: partial, expected: expected)
            XCTAssertTrue(policy.takeRetry(token))
        }
        XCTAssertEqual(
            policy.evaluate(actual: partial, expected: expected, allowsContentChange: true),
            .discard
        )
        XCTAssertEqual(
            policy.evaluate(actual: expected, expected: expected, contentSize: expected,
                            allowsContentChange: true),
            .accept
        )
    }

    func testVeryWideAndTallWindowsRetainTheirContentBounds() throws {
        for size in [CGSize(width: 4096, height: 16), CGSize(width: 16, height: 4096)] {
            let image = try image(content: CGRect(origin: .zero, size: size), size: size)
            let content = try XCTUnwrap(ThumbnailCapturePolicy.contentPixelSize(image))
            XCTAssertFalse(ThumbnailCapturePolicy.isPartial(content, size))
        }
    }

    func testAppKitRenderedTransparentWindowsAreUsable() throws {
        _ = NSApplication.shared
        for opacity: CGFloat in [0, 0.05, 0.5] {
            let view = TransparentThumbnailFixture(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
            view.opacity = opacity
            let window = NSWindow(
                contentRect: view.bounds,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = view
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let image = try XCTUnwrap(bitmap.cgImage)
            let frame = CGSize(width: image.width, height: image.height)
            let content = ThumbnailCapturePolicy.contentPixelSize(image)
            var policy = ThumbnailCapturePolicy()
            XCTAssertEqual(policy.evaluate(actual: frame, expected: frame, contentSize: content), .accept)
            XCTAssertEqual(policy.evaluate(actual: frame, expected: frame, contentSize: content), .accept)
        }
    }

    func testMetadataUsesDisplayScaleAndClipsToBuffer() {
        let size = ThumbnailCapturePolicy.contentPixelSize(CGRect(x: 0, y: 0, width: 200, height: 150),
                                                           scaleFactor: 2, frameSize: expected)
        XCTAssertEqual(size, expected)
        let clipped = ThumbnailCapturePolicy.contentPixelSize(CGRect(x: 50, y: 0, width: 200, height: 150),
                                                              scaleFactor: 2, frameSize: expected)
        XCTAssertEqual(clipped, CGSize(width: 300, height: 300))
    }

    func testMetadataDetectsSmallDrawingAndRejectsInvalidValues() throws {
        let content = try XCTUnwrap(ThumbnailCapturePolicy.contentPixelSize(
            CGRect(x: 0, y: 0, width: 50, height: 37.5),
            scaleFactor: 2,
            frameSize: expected
        ))
        XCTAssertEqual(content, partial)
        XCTAssertTrue(ThumbnailCapturePolicy.isPartial(content, expected))
        for scale: CGFloat in [0, -.infinity, .nan] {
            XCTAssertNil(ThumbnailCapturePolicy.contentPixelSize(CGRect(x: 0, y: 0, width: 50, height: 40),
                                                                 scaleFactor: scale, frameSize: expected))
        }
        XCTAssertNil(ThumbnailCapturePolicy.contentPixelSize(CGRect(x: 900, y: 900, width: 50, height: 40),
                                                             scaleFactor: 2, frameSize: expected))
    }

    private func image(content: CGRect, backgroundAlpha: CGFloat = 0,
                       opaque: Bool = false,
                       size: CGSize = CGSize(width: 128, height: 96)) throws -> CGImage {
        let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width) * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alpha.rawValue
        ))
        context.setFillColor(CGColor(gray: 0, alpha: backgroundAlpha))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(content)
        return try XCTUnwrap(context.makeImage())
    }
}

private final class TransparentThumbnailFixture: NSView {
    var opacity: CGFloat = 0
    override var isOpaque: Bool {
        false
    }

    override func draw(_: NSRect) {
        NSColor.white.withAlphaComponent(opacity).setFill()
        bounds.fill()
        NSColor.blue.setFill()
        bounds.insetBy(dx: bounds.width * 0.35, dy: bounds.height * 0.35).fill()
    }
}
