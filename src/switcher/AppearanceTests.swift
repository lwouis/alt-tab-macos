import XCTest

final class AppearanceTests: XCTestCase {
    func testTitlesWidthAbsorbsSpinnerChangesButStillGrowsAndShrinks() {
        var width = AppearanceTestable.stableTitlesWidth(measured: 500, limit: 1000, previous: nil, tolerance: 32)
        XCTAssertEqual(width, 532)
        for measured in [501.0, 499, 515, 500, 525, 498] {
            width = AppearanceTestable.stableTitlesWidth(measured: measured, limit: 1000, previous: width, tolerance: 32)
            XCTAssertEqual(width, 532)
        }
        width = AppearanceTestable.stableTitlesWidth(measured: 800, limit: 1000, previous: width, tolerance: 32)
        XCTAssertEqual(width, 832)
        width = AppearanceTestable.stableTitlesWidth(measured: 400, limit: 1000, previous: width, tolerance: 32)
        XCTAssertEqual(width, 432)
        XCTAssertEqual(AppearanceTestable.stableTitlesWidth(measured: 990, limit: 1000, previous: width, tolerance: 32), 1000)
        XCTAssertEqual(AppearanceTestable.stableTitlesWidth(measured: 450, limit: 480, previous: 832, tolerance: 32), 480)
        XCTAssertEqual(AppearanceTestable.stableTitlesWidth(measured: 500, limit: 1000, previous: nil, tolerance: 32), 532)
    }

    func testTitlesWidthShrinksWithContentAndRespectsScreenLimit() {
        XCTAssertEqual(AppearanceTestable.fittedTitlesWidth(measured: 900, limit: 1000), 900)
        XCTAssertEqual(AppearanceTestable.fittedTitlesWidth(measured: 410.2, limit: 1000), 411)
        XCTAssertEqual(AppearanceTestable.fittedTitlesWidth(measured: 100, limit: 1000), 300)
        XCTAssertEqual(AppearanceTestable.fittedTitlesWidth(measured: 1400, limit: 1000), 1000)
        XCTAssertEqual(AppearanceTestable.fittedTitlesWidth(measured: 100, limit: 250), 250)
    }

    func testCustomTitlesMinimumStillHonorsScreenLimitAndHysteresis() {
        XCTAssertEqual(AppearanceTestable.fittedTitlesWidth(measured: 100, limit: 1000, minimum: 600), 600)
        XCTAssertEqual(AppearanceTestable.fittedTitlesWidth(measured: 100, limit: 400, minimum: 600), 400)
        XCTAssertEqual(AppearanceTestable.stableTitlesWidth(measured: 100, limit: 1000, previous: 350, tolerance: 32, minimum: 600), 632)
        XCTAssertEqual(AppearanceTestable.stableTitlesWidth(measured: 100, limit: 1000, previous: 632, tolerance: 32, minimum: 240), 272)
    }

    func testAppNameColumnPreservesSessionWidthWithinBounds() {
        XCTAssertEqual(AppearanceTestable.appNameColumnWidth(measured: 220, previous: 100, rowWidth: 1000), 220)
        XCTAssertEqual(AppearanceTestable.appNameColumnWidth(measured: 80, previous: 220, rowWidth: 1000), 220)
        XCTAssertEqual(AppearanceTestable.appNameColumnWidth(measured: 400, previous: 220, rowWidth: 1000), 240)
        XCTAssertEqual(AppearanceTestable.appNameColumnWidth(measured: 400, previous: 220, rowWidth: 600), 150)
    }

    func testIconSeparationUsesBoundaryContrast() {
        let blue = [0.0, 0.35, 0.9]
        let blueLuminance = AppearanceTestable.relativeLuminance(blue)
        XCTAssertTrue(AppearanceTestable.needsIconSeparation([blueLuminance], background: blue))
        XCTAssertFalse(AppearanceTestable.needsIconSeparation([1], background: blue))
        XCTAssertFalse(AppearanceTestable.needsIconSeparation([], background: blue))
        XCTAssertFalse(AppearanceTestable.needsIconSeparation([blueLuminance, 1, 1], background: blue))
        XCTAssertTrue(AppearanceTestable.needsIconSeparation([1], background: [0.95, 0.95, 0.95]))
    }

