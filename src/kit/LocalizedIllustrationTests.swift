import Cocoa
import CoreText
import XCTest

final class LocalizedIllustrationTests: XCTestCase {
    private var resources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("resources/native-illustrations")
    }

    func testEveryIllustrationUsesReusableNativeVectorDrawing() throws {
        let drawer = try IllustrationDrawer(directory: resources)
        XCTAssertEqual(drawer.archive.scenes.count, 29)
        for name in drawer.archive.scenes.keys {
            let image = try XCTUnwrap(drawer.image(name), name)
            XCTAssertTrue(image.representations.contains { $0 is NSCustomImageRep }, name)
            XCTAssertFalse(image.representations.contains { $0 is NSBitmapImageRep }, name)
            let bitmap = try rendered(image)
            XCTAssertGreaterThan(bitmap.pixelsWide, 0)
            XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
            XCTAssertNotEqual(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2), .white, name)
        }
        XCTAssertNil(drawer.image("missing"))
    }

    func testLongTextFitsAndPreservesCompleteCharacters() {
        let cluster = "👨‍👩‍👦"
        let fitted = IllustrationDrawer.fit(String(repeating: cluster, count: 100), size: 16,
            minimum: 12, maximum: 160, bold: false)
        XCTAssertEqual(fitted.size, 12)
        XCTAssertTrue(fitted.text.hasSuffix("…"))
        XCTAssertTrue(fitted.text.dropLast().allSatisfy { String($0) == cluster })
        XCTAssertLessThanOrEqual((fitted.text as NSString).size(withAttributes:
            [.font: IllustrationDrawer.font(fitted.size, bold: false)]).width, 158)
    }

    func testArabicUsesTheSameFontForFittingAndDrawing() {
        let fitted = IllustrationDrawer.fit(String(repeating: "رحلة اليابان — نافذة جديدة ", count: 8),
            size: 16, minimum: 12, maximum: 160, bold: true)
        XCTAssertTrue(fitted.text.hasSuffix("…"))
        XCTAssertLessThanOrEqual((fitted.text as NSString).size(withAttributes:
            [.font: IllustrationDrawer.font(fitted.size, bold: true)]).width, 158)
    }

    func testSmallFontRoundingDoesNotTruncateATitleThatFitsAtMinimumSize() {
        let fitted = IllustrationDrawer.fit("Anteckningar", size: 8, minimum: 6, maximum: 45, bold: true)
        XCTAssertEqual(fitted.text, "Anteckningar")
        XCTAssertGreaterThanOrEqual(fitted.size, 6)
        XCTAssertLessThanOrEqual((fitted.text as NSString).size(withAttributes:
            [.font: IllustrationDrawer.font(fitted.size, bold: true)]).width, 43)
    }

    func testTranslationIsLiteralAndDecorativeImageHasNoAccessibilityDescription() throws {
        let drawer = try IllustrationDrawer(directory: resources)
        let value = "<image href='file:///private/test'/> & " + String(repeating: "A long title ", count: 20)
        let image = try XCTUnwrap(drawer.image("settings-app-icons") { _, _ in value })
        XCTAssertNil(image.accessibilityDescription)
        XCTAssertNotEqual(try rendered(image).representation(using: .png, properties: [:]),
            try rendered(XCTUnwrap(drawer.image("settings-app-icons"))).representation(using: .png, properties: [:]))
    }

    func testDecorativeIllustrationViewIsExcludedFromAccessibility() {
        let view = LocalizedIllustrationView("settings-titles")
        XCTAssertFalse(view.isAccessibilityElement())
        XCTAssertTrue(view.accessibilityLabel()?.isEmpty ?? true)
    }

    func testDrawingReusesPreparedTextWithoutRelocalizing() throws {
        let drawer = try IllustrationDrawer(directory: resources)
        var calls = 0
        let image = try XCTUnwrap(drawer.image("search-comparison") { _, english in
            calls += 1
            return english
        })
        let preparedCalls = calls
        XCTAssertGreaterThan(preparedCalls, 0)
        let first = try rendered(image).representation(using: .png, properties: [:])
        let second = try rendered(image).representation(using: .png, properties: [:])
        XCTAssertEqual(first, second)
        XCTAssertEqual(calls, preparedCalls)
    }

    func testAppearanceAndDirectionChangeTheRenderedComparison() throws {
        let drawer = try IllustrationDrawer(directory: resources)
        let light = try rendered(XCTUnwrap(drawer.image("search-comparison"))).representation(using: .png, properties: [:])
        let dark = try rendered(XCTUnwrap(drawer.image("search-comparison", dark: true))).representation(using: .png, properties: [:])
        let rtl = try rendered(XCTUnwrap(drawer.image("search-comparison", rightToLeft: true))).representation(using: .png, properties: [:])
        XCTAssertNotEqual(light, dark)
        XCTAssertNotEqual(light, rtl)
    }

    func testImageCacheSeparatesBundleAppearanceDirectionAndOverrides() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Contents/Resources/native-illustrations")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: resources, to: destination)
        let info = ["CFBundleIdentifier": "test.native-illustrations", "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: directory.appendingPathComponent("Contents/Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: directory))
        let original = try XCTUnwrap(LocalizedIllustration.image("settings-app-icons", bundle: bundle))
        XCTAssertTrue(original === LocalizedIllustration.image("settings-app-icons", bundle: bundle))
        XCTAssertFalse(original === LocalizedIllustration.image("settings-app-icons", dark: true, bundle: bundle))
        XCTAssertFalse(original === LocalizedIllustration.image("settings-app-icons", rightToLeft: true, bundle: bundle))
        XCTAssertFalse(original === LocalizedIllustration.image("settings-app-icons", overrides: ["window.japan": "France"], bundle: bundle))
        XCTAssertNil(LocalizedIllustration.image("missing", bundle: bundle))
    }

    func testUnreadableResourceFailsWithoutCreatingAnImage() {
        XCTAssertThrowsError(try IllustrationDrawer(directory: resources.appendingPathComponent("missing")))
    }

    func testEveryIllustrationStringHasATranslationInEverySupportedLanguage() throws {
        let drawer = try IllustrationDrawer(directory: resources)
        let languages = try FileManager.default.contentsOfDirectory(at: resources.deletingLastPathComponent()
            .appendingPathComponent("l10n"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "lproj" }
        XCTAssertEqual(languages.count, 21)
        for language in languages {
            let data = try Data(contentsOf: language.appendingPathComponent("Localizable.strings"))
            let strings = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            for node in drawer.archive.nodes where node.localization != nil {
                let english = try XCTUnwrap(node.text)
                let value = try XCTUnwrap(strings[english], "\(language.lastPathComponent): \(english)")
                XCTAssertFalse(value.isEmpty, english)
                let fitted = IllustrationDrawer.fit(value, size: node.fontSize!, minimum: node.minimumSize,
                    maximum: node.maxWidth, bold: node.bold == true)
                XCTAssertEqual(fitted.text, value, "\(language.lastPathComponent): \(english)")
                if let query = node.highlightQuery {
                    let translatedQuery = try XCTUnwrap(strings[query])
                    XCTAssertNotNil(value.range(of: translatedQuery), "\(language.lastPathComponent): \(value)")
                }
            }
        }
    }

    func testSearchHighlightTracksTranslatedWordOrderAndGlyphBounds() {
        for (title, query) in [("Voyage au Japon", "Japon"), ("日本旅行", "日本"), ("رحلة اليابان", "اليابان"), ("טיול ביפן", "יפן")] {
            let text = NSAttributedString(string: title, attributes: [.font: IllustrationDrawer.font(10, bold: true), .kern: 0])
            let line = CTLineCreateWithAttributedString(text)
            let range = (title as NSString).range(of: query)
            let bounds = IllustrationDrawer.highlightBounds(line, range: range)
            XCTAssertFalse(bounds.isEmpty, title)
            let full = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            for rect in bounds {
                XCTAssertGreaterThan(rect.width, 0, title)
                XCTAssertLessThan(rect.width, full.width, title)
                XCTAssertGreaterThanOrEqual(rect.minX, full.minX - 0.01, title)
                XCTAssertLessThanOrEqual(rect.maxX, full.maxX + 0.01, title)
            }
            XCTAssertTrue(IllustrationDrawer.highlightBounds(line, range: NSRange(location: NSNotFound, length: 0)).isEmpty)
        }
    }

    private func rendered(_ image: NSImage) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(image.size.width * 2), pixelsHigh: Int(image.size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
