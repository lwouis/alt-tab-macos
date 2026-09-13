import Cocoa
import ImageIO

/// Decodes bounded candidates once, before AltTab sees the snapshot.
enum IconRenderer {
    struct Result {
        let png: String
        let sourcePixels: Int
        let kind: String
        let maskable: Bool
    }

    /// A stable neutral tile for completed web pages with no usable artwork.
    static func websitePlaceholder() -> String? {
        guard #available(macOS 12.0, *) else { return nil }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 60, height: 60),
                     xRadius: 13.125, yRadius: 13.125).fill()
        let symbol = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 40, weight: .regular))?
            .withSymbolConfiguration(.init(paletteColors: [.darkGray]))
        symbol?.draw(in: NSRect(x: 12, y: 12, width: 40, height: 40))
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return png.base64EncodedString()
    }

    static func render(_ candidates: [[String: Any]], edgeHighlight: Bool = true) -> Result? {
        var best: (source: CGImageSource, index: Int, pixels: Int, score: Int, kind: String, maskable: Bool)?
        for candidate in candidates.prefix(4) {
            guard let encoded = candidate["data"] as? String, encoded.count <= 350000,
                  let data = Data(base64Encoded: encoded), data.count <= 262144,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { continue }
            let isICO = (CGImageSourceGetType(source) as String?) == "com.microsoft.ico"
            let count = isICO ? min(CGImageSourceGetCount(source), 32) : min(CGImageSourceGetCount(source), 1)
            for index in 0..<count {
                guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
                      let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
                      let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
                      (16...2048).contains(width), (16...2048).contains(height) else { continue }
                let pixels = min(width, height)
                guard let decoded = thumbnail(source, index), hasVisibleArtwork(decoded) else { continue }
                let maskable = candidate["maskable"] as? Bool == true && width == height && isOpaque(decoded)
                let kind = candidate["kind"] as? String ?? "favicon"
                let vector = candidate["vector"] as? Bool == true
                let score = vector ? 0 : pixels >= 64 ? pixels - 64 : 1000 + 64 - pixels
                guard best == nil || score < best!.score else { continue }
                best = (source, index, pixels, score, kind, maskable)
            }
        }
        guard let best, let image = CGImageSourceCreateImageAtIndex(best.source, best.index, nil),
              let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        // Keep precomposed artwork at full size only when the corner regions are background.
        // Uncertain artwork remains contained so the mask cannot cut through its logo.
        // Native app artwork retains a small transparent margin after AltTab crops its icon canvas.
        let tile = CGRect(x: 2, y: 2, width: 60, height: 60)
        context.addPath(CGPath(roundedRect: tile,
                               cornerWidth: 13.125, cornerHeight: 13.125, transform: nil))
        context.clip()
        let fullTile = best.maskable || hasBackgroundCorners(image)
        if !fullTile {
            context.setFillColor(backgroundColor(image))
            context.fill(tile)
        }
        let extent: CGFloat = fullTile ? 60 : 48.75
        let scale = extent / CGFloat(max(image.width, image.height))
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        context.draw(image, in: CGRect(x: (64 - width) / 2, y: (64 - height) / 2, width: width, height: height))
        if edgeHighlight { drawEdgeHighlight(in: context); drawLowerGlint(in: context) }
        guard let output = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]) else { return nil }
        return Result(png: png.base64EncodedString(), sourcePixels: best.pixels, kind: best.kind, maskable: best.maskable)
    }

    private static func drawEdgeHighlight(in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        let edge = CGPath(roundedRect: CGRect(x: 2.5, y: 2.5, width: 59, height: 59),
                          cornerWidth: 12.625, cornerHeight: 12.625, transform: nil)
        context.addPath(edge)
        context.setBlendMode(.sourceAtop)
        context.setLineWidth(1)
        context.replacePathWithStrokedPath()
        context.clip()
        let colors = [CGColor(gray: 1, alpha: 0.40), CGColor(gray: 1, alpha: 0.08),
                      CGColor(gray: 0, alpha: 0.18)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                        locations: [0, 0.55, 1]) else { return }
        context.drawLinearGradient(gradient, start: CGPoint(x: 32, y: 62), end: CGPoint(x: 32, y: 2), options: [])
    }

    private static func drawLowerGlint(in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(CGPath(roundedRect: CGRect(x: 3.5, y: 3.5, width: 57, height: 57),
                               cornerWidth: 11.625, cornerHeight: 11.625, transform: nil))
        context.setBlendMode(.sourceAtop)
        context.setLineWidth(1)
        context.replacePathWithStrokedPath()
        context.clip()
        let colors = [CGColor(gray: 1, alpha: 0.24), CGColor(gray: 1, alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                        locations: [0, 1]) else { return }
        context.drawLinearGradient(gradient, start: CGPoint(x: 32, y: 3), end: CGPoint(x: 32, y: 15), options: [.drawsBeforeStartLocation])
    }

    private static func hasBackgroundCorners(_ image: CGImage) -> Bool {
        guard image.width == image.height else { return false }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let background = bitmap.colorAt(x: image.width / 2, y: 0)?.usingColorSpace(.deviceRGB),
              background.alphaComponent > 0.99 else { return false }
        // Inspect whole corner squares, larger than the region removed by the rounded mask.
        let cornerSize = Int(ceil(CGFloat(image.width) * 14 / 64))
        for originY in [0, image.height - cornerSize] {
            for originX in [0, image.width - cornerSize] {
                for y in originY..<(originY + cornerSize) {
                    for x in originX..<(originX + cornerSize) {
                        guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                        if pixel.alphaComponent < 0.01 { continue }
                        // Low-alpha edge pixels amplify quantization when unpremultiplied.
                        // Compare their visible contribution, not the hidden RGB difference.
                        let alpha = pixel.alphaComponent
                        guard abs(pixel.redComponent - background.redComponent) * alpha < 0.03,
                              abs(pixel.greenComponent - background.greenComponent) * alpha < 0.03,
                              abs(pixel.blueComponent - background.blueComponent) * alpha < 0.03 else { return false }
                    }
                }
            }
        }
        return true
    }

    private static func hasVisibleArtwork(_ image: CGImage) -> Bool {
        let bitmap = NSBitmapImageRep(cgImage: image)
        for y in 0..<image.height {
            for x in 0..<image.width {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { return true }
            }
        }
        return false
    }

    private static func isOpaque(_ image: CGImage) -> Bool {
        let bitmap = NSBitmapImageRep(cgImage: image)
        for y in 0..<image.height {
            for x in 0..<image.width {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) < 0.99 { return false }
            }
        }
        return true
    }

    private static func backgroundColor(_ image: CGImage) -> CGColor {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let corner = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB),
              corner.alphaComponent > 0.99 else { return contrastingBackground(image) }
        for y in 0..<image.height {
            for x in 0..<image.width where x == 0 || y == 0 || x == image.width - 1 || y == image.height - 1 {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      pixel.alphaComponent > 0.99,
                      abs(pixel.redComponent - corner.redComponent) < 0.03,
                      abs(pixel.greenComponent - corner.greenComponent) < 0.03,
                      abs(pixel.blueComponent - corner.blueComponent) < 0.03 else { return contrastingBackground(image) }
            }
        }
        return corner.cgColor
    }

    // Preserve the supplied logo color. Choose a neutral backing from visible artwork,
    // independently of the host appearance, so cached dark/light logos remain legible.
    private static func contrastingBackground(_ image: CGImage) -> CGColor {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var luminance: CGFloat = 0
        var weight: CGFloat = 0
        var visibleOnWhite: CGFloat = 0
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        for y in stride(from: 0, to: image.height, by: max(1, image.height / 64)) {
            for x in stride(from: 0, to: image.width, by: max(1, image.width / 64)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.05 else { continue }
                let alpha = color.alphaComponent
                let pixelLuminance = 0.2126 * linear(color.redComponent) +
                    0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
                luminance += alpha * pixelLuminance
                if 1.05 / (pixelLuminance + 0.05) >= 3 { visibleOnWhite += alpha }
                weight += alpha
            }
        }
        // Reserve dark backing for predominantly near-white artwork that would vanish on white.
        // Colored marks need not meet a text contrast threshold to retain their brand appearance.
        let value = weight > 0 ? luminance / weight : 0
        return CGColor(gray: weight > 0 && visibleOnWhite / weight < 0.1 && value > 0.75 ? 0.12 : 1, alpha: 1)
    }

    private static func thumbnail(_ source: CGImageSource, _ index: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }
}
