//import XCTest
//
//final class ImageScalingTests: XCTestCase {
//    /// 4ms
//    func testCgImageResizedWithCoreGraphics() throws {
//        let image = load20MbImage().cgImage()
//        measure(options: options) {
//            let _ = image.resizedCopyWithCoreGraphics(NSSize(width: 200, height: 200))
//        }
//    }
//
//    /// 4ms
//    func testNsImageResizedWithCoreGraphics() throws {
//        let image = load20MbImage()
//        measure(options: options) {
//            let _ = image.resizedWithCoreGraphics(NSSize(width: 200, height: 200))
//        }
//    }
//
//    /// 9ms
//    func testResizedWithNSGraphicsContext() throws {
//        let image = load20MbImage()
//        measure(options: options) {
//            let _ = image.resizedWithNSGraphicsContext(NSSize(width: 200, height: 200))
//        }
//    }
//
//    /// 42s
//    func testResizedWithCoreImage() throws {
//        let image = load20MbImage()
//        measure(options: options) {
//            let _ = image.resizedWithCoreImage(NSSize(width: 200, height: 200))
//        }
//    }
//
//    private var options: XCTMeasureOptions = {
//        let o = XCTMeasureOptions()
//        o.iterationCount = 10
//        return o
//    }()
//
//    private func load20MbImage() -> NSImage {
//        let bundle = Bundle(for: type(of: self))
//        let imagePath = bundle.path(forResource: "20MB-photo.jpg", ofType: nil)!
//        return NSImage(contentsOfFile: imagePath)!
//    }
//}
//
//extension NSImage {
//    func resizedWithNSGraphicsContext(_ newSize: NSSize) -> NSImage {
//        let newImage = NSImage(size: newSize)
//        newImage.lockFocus()
//        NSGraphicsContext.current?.imageInterpolation = .high
//        self.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size),
//            operation: .copy, fraction: 1.0)
//        newImage.unlockFocus()
//        return newImage
//    }
//
//    @available(macOS 10.15, *)
//    func resizedWithCoreImage(_ newSize: NSSize) -> NSImage {
//        let ciImage = CIImage(data: tiffRepresentation!)!
//        let filter = CIFilter.lanczosScaleTransform()
//        filter.inputImage = ciImage
//        let scaleX = newSize.width / size.width
//        let scaleY = newSize.height / size.height
//        let scale = min(scaleX, scaleY) // Preserve aspect ratio
//        filter.scale = Float(scale)
//        filter.aspectRatio = 1.0
//        let outputCIImage = filter.outputImage!
//        let context = CIContext(options: [CIContextOption.useSoftwareRenderer: false]) // Prefer GPU
//        let outputCGImage = context.createCGImage(outputCIImage, from: outputCIImage.extent)!
//        return NSImage(cgImage: outputCGImage, size: newSize)
//    }
//
//    func resizedWithCoreGraphics(_ newSize: NSSize) -> NSImage {
//        let image = cgImage()
//        let context = CGContext(data: nil,
//            width: Int(newSize.width),
//            height: Int(newSize.height),
//            bitsPerComponent: image.bitsPerComponent,
//            bytesPerRow: 0,
//            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
//            bitmapInfo: image.bitmapInfo.rawValue)!
//        context.interpolationQuality = .high
//        context.draw(image, in: CGRect(origin: .zero, size: newSize))
//        let scaledImage = context.makeImage()!
//        return NSImage(cgImage: scaledImage, size: newSize)
//    }
//}
