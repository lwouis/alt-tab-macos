import XCTest

final class WebsiteIconsTests: XCTestCase {
    func testHomepageDropsPathQueryFragmentAndCleartext() {
        XCTAssertEqual(homepage("https://darioamodei.com/post/essay?q=private#section"), "https://darioamodei.com/")
        XCTAssertEqual(homepage("http://www.google.com/search?q=private"), "https://www.google.com/")
        XCTAssertEqual(homepage("https://www.google.com/?client=safari"), "https://www.google.com/")
        XCTAssertNil(homepage("https://user:secret@example.org/"))
        XCTAssertNil(homepage("https://example.org:8443/"))
        XCTAssertNil(homepage("file:///tmp/page.html"))
        XCTAssertNil(homepage("chrome://newtab/"))
    }

    func testRejectsLocalNamesAndAddressLiterals() {
        for raw in ["http://example.org/icon.png", "https://localhost/", "https://printer.local/", "https://router.home.arpa/",
                    "https://127.0.0.1/", "https://2130706433/", "https://[::1]/", "https://intranet/", "https://example.org:8443/"] {
            XCTAssertFalse(WebsiteIconResolver.isPublic(URL(string: raw)!), raw)
        }
        XCTAssertTrue(WebsiteIconResolver.isPublic(URL(string: "https://github.githubassets.com/favicons/favicon.png")!))
    }

    func testScreensNonPublicAddresses() {
        for address: [UInt8] in [[127, 0, 0, 1], [10, 1, 1, 1], [192, 168, 1, 1], [169, 254, 1, 1], [100, 64, 0, 1], [172, 16, 0, 1], [224, 0, 0, 1]] {
            XCTAssertFalse(WebsiteIconResolver.isPublicAddress(address), "\(address)")
        }
        XCTAssertFalse(WebsiteIconResolver.isPublicAddress([UInt8](repeating: 0, count: 16)))
        XCTAssertTrue(WebsiteIconResolver.isPublicAddress([8, 8, 8, 8]))
        XCTAssertTrue(WebsiteIconResolver.isPublicAddress([0x26, 0x06, 0x47, 0x00] + [UInt8](repeating: 0, count: 12)))
    }

    func testCandidatesHonorBaseTouchIconsAndFaviconFallback() {
        let html = Data("""
            <html><head><base href='https://cdn.example.org/assets/'><link rel='icon' href='a.png'><link rel='ICON' href='a.png'>
            <link rel='apple-touch-icon' href='b.png'><link rel='icon' href='https://127.0.0.1/icon'></head></html>
            """.utf8)
        XCTAssertEqual(WebsiteIconResolver.candidates(in: html, page: URL(string: "https://www.example.org/")!).map(\.absoluteString),
                       ["https://cdn.example.org/assets/a.png", "https://cdn.example.org/assets/b.png", "https://www.example.org/favicon.ico"])
    }

