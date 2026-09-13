import Cocoa

@main struct RendererTests {
    static func png(_ size: Int) -> Data {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    }
    static func candidate(_ data: Data, maskable: Bool = false) -> [String: Any] {
        ["data": data.base64EncodedString(), "maskable": maskable, "kind": "fixture"]
    }
    static func compositionFixture(width: Int = 64, transparent: Bool = false, cornerMark: Bool = false) -> Data {
        let c = CGContext(data: nil, width: width, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: transparent ? 0 : 1))
        c.fill(CGRect(x: 0, y: 0, width: width, height: 64))
        c.setFillColor(CGColor(gray: transparent ? 0 : 1, alpha: 1))
        c.fill(CGRect(x: 8, y: 28, width: width - 16, height: 8))
        if cornerMark { c.fill(CGRect(x: 1, y: 1, width: 3, height: 3)) }
        return NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
    }
    static func rendered(_ data: Data) -> NSBitmapImageRep {
        NSBitmapImageRep(data: Data(base64Encoded: IconRenderer.render([candidate(data)])!.png)!)!
    }
    static func main() {
        let small = png(16), exact = png(64), large = png(256)
        assert(IconRenderer.render([candidate(small), candidate(large), candidate(exact)])!.sourcePixels == 64)
        assert(IconRenderer.render([candidate(small), candidate(large)])!.sourcePixels == 256)
        assert(IconRenderer.render([candidate(Data([0, 1, 2])), candidate(exact)]) != nil)
        assert(IconRenderer.render([candidate(Data(repeating: 0, count: 262145))]) == nil)
        let ordinary = IconRenderer.render([candidate(exact)])!
        let masked = IconRenderer.render([candidate(exact, maskable: true)])!
        let ordinaryBitmap = NSBitmapImageRep(data: Data(base64Encoded: ordinary.png)!)!
        let maskedBitmap = NSBitmapImageRep(data: Data(base64Encoded: masked.png)!)!
        assert(ordinaryBitmap.colorAt(x: 0, y: 0)!.alphaComponent < 0.01)
        assert(maskedBitmap.colorAt(x: 0, y: 0)!.alphaComponent < 0.01)
        assert(maskedBitmap.colorAt(x: 32, y: 32)!.alphaComponent > 0.99)
        for y in 0..<64 { for x in 0..<64 {
            if hypot(Double(x) + 0.5 - 32, Double(y) + 0.5 - 32) < 25.6 {
                assert(maskedBitmap.colorAt(x: x, y: y)!.alphaComponent > 0.99)
            }
        } }
        assert(ordinaryBitmap.colorAt(x: 32, y: 3)!.redComponent > 0.99)
        assert(ordinaryBitmap.colorAt(x: 32, y: 3)!.alphaComponent > 0.99)
        let touch = ["data": large.base64EncodedString(), "kind": "touch"] as [String: Any]
        let appIcon = ["data": png(512).base64EncodedString(), "kind": "manifest", "maskable": true] as [String: Any]
        assert(!IconRenderer.render([candidate(exact), touch, appIcon])!.maskable)
        assert(IconRenderer.render([candidate(exact), touch])!.sourcePixels == 64)
        // An ICO whose first frame is 16px must still select its 64px representation.
        var ico = Data([0, 0, 1, 0, 2, 0])
        func little(_ value: Int, _ count: Int) -> [UInt8] { (0..<count).map { UInt8((value >> ($0 * 8)) & 255) } }
        var offset = 38
        for (size, bytes) in [(16, small), (64, exact)] {
            ico.append(contentsOf: [UInt8(size), UInt8(size), 0, 0, 1, 0, 32, 0])
            ico.append(contentsOf: little(bytes.count, 4) + little(offset, 4)); offset += bytes.count
        }
        ico.append(small); ico.append(exact)
        assert(IconRenderer.render([candidate(ico)])!.sourcePixels == 64)
        let composed = rendered(compositionFixture())
        // A full-size white mark begins at x=8; the old inset would move it to x=12.5.
        assert(composed.colorAt(x: 10, y: 32)!.greenComponent > 0.99)
        assert(composed.colorAt(x: 0, y: 0)!.alphaComponent < 0.01)
        let marked = rendered(compositionFixture(cornerMark: true))
        assert(marked.colorAt(x: 10, y: 32)!.greenComponent < 0.2)
        assert(marked.colorAt(x: 9, y: 54)!.greenComponent > 0.9)
        let transparent = rendered(compositionFixture(transparent: true))
        assert(transparent.colorAt(x: 10, y: 32)!.redComponent > 0.99 && transparent.colorAt(x: 15, y: 32)!.redComponent < 0.1)
        let rectangular = rendered(compositionFixture(width: 96))
        assert(rectangular.colorAt(x: 8, y: 32)!.greenComponent < 0.2)
        assert(composed.colorAt(x: 1, y: 32)!.alphaComponent < 0.01)
        assert(composed.colorAt(x: 2, y: 32)!.alphaComponent > 0.99)
        let baseline = NSBitmapImageRep(data: Data(base64Encoded: IconRenderer.render([candidate(compositionFixture())], edgeHighlight: false)!.png)!)!
        var changed = 0
        for y in 0..<64 { for x in 0..<64 {
            let before = baseline.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            let after = composed.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            if before != after { changed += 1 }
            if (16..<48).contains(x) && (16..<48).contains(y) { assert(before == after) }
            assert(abs(before.alphaComponent - after.alphaComponent) < 0.02)
        } }
        assert(changed > 0 && changed < 600)
        assert(composed.colorAt(x: 32, y: 2)!.greenComponent > baseline.colorAt(x: 32, y: 2)!.greenComponent)
        assert(composed.colorAt(x: 32, y: 61)!.redComponent < baseline.colorAt(x: 32, y: 61)!.redComponent)
        let c = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(red: 0, green: 0.3, blue: 0.8, alpha: 1))
        c.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 64, height: 64), cornerWidth: 12, cornerHeight: 12, transform: nil))
        c.fillPath()
        let roundedSource = NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
        let rounded = rendered(roundedSource)
        assert(rounded.colorAt(x: 4, y: 32)!.redComponent < 0.1)
        assert(rounded.colorAt(x: 32, y: 32)!.blueComponent > 0.7)
        assert(rounded.colorAt(x: 0, y: 0)!.alphaComponent < 0.01)
        // Older rounded ICOs can carry quantized RGB in nearly transparent edge pixels.
        // Their visible contribution must not force a small logo onto a neutral frame.
        c.setBlendMode(.copy)
        c.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.8, alpha: 16.0 / 255.0))
        c.fill(CGRect(x: 2, y: 0, width: 1, height: 1))
        let quantizedEdge = NSBitmapImageRep(cgImage: c.makeImage()!)
        let quantizedData = quantizedEdge.representation(using: .png, properties: [:])!
        let quantized = rendered(quantizedData)
        assert(quantized.colorAt(x: 4, y: 32)!.blueComponent > 0.7 && quantized.colorAt(x: 4, y: 32)!.redComponent < 0.1)
        assert(quantized.colorAt(x: 32, y: 4)!.blueComponent > 0.7 && quantized.colorAt(x: 32, y: 4)!.redComponent < 0.1)
        assert(quantized.colorAt(x: 0, y: 0)!.alphaComponent < 0.01)
        assert(composed.colorAt(x: 32, y: 60)!.greenComponent > baseline.colorAt(x: 32, y: 60)!.greenComponent)
        // White-on-transparent artwork used by dark favicons must not disappear.
        let lightLogo = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        lightLogo.setFillColor(CGColor(gray: 1, alpha: 1))
        lightLogo.fillEllipse(in: CGRect(x: 12, y: 12, width: 40, height: 40))
        let lightData = NSBitmapImageRep(cgImage: lightLogo.makeImage()!).representation(using: .png, properties: [:])!
        let lightBitmap = rendered(lightData)
        assert(lightBitmap.colorAt(x: 32, y: 32)!.redComponent > 0.95)
        assert(lightBitmap.colorAt(x: 5, y: 32)!.redComponent < 0.2)
        assert(lightBitmap.colorAt(x: 0, y: 0)!.alphaComponent < 0.01)
        // A saturated mark with a white interior prefers a white tile, without a domain rule.
        lightLogo.clear(CGRect(x: 0, y: 0, width: 64, height: 64))
        lightLogo.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        lightLogo.fill(CGRect(x: 8, y: 16, width: 48, height: 32))
        lightLogo.setFillColor(CGColor(gray: 1, alpha: 1))
        lightLogo.fill(CGRect(x: 26, y: 24, width: 10, height: 16))
        let coloredData = NSBitmapImageRep(cgImage: lightLogo.makeImage()!).representation(using: .png, properties: [:])!
        let coloredBitmap = rendered(coloredData)
        assert(coloredBitmap.colorAt(x: 5, y: 32)!.redComponent > 0.95)
        assert(coloredBitmap.colorAt(x: 5, y: 32)!.greenComponent > 0.95)
        lightLogo.clear(CGRect(x: 0, y: 0, width: 64, height: 64))
        lightLogo.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.77, alpha: 1))
        lightLogo.fillEllipse(in: CGRect(x: 12, y: 12, width: 40, height: 40))
        let cyanData = NSBitmapImageRep(cgImage: lightLogo.makeImage()!).representation(using: .png, properties: [:])!
        let cyanBitmap = rendered(cyanData)
        assert(cyanBitmap.colorAt(x: 5, y: 32)!.redComponent > 0.95)
        // The same input remains deterministic across host appearances.
        var appearances = [String]()
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                appearances.append(IconRenderer.render([candidate(lightData)])!.png)
            }
        }
        assert(appearances[0] == appearances[1])
        let empty = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let emptyData = NSBitmapImageRep(cgImage: empty.makeImage()!).representation(using: .png, properties: [:])!
        assert(IconRenderer.render([candidate(emptyData)]) == nil)
        assert(IconRenderer.render([candidate(emptyData), candidate(exact)]) != nil)
        let placeholder = Data(base64Encoded: IconRenderer.websitePlaceholder()!)!
        let globe = NSBitmapImageRep(data: placeholder)!
        assert(globe.pixelsWide == 64 && globe.pixelsHigh == 64)
        var darkPixels = 0
        for x in 0..<globe.pixelsWide {
            for y in 0..<globe.pixelsHigh {
                let color = globe.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                if color.alphaComponent > 0.5 && color.redComponent < 0.6 { darkPixels += 1 }
            }
        }
        assert(darkPixels > 20, "Placeholder must contain visible globe artwork")
        try! placeholder.write(to: URL(fileURLWithPath: "/tmp/alttab-website-globe.png"))
        print("44 renderer checks passed, including quantized rounded edges and lower glint")
    }
}