    func testIconSamplingSkipsTransparentMarginsAndCentralArtwork() {
        var bytes = [UInt8](repeating: 0, count: 5 * 5 * 4)
        for y in 1...3 {
            for x in 1...3 {
                let offset = (y * 5 + x) * 4
                bytes[offset + 2] = 255
                bytes[offset + 3] = 255
            }
        }
        for component in 0..<3 { bytes[(2 * 5 + 2) * 4 + component] = 255 }
        let samples = AppearanceTestable.iconEdgeLuminances(bytes, side: 5)
        XCTAssertEqual(samples.count, 8)
        XCTAssertTrue(samples.allSatisfy { abs($0 - 0.0722) < 0.0001 })
        XCTAssertEqual(AppearanceTestable.iconEdgeLuminances([], side: 5), [])
    }

    // TODO add 6, 7, 8 rowsCount and reuse vertical screens data from bellow
    func testGoodValuesForThumbnailsWidthMinMax() throws {
        var actual: (CGFloat, CGFloat)
        for (model, (pixelWidth, pixelHeight), _, (expectedHorizontal, _), expectedArray) in screens {
            for (rowCount, expectedMin, expectedMax) in expectedArray {
                actual = AppearanceTestable.goodValuesForThumbnailsWidthMinMax((pixelWidth * expectedHorizontal) / (pixelHeight * 0.8), CGFloat(rowCount))
                XCTAssertEqual(actual.0, expectedMin, accuracy: 0.01, model)
                XCTAssertEqual(actual.1, expectedMax, accuracy: 0.01, model)
            }
        }
    }


    func testComfortableWidth() throws {
        var actual: Double
        for (model, _, (physicalWidth, physicalHeight), (expectedHorizontal, expectedVertical), _) in screens {
            // screen used horizontally
            actual = AppearanceTestable.comfortableWidth(physicalWidth)
            XCTAssertEqual(actual, expectedHorizontal, accuracy: 0.01, model)
            // screen used vertically
            actual = AppearanceTestable.comfortableWidth(physicalHeight)
            XCTAssertEqual(actual, expectedVertical, accuracy: 0.01, model)
        }

    }

    /// Screens that don't report their physical dimensions (`physicalWidth == nil`) get the 0.9
    /// default — the same clamp Windows 11 uses. Without this, ultrawides would fall to 0.45 just
    /// because we lack the data, which is worse than picking a sane default.
    func testComfortableWidthFallsBackToDefaultWhenPhysicalWidthIsNil() throws {
        XCTAssertEqual(AppearanceTestable.comfortableWidth(nil), 0.9)
    }

    /// Portrait-oriented usage (aspectRatio < 1) takes the second formula branch with different
    /// constants. The fixture above is horizontal-only; this pins the portrait path.
    func testGoodValuesForThumbnailsWidthMinMaxPortrait() throws {
        // aspectRatio = 0.5, rowsCount = 4 → minRatio = 1.3/4 = 0.325, maxRatio = 2.1/4 = 0.525
        // Then clamp: lo = max(0.09, 0.325) = 0.325, hi = min(0.30, 0.525) = 0.30
        let (lo, hi) = AppearanceTestable.goodValuesForThumbnailsWidthMinMax(0.5, 4)
        XCTAssertEqual(lo, 0.325, accuracy: 0.001)
        XCTAssertEqual(hi, 0.30, accuracy: 0.001)
        // smaller portrait ratio with more rows → both fall into the clamp zone
        let (lo2, hi2) = AppearanceTestable.goodValuesForThumbnailsWidthMinMax(0.5, 16)
        XCTAssertEqual(lo2, max(0.09, 1.3 / 16), accuracy: 0.001)
        XCTAssertEqual(hi2, min(0.30, 2.1 / 16), accuracy: 0.001)
    }

