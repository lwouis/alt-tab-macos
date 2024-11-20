import XCTest

final class AppearanceUtilsTests: XCTestCase {
    func testComfortableWidth() throws {
        [
            // screen model, width, height, expected width %
            ("11\" Laptop: MacBook Air 11\"", 255.7, 178.6, 0.9),
            ("13\" Laptop: MacBook Air 13\"", 304.1, 197.8, 0.9),
            ("14\" Laptop: MacBook Pro 14\"", 311.0, 221.1, 0.9),
            ("15\" Laptop: MacBook Pro 15\"", 344.4, 233.0, 0.9),
            ("16\" Laptop: MacBook Pro 16\"", 358.4, 245.9, 0.9),
            ("19\" Monitor: Apple Studio Display 19\"", 403, 236, 0.9),
            ("20\" Monitor: Apple Cinema Display 20\"", 440, 268, 0.9),
            ("21\" Monitor: LG 21:9 UltraWide", 470, 290, 0.9),
            ("22\" Monitor: ASUS 22\" Full HD", 485, 290, 0.9),
            ("24\" Monitor: Dell P2419H", 531.3, 298.6, 0.9),
            ("27\" Monitor: LG 27UK850-W", 596.8, 336.4, 0.9),
            ("30\" Monitor: BenQ PD3200U", 657.5, 376.3, 0.9),
            ("32\" Monitor: BenQ EW3270U", 711.5, 398.9, 0.8432888264230499),
            ("34\" UltraWide Monitor: LG 34UC79G-B", 798.5, 336.5, 0.7514088916718847),
            ("32\" TV: Samsung UE32T5300", 715, 406, 0.8391608391608392),
            ("40\" TV: Samsung Q60B", 889, 510, 0.6749156355455568),
            ("43\" TV: LG 43UN7300", 956, 551, 0.6276150627615062),
            ("50\" TV: Samsung TU8000", 1110, 630, 0.5405405405405406),
            ("55\" TV: LG OLED55CXPUA", 1210, 715, 0.49586776859504134),
            ("60\" TV: Vizio 60-inch 4K", 1320, 750, 0.45454545454545453),
        ].forEach { screen in
            let percent = AppearanceUtils.comfortableWidth(screen.1)
            XCTAssertEqual(percent, screen.3)
        }
    }
}
