import XCTest

final class SearchAcronymTests: XCTestCase {
    func testAcronymBonusPrefixMatch() throws {
        XCTAssertGreaterThan(SearchTestable.acronymBonus(query: "chr", text: "Chrome"), 0)
        XCTAssertEqual(SearchTestable.acronymBonus(query: "chr", text: "My Chrome"), 0)
    }

    func testAcronymBonusWordStarts() throws {
        XCTAssertGreaterThan(SearchTestable.acronymBonus(query: "cd", text: "Chrome DevTools"), 0)
        XCTAssertEqual(SearchTestable.acronymBonus(query: "cd", text: "Chrome"), 0)
    }

    func testAcronymBonusPrefersEarlierMatch() throws {
        let early = SearchTestable.acronymBonus(query: "cd", text: "Chrome DevTools")
        let later = SearchTestable.acronymBonus(query: "cd", text: "Google Chrome DevTools")
        XCTAssertGreaterThan(early, later)
    }

    func testAcronymBonusIgnoresSpacesInQuery() throws {
        let compact = SearchTestable.acronymBonus(query: "cd", text: "Chrome DevTools")
        let spaced = SearchTestable.acronymBonus(query: " c d ", text: "Chrome DevTools")
        XCTAssertEqual(compact, spaced)
    }
}
