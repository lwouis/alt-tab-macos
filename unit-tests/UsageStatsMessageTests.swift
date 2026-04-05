import XCTest

final class UsageStatsTestableMessageTests: XCTestCase {
    private func count(triggers: [Int] = [], appIcons: [Int] = [], titles: [Int] = [],
                       extraShortcuts: [Int] = [], searches: [Int] = []) -> Int {
        UsageStatsTestable.proFeatureSessionCount(
            triggers: triggers, appIcons: appIcons, titles: titles,
            extraShortcuts: extraShortcuts, searches: searches)
    }

    func testEmpty_returnsZero() {
        XCTAssertEqual(count(), 0)
    }

    func testTriggersOnlyNoFeatures_returnsZero() {
        XCTAssertEqual(count(triggers: [100, 200, 300]), 0)
    }

    func testAppIconsAndSearchInSameSession_countsOne() {
        XCTAssertEqual(count(triggers: [100], appIcons: [100], searches: [105]), 1)
    }

    func testCycleHeavySession_collapsesToOne() {
        XCTAssertEqual(count(triggers: [100, 100, 100, 100, 100], appIcons: [100, 100, 100, 100, 100]), 1)
    }

    func testTwoDistinctSessionsWithDifferentFeatures() {
        XCTAssertEqual(count(triggers: [100, 200], appIcons: [100], titles: [200]), 2)
    }

    func testSearchesMappedBackToOwningTriggers() {
        XCTAssertEqual(count(triggers: [100, 200], searches: [150, 250]), 2)
    }

    func testSpuriousFeatureTimestamp_intersectedAway() {
        XCTAssertEqual(count(triggers: [100], appIcons: [999]), 0)
    }

    func testSearchBeforeAnyTrigger_skipped() {
        XCTAssertEqual(count(triggers: [100], searches: [50]), 0)
    }

    func testSessionCountNeverExceedsTriggerCount() {
        let triggers = [100, 100, 200]
        let result = count(triggers: triggers, appIcons: [100, 100], titles: [200], searches: [105, 205])
        XCTAssertLessThanOrEqual(result, triggers.count)
        XCTAssertEqual(result, 2)
    }

    func testFormatCount_thousandSeparator() {
        XCTAssertEqual(UsageStatsTestable.formatCount(1), "1")
        XCTAssertEqual(UsageStatsTestable.formatCount(999), "999")
        let formatted1000 = UsageStatsTestable.formatCount(1000)
        XCTAssertTrue(formatted1000.count > 4, "Expected grouping separator in '\(formatted1000)'")
        XCTAssertTrue(formatted1000.contains("1"))
        XCTAssertTrue(formatted1000.contains("000"))
    }
}
