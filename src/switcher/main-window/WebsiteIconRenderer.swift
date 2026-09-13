import Cocoa
import ImageIO

/// Normalizes website artwork into a 64px rounded tile, so sites sit next to app icons. The output never depends on
/// the system appearance: the same tile is cached and shown in light and dark mode.
enum WebsiteIconRenderer {
    private static let tile = CGRect(x: 2, y: 2, width: 60, height: 60)
    private static let cornerRadius: CGFloat = 13.125

    /// A neutral tile for web pages that have no usable artwork.
    static let placeholder: CGImage? = {
        guard #available(macOS 12.0, *), let context = makeContext() else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: tile, xRadius: cornerRadius, yRadius: cornerRadius).fill()
        NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 40, weight: .regular))?
            .withSymbolConfiguration(.init(paletteColors: [.darkGray]))?
            .draw(in: NSRect(x: 12, y: 12, width: 40, height: 40))
        return context.makeImage()
    }()

    static func render(_ candidates: [Data]) -> CGImage? {
        guard let image = bestImage(candidates), let context = makeContext() else { return nil }
        context.interpolationQuality = .high
        context.addPath(CGPath(roundedRect: tile, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        context.clip()
        let fullTile = hasBackgroundCorners(image)
        if !fullTile {
            context.setFillColor(backgroundColor(image))
            context.fill(tile)
        }
        let scale = (fullTile ? 60 : 48.75) / CGFloat(max(image.width, image.height))
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        context.draw(image, in: CGRect(x: (64 - width) / 2, y: (64 - height) / 2, width: width, height: height))
        drawEdgeHighlight(in: context)
        drawLowerGlint(in: context)
        return context.makeImage()
    }

    /// The first 4 candidates are considered; ICO files contribute each frame. The frame closest to 64px wins,
    /// preferring larger frames over smaller ones.
    private static func bestImage(_ candidates: [Data]) -> CGImage? {
        var best: (image: CGImage, score: Int)?
        for data in candidates.prefix(4) where data.count <= 262_144 {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { continue }
            let isIco = (CGImageSourceGetType(source) as String?) == "com.microsoft.ico"
            for index in 0..<min(CGImageSourceGetCount(source), isIco ? 32 : 1) {
                guard let pixels = pixelSize(source, index) else { continue }
                let score = pixels >= 64 ? pixels - 64 : 1000 + 64 - pixels
                guard best == nil || score < best!.score, let preview = thumbnail(source, index), hasVisibleArtwork(preview),
                      let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
                best = (image, score)
            }
        }
        return best?.image
    }

    private static func pixelSize(_ source: CGImageSource, _ index: Int) -> Int? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              (16...2048).contains(width), (16...2048).contains(height) else { return nil }
        return min(width, height)
    }

    private static func makeContext() -> CGContext? {
        CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func drawEdgeHighlight(in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.addPath(CGPath(roundedRect: CGRect(x: 2.5, y: 2.5, width: 59, height: 59),
                               cornerWidth: 12.625, cornerHeight: 12.625, transform: nil))
        context.setBlendMode(.sourceAtop)
        context.setLineWidth(1)
        context.replacePathWithStrokedPath()
        context.clip()
        let colors = [CGColor(gray: 1, alpha: 0.40), CGColor(gray: 1, alpha: 0.08), CGColor(gray: 0, alpha: 0.18)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) else { return }
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
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
        context.drawLinearGradient(gradient, start: CGPoint(x: 32, y: 3), end: CGPoint(x: 32, y: 15), options: [.drawsBeforeStartLocation])
    }

    /// Artwork keeps its full size only when its corners are one opaque background color wherever the rounded mask
    /// leaves them visible. A transparent pixel there (e.g. GitHub's circular mark touching the image edges) would let the
    /// row's selection color show through, so that artwork is inset on a backing instead. Pixels the mask removes may be
    /// transparent (pre-rounded artwork), but must not carry a different color, or the mask would cut through the logo.
    private static func hasBackgroundCorners(_ image: CGImage) -> Bool {
        guard image.width == image.height else { return false }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let background = bitmap.colorAt(x: image.width / 2, y: 0)?.usingColorSpace(.deviceRGB),
              background.alphaComponent > 0.99 else { return false }
        let cornerSize = Int(ceil(CGFloat(image.width) * 14 / 64))
        for originY in [0, image.height - cornerSize] {
            for originX in [0, image.width - cornerSize] {
                for y in originY..<(originY + cornerSize) {
                    for x in originX..<(originX + cornerSize) {
                        guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                        if isVisibleInTile(x, y, image.width) {
                            guard pixel.alphaComponent > 0.97, matches(pixel, background, weight: 1) else { return false }
                        } else if pixel.alphaComponent >= 0.01 {
                            // Nearly transparent edge pixels carry quantized RGB; compare their visible contribution.
                            guard matches(pixel, background, weight: pixel.alphaComponent) else { return false }
                        }
                    }
                }
            }
        }
        return true
    }

    /// A 1.5pt margin keeps the antialiased edge of pre-rounded artwork out of the visible region.
    private static func isVisibleInTile(_ x: Int, _ y: Int, _ size: Int) -> Bool {
        let scale = tile.width / CGFloat(size), inner = tile.width / 2 - cornerRadius
        let dx = max(0, abs(tile.minX + (CGFloat(x) + 0.5) * scale - tile.midX) - inner)
        let dy = max(0, abs(tile.minY + (CGFloat(y) + 0.5) * scale - tile.midY) - inner)
        return hypot(dx, dy) < cornerRadius - 1.5
    }

    private static func matches(_ pixel: NSColor, _ background: NSColor, weight: CGFloat) -> Bool {
        abs(pixel.redComponent - background.redComponent) * weight < 0.03
            && abs(pixel.greenComponent - background.greenComponent) * weight < 0.03
            && abs(pixel.blueComponent - background.blueComponent) * weight < 0.03
    }

    private static func hasVisibleArtwork(_ image: CGImage) -> Bool {
        let bitmap = NSBitmapImageRep(cgImage: image)
        for y in 0..<image.height {
            for x in 0..<image.width where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                return true
            }
        }
        return false
    }

    /// Opaque artwork with a uniform border extends that border color, so the inset looks intentional.
    private static func backgroundColor(_ image: CGImage) -> CGColor {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let corner = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB),
              corner.alphaComponent > 0.99 else { return contrastingBackground(image) }
        for y in 0..<image.height {
            for x in 0..<image.width where x == 0 || y == 0 || x == image.width - 1 || y == image.height - 1 {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), pixel.alphaComponent > 0.99,
                      matches(pixel, corner, weight: 1) else { return contrastingBackground(image) }
            }
        }
        return corner.cgColor
    }

    /// Transparent artwork gets a white backing, like app icons, and keeps its brand colors. Only artwork that barely
    /// shows on white (under 1.5:1 contrast for over 90% of its visible area, e.g. white or pale-yellow marks) gets a dark
    /// backing instead; a white badge with a small dark logo (apple.com) stays on white. Either backing contrasts at
    /// least 3:1 with the selected row's accent color.
    private static func contrastingBackground(_ image: CGImage) -> CGColor {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var weight: CGFloat = 0
        var visibleOnWhite: CGFloat = 0
        for y in stride(from: 0, to: image.height, by: max(1, image.height / 64)) {
            for x in stride(from: 0, to: image.width, by: max(1, image.width / 64)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.alphaComponent > 0.05 else { continue }
                weight += color.alphaComponent
                if 1.05 / (relativeLuminance(color) + 0.05) >= 1.5 { visibleOnWhite += color.alphaComponent }
            }
        }
        return CGColor(gray: weight > 0 && visibleOnWhite / weight < 0.1 ? 0.12 : 1, alpha: 1)
    }

    private static func relativeLuminance(_ color: NSColor) -> CGFloat {
        func linear(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
    }

    private static func thumbnail(_ source: CGImageSource, _ index: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }
}
