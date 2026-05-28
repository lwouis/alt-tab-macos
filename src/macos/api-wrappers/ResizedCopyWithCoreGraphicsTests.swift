import XCTest
import Cocoa

/// Pins `CGImage.resizedCopyWithCoreGraphics` — the resize used on every window thumbnail before
/// it reaches the switcher. The function builds a CGContext at the target size, optionally
/// normalizes the bitmap info to `premultipliedFirst | byteOrder32Little` (the format AppKit
/// expects for the thumbnail compositor), draws the source at high interpolation, and returns
/// the result.
///
/// Lives in its own file (not `OnActionExtensionTests.swift`) because the topic is CGImage
/// resizing, not the `NSControl.onAction` extension — even though both extensions are defined in
/// `HelperExtensionsTestable.swift`.
final class ResizedCopyWithCoreGraphicsTests: XCTestCase {

    // MARK: - Helpers

    /// Build a solid-color CGImage with explicit dimensions + a sane sRGB colorspace + an alpha
    /// channel. Used as input to the resize under test.
    private func makeImage(width: Int, height: Int,
                           alphaInfo: CGImageAlphaInfo = .premultipliedLast) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil,
                            width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: space,
                            bitmapInfo: alphaInfo.rawValue)!
        ctx.setFillColor(NSColor.red.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    // MARK: - Dimensions

    func testResizeDownscaleProducesExpectedDimensions() {
        let src = makeImage(width: 200, height: 100)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 50, height: 25), false)
        XCTAssertEqual(out.width, 50)
        XCTAssertEqual(out.height, 25)
    }

    func testResizeUpscaleProducesExpectedDimensions() {
        let src = makeImage(width: 32, height: 32)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 128, height: 96), false)
        XCTAssertEqual(out.width, 128)
        XCTAssertEqual(out.height, 96)
    }

    func testResizeNonSquareAspectRatioIsHonored() {
        let src = makeImage(width: 100, height: 100)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 80, height: 20), false)
        XCTAssertEqual(out.width, 80)
        XCTAssertEqual(out.height, 20)
    }

    // MARK: - Bitmap info

    /// `fixBitmapInfo == true` is the thumbnail-pipeline path: it normalizes alpha to
    /// `premultipliedFirst` and byte order to `byteOrder32Little` so the compositor doesn't have
    /// to convert per-frame.
    func testFixBitmapInfoNormalizesAlphaAndByteOrder() {
        let src = makeImage(width: 50, height: 50, alphaInfo: .premultipliedLast)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 25, height: 25), true)
        // Alpha info is encoded in the low bits of bitmapInfo.
        XCTAssertEqual(out.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue,
                       CGImageAlphaInfo.premultipliedFirst.rawValue,
                       "fixBitmapInfo must force alpha to premultipliedFirst")
        XCTAssertTrue(out.bitmapInfo.contains(.byteOrder32Little),
                      "fixBitmapInfo must force byteOrder32Little")
    }

    /// `fixBitmapInfo == false` is the rare path used outside the thumbnail compositor — the
    /// source's bitmap info must be preserved (no silent normalization).
    func testNoFixBitmapInfoPreservesSourceAlpha() {
        let src = makeImage(width: 50, height: 50, alphaInfo: .premultipliedLast)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 25, height: 25), false)
        XCTAssertEqual(out.bitmapInfo.rawValue & CGBitmapInfo.alphaInfoMask.rawValue,
                       CGImageAlphaInfo.premultipliedLast.rawValue,
                       "without fixBitmapInfo, the source's alpha info should survive untouched")
    }

    // MARK: - Pixel content sanity

    /// A solid-red source resized stays solid-red — sample a pixel via a CGContext readback to
    /// confirm the draw actually ran (catches a regression where the context is created but
    /// `draw(_:in:)` is omitted).
    func testResizePreservesSolidColor() {
        let src = makeImage(width: 100, height: 100)
        let out = src.resizedCopyWithCoreGraphics(NSSize(width: 10, height: 10), true)
        // Render the resized image into a 1x1 byte buffer at the center and check the red channel.
        var pixel: [UInt8] = [0, 0, 0, 0]
        let ctx = CGContext(data: &pixel,
                            width: 1, height: 1,
                            bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(out, in: CGRect(x: -5, y: -5, width: 10, height: 10))
        // Premultiplied last: layout is R G B A. Red channel should be ~255.
        XCTAssertGreaterThan(pixel[0], 200, "the resized image should still be predominantly red")
    }
}
