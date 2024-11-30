import XCTest

final class AppearanceTests: XCTestCase {
    let screens: [(String, (CGFloat, CGFloat), (CGFloat, CGFloat), (CGFloat, CGFloat), [(Int, CGFloat, CGFloat)])] = [
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
}