    func testOpaqueSquareFillsTheRoundedTile() {
        let icon = render(png { $0.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) })!
        XCTAssertLessThan(pixel(icon, 0, 0).alphaComponent, 0.01)
        XCTAssertGreaterThan(pixel(icon, 32, 3).redComponent, 0.99)
        XCTAssertGreaterThan(pixel(icon, 32, 3).alphaComponent, 0.99)
    }

    /// GitHub's favicon is a dark circle touching the image edges with transparent corners.
    func testEdgeTouchingCircleGetsWhiteBacking() {
        let icon = render(png(32) { $0.setFillColor(CGColor(gray: 0.14, alpha: 1)); $0.fillEllipse(in: CGRect(x: 0, y: 0, width: 32, height: 32)) })!
        XCTAssertGreaterThan(pixel(icon, 8, 8).alphaComponent, 0.99)
        XCTAssertGreaterThan(pixel(icon, 8, 8).redComponent, 0.9)
        XCTAssertLessThan(pixel(icon, 32, 32).redComponent, 0.3)
    }

    func testArtworkThatVanishesOnWhiteGetsDarkBacking() {
        for color in [CGColor(gray: 1, alpha: 1), CGColor(red: 1, green: 0.92, blue: 0.5, alpha: 1)] {
            let icon = render(png { $0.setFillColor(color); $0.fillEllipse(in: CGRect(x: 12, y: 12, width: 40, height: 40)) })!
            XCTAssertLessThan(pixel(icon, 5, 32).redComponent, 0.2)
            XCTAssertGreaterThan(pixel(icon, 32, 32).redComponent, 0.95)
        }
    }

    func testColoredArtworkKeepsWhiteBacking() {
        let cyan = render(png { $0.setFillColor(CGColor(red: 0.1, green: 0.7, blue: 0.77, alpha: 1)); $0.fillEllipse(in: CGRect(x: 12, y: 12, width: 40, height: 40)) })!
        XCTAssertGreaterThan(pixel(cyan, 5, 32).redComponent, 0.95)
        let redWithWhiteInterior = render(png {
            $0.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            $0.fill(CGRect(x: 8, y: 16, width: 48, height: 32))
            $0.setFillColor(CGColor(gray: 1, alpha: 1))
            $0.fill(CGRect(x: 26, y: 24, width: 10, height: 16))
        })!
        XCTAssertGreaterThan(pixel(redWithWhiteInterior, 5, 32).greenComponent, 0.95)
    }

    func testPreRoundedArtworkStaysFullSizeDespiteQuantizedEdges() {
        let icon = render(png {
            $0.setFillColor(CGColor(red: 0, green: 0.3, blue: 0.8, alpha: 1))
            $0.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 64, height: 64), cornerWidth: 12, cornerHeight: 12, transform: nil))
            $0.fillPath()
            $0.setBlendMode(.copy)
            $0.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.8, alpha: 16.0 / 255.0))
            $0.fill(CGRect(x: 2, y: 0, width: 1, height: 1))
        })!
        XCTAssertGreaterThan(pixel(icon, 4, 32).blueComponent, 0.7)
        XCTAssertLessThan(pixel(icon, 4, 32).redComponent, 0.1)
        XCTAssertLessThan(pixel(icon, 0, 0).alphaComponent, 0.01)
    }

    func testIcoUsesTheFrameClosestTo64Pixels() {
        let small = png(16) { $0.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); $0.fill(CGRect(x: 0, y: 0, width: 16, height: 16)) }
        let exact = png { $0.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) }
        var ico = Data([0, 0, 1, 0, 2, 0])
        var offset = 6 + 16 * 2
        for (size, frame) in [(16, small), (64, exact)] {
            ico.append(contentsOf: [UInt8(size), UInt8(size), 0, 0, 1, 0, 32, 0] + littleEndian(frame.count) + littleEndian(offset))
            offset += frame.count
        }
        ico.append(small)
        ico.append(exact)
        XCTAssertGreaterThan(pixel(render(ico)!, 32, 32).blueComponent, 0.99)
    }

    func testSkipsUndecodableEmptyAndOversizedCandidates() {
        let empty = png { _ in }
        let red = png { $0.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); $0.fill(CGRect(x: 0, y: 0, width: 64, height: 64)) }
        XCTAssertNil(WebsiteIconRenderer.render([Data([0, 1, 2])]))
        XCTAssertNil(WebsiteIconRenderer.render([empty]))
        XCTAssertNil(WebsiteIconRenderer.render([Data(repeating: 0, count: 262_145)]))
        XCTAssertNotNil(WebsiteIconRenderer.render([Data([0, 1, 2]), empty, red]))
    }

    func testRenderingIgnoresSystemAppearance() {
        let logo = png { $0.setFillColor(CGColor(gray: 1, alpha: 1)); $0.fillEllipse(in: CGRect(x: 12, y: 12, width: 40, height: 40)) }
        var outputs = [Data]()
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                outputs.append(NSBitmapImageRep(cgImage: WebsiteIconRenderer.render([logo])!).representation(using: .png, properties: [:])!)
            }
        }
        XCTAssertEqual(outputs[0], outputs[1])
    }

    func testPlaceholderShowsAGlobe() throws {
        guard #available(macOS 12.0, *) else { throw XCTSkip("SF Symbols palette colors need macOS 12") }
        let globe = NSBitmapImageRep(cgImage: try XCTUnwrap(WebsiteIconRenderer.placeholder))
        XCTAssertEqual(globe.pixelsWide, 64)
        let darkPixels = (0..<64).flatMap { x in (0..<64).map { y in pixel(globe, x, y) } }
            .filter { $0.alphaComponent > 0.5 && $0.redComponent < 0.6 }.count
        XCTAssertGreaterThan(darkPixels, 20)
    }

    private func homepage(_ raw: String) -> String? {
        WebsiteIconResolver.homepage(for: URL(string: raw)!)?.absoluteString
    }

    private func png(_ size: Int = 64, _ draw: (CGContext) -> Void) -> Data {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(context)
        return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
    }

    private func render(_ data: Data) -> NSBitmapImageRep? {
        WebsiteIconRenderer.render([data]).map { NSBitmapImageRep(cgImage: $0) }
    }

    private func pixel(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> NSColor {
        bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    }

    private func littleEndian(_ value: Int) -> [UInt8] {
        (0..<4).map { UInt8((value >> ($0 * 8)) & 255) }
    }
}
