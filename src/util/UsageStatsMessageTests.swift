import XCTest

final class UsageStatsTestableMessageTests: XCTestCase {
    func testFormatCount_thousandSeparator() {
        XCTAssertEqual(UsageStatsTestable.formatCount(1), "1")
        XCTAssertEqual(UsageStatsTestable.formatCount(999), "999")
        let formatted1000 = UsageStatsTestable.formatCount(1000)
        XCTAssertTrue(formatted1000.count > 4, "Expected grouping separator in '\(formatted1000)'")
        XCTAssertTrue(formatted1000.contains("1"))
        XCTAssertTrue(formatted1000.contains("000"))
    }
}