    private let screens: [(String, (CGFloat, CGFloat), (CGFloat, CGFloat), (CGFloat, CGFloat), [(Int, CGFloat, CGFloat)])] = [
        // screen model, (widthInPixels, heightInPixels), (physicalWidthInMM, physicalHeightInMM), (expectedWidthForHorizontal, expectedWidthForVertical), (rowCount, expectedMinWidth, expectedMaxWidth)
        ("11\" Laptop: MacBook Air 11\": HD", (1366, 768), (255.7, 178.6), (0.90, 0.90), [(3, 0.12, 0.25), (4, 0.09, 0.19), (5, 0.09, 0.15)]),
        ("13\" Laptop: MacBook Air 13\": WXGA+", (1440, 900), (304.1, 197.8), (0.90, 0.90), [(3, 0.13, 0.28), (4, 0.10, 0.21), (5, 0.09, 0.17)]),
        ("14\" Laptop: MacBook Pro 14\": 3K", (3024, 1964), (311.0, 221.1), (0.90, 0.90), [(3, 0.13, 0.29), (4, 0.10, 0.22), (5, 0.09, 0.17)]),
        ("15\" Laptop: MacBook Pro 15\": QXGA", (2880, 1800), (344.4, 233.0), (0.90, 0.90), [(3, 0.13, 0.28), (4, 0.10, 0.21), (5, 0.09, 0.17)]),
        ("16\" Laptop: MacBook Pro 16\": 3.5K", (3456, 2234), (358.4, 245.9), (0.90, 0.90), [(3, 0.13, 0.29), (4, 0.10, 0.22), (5, 0.09, 0.17)]),
        ("19\" Monitor: Apple Studio Display 19\": HD", (1440, 900), (403.0, 236.0), (0.90, 0.90), [(3, 0.13, 0.28), (4, 0.10, 0.21), (5, 0.09, 0.17)]),
        ("20\" Monitor: Apple Cinema Display 20\": WSXGA+", (1680, 1050), (440.0, 268.0), (0.90, 0.90), [(3, 0.13, 0.28), (4, 0.10, 0.21), (5, 0.09, 0.17)]),
        ("21\" Monitor: LG 21:9 UltraWide: UWHD", (2560, 1080), (470.0, 290.0), (0.90, 0.90), [(3, 0.09, 0.19), (4, 0.09, 0.14), (5, 0.09, 0.11)]),
        ("22\" Monitor: ASUS 22\" Full HD: Full HD", (1920, 1080), (485.0, 290.0), (0.90, 0.90), [(3, 0.12, 0.25), (4, 0.09, 0.19), (5, 0.09, 0.15)]),
        ("24\" Monitor: Dell P2419H: Full HD", (1920, 1080), (531.3, 298.6), (0.90, 0.90), [(3, 0.12, 0.25), (4, 0.09, 0.19), (5, 0.09, 0.15)]),
        ("27\" Monitor: LG 27UK850-W: 4K", (3840, 2160), (596.8, 336.4), (0.90, 0.90), [(3, 0.12, 0.25), (4, 0.09, 0.19), (5, 0.09, 0.15)]),
        ("30\" Monitor: BenQ PD3200U: 4K", (3840, 2160), (657.5, 376.3), (0.90, 0.90), [(3, 0.12, 0.25), (4, 0.09, 0.19), (5, 0.09, 0.15)]),
        ("32\" Monitor: BenQ EW3270U: 4K", (3840, 2160), (711.5, 398.9), (0.84, 0.90), [(3, 0.12, 0.27), (4, 0.09, 0.20), (5, 0.09, 0.16)]),
        ("34\" UltraWide Monitor: LG 34UC79G-B: UWHD", (2560, 1080), (798.5, 336.5), (0.75, 0.90), [(3, 0.10, 0.22), (4, 0.09, 0.17), (5, 0.09, 0.14)]),
        ("34\" UltraWide Monitor: LG 34WN80C-B: UWQHD", (3440, 1440), (799.8, 334.8), (0.75, 0.90), [(3, 0.10, 0.22), (4, 0.09, 0.17), (5, 0.09, 0.13)]),
        ("32\" TV: Samsung UE32T5300: Full HD", (1920, 1080), (715.0, 406.0), (0.83, 0.90), [(3, 0.13, 0.27), (4, 0.09, 0.20), (5, 0.09, 0.16)]),
        ("40\" TV: Samsung Q60B: 4K", (3840, 2160), (889.0, 510.0), (0.67, 0.90), [(3, 0.16, 0.30), (4, 0.12, 0.25), (5, 0.09, 0.20)]),
        ("43\" TV: LG 43UN7300: 4K", (3840, 2160), (956.0, 551.0), (0.62, 0.90), [(3, 0.17, 0.30), (4, 0.13, 0.27), (5, 0.10, 0.22)]),
        ("50\" TV: Samsung TU8000: 4K", (3840, 2160), (1110.0, 630.0), (0.54, 0.90), [(3, 0.19, 0.30), (4, 0.15, 0.30), (5, 0.12, 0.25)]),
        ("55\" TV: LG OLED55CXPUA: 4K", (3840, 2160), (1210.0, 715.0), (0.49, 0.83), [(3, 0.21, 0.30), (4, 0.16, 0.30), (5, 0.13, 0.28)]),
        ("60\" TV: Vizio 60-inch 4K: 4K", (3840, 2160), (1320.0, 750.0), (0.45, 0.80), [(3, 0.23, 0.30), (4, 0.17, 0.30), (5, 0.14, 0.30)]),
    ]
}
