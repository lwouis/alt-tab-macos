import Cocoa

extension CGImage {
    func resizedCopyWithCoreGraphics(_ newSize: NSSize, _ fixBitmapInfo: Bool) -> CGImage {
        let finalBitmapInfo = fixBitmapInfo
            ? CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little)
            : bitmapInfo
        let context = CGContext(data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: finalBitmapInfo.rawValue
        )!
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(origin: .zero, size: newSize))
        return context.makeImage()!
    }
}
