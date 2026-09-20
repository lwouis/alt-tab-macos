import XCTest

class TabReadPolicyTests: XCTestCase {
    func testTabChildrenContinueBeyondTheFirst128Entries() {
        var offsets = [Int]()
        var titles = [String]()
        let result = AxChildrenTraversal.walk(pageSize: 128, mayRead: { true }, count: { 300 }, page: { offset, amount in
            offsets.append(offset)
            return (offset..<(offset + amount)).map { "tab-\($0)" }
        }, visit: { title in
            titles.append(title)
            return false
        })
        XCTAssertEqual(result, .complete)
        XCTAssertEqual(offsets, [0, 128, 256])
        XCTAssertEqual(titles, (0..<300).map { "tab-\($0)" })
    }

    func testTabGroupCanBeFoundBeyondTheFirst64DirectChildren() {
        var visited = [Int]()
        let result = AxChildrenTraversal.walk(pageSize: 64, mayRead: { true }, count: { 140 }, page: { offset, amount in
            Array(offset..<(offset + amount))
        }, visit: { child in
            visited.append(child)
            return child == 130
        })
        XCTAssertEqual(result, .stopped)
        XCTAssertEqual(visited, Array(0...130))
    }

    func testExpiredBudgetDoesNotStartAnotherPageOrPublishAPartialRead() {
        var remaining = 130
        var offsets = [Int]()
        let result = AxChildrenTraversal.walk(pageSize: 128, mayRead: { remaining > 0 }, count: { 300 }, page: { offset, amount in
            offsets.append(offset)
            return Array(offset..<(offset + amount))
        }, visit: { _ in
            remaining -= 1
            return false
        })
        XCTAssertEqual(result, .unknown)
        XCTAssertEqual(offsets, [0, 128])
        XCTAssertEqual(remaining, 0)
    }

    func testChildCountReadThatExhaustsTheBudgetDoesNotStartAPage() {
        var mayRead = true
        let result = AxChildrenTraversal.walk(pageSize: 64, mayRead: { mayRead }, count: {
            mayRead = false
            return 100
        }, page: { _, _ -> [Int]? in
            XCTFail("The count IPC exhausted this traversal's budget")
            return nil
        }, visit: { _ in false })
        XCTAssertEqual(result, .unknown)
    }

    func testTruncatedOrFailedLaterPageIsUnknown() {
        for partial in [Optional([128]), nil] {
            let result = AxChildrenTraversal.walk(pageSize: 128, mayRead: { true }, count: { 130 }, page: { offset, amount in
                offset == 0 ? Array(0..<amount) : partial
            }, visit: { _ in false })
            XCTAssertEqual(result, .unknown)
        }
    }

    func testChildCountChangingBetweenPagesIsUnknown() {
        var count = 130
        let result = AxChildrenTraversal.walk(pageSize: 128, mayRead: { true }, count: { count }, page: { offset, amount in
            Array(offset..<(offset + amount))
        }, visit: { child in
            if child == 129 { count += 1 }
            return false
        })
        XCTAssertEqual(result, .unknown)
    }

    func testFailedChildInspectionIsUnknown() {
        let result = AxChildrenTraversal.walk(pageSize: 128, mayRead: { true }, count: { 130 }, page: { offset, amount in
            Array(offset..<(offset + amount))
        }, visit: { $0 == 129 ? nil : false })
        XCTAssertEqual(result, .unknown)
    }

    private func candidate(_ wid: CGWindowID, _ capability: AppTabCapability = .neverSeenTabGroup,
                           changed: Bool = false, lastRead: UInt64? = 10) -> TabReadCandidate {
        TabReadCandidate(wid: wid, capability: capability, appWindowsChangedSinceLastRead: changed,
            lastReadGeneration: lastRead)
    }

    // MARK: - A. Always read (rules 1-3)

    /// a window whose tabs were never read is always read
    func testNeverReadIsRead() {
        let read = TabReadPolicy.windowsToRead([candidate(1, lastRead: nil)])
        XCTAssertEqual(read, [1])
    }

    /// a window of an app we have learned nothing about yet is always read
    func testUnknownCapabilityIsRead() {
        let read = TabReadPolicy.windowsToRead([candidate(1, .unknown)])
        XCTAssertEqual(read, [1])
    }

    /// the app gained or lost a window since this window's last read, so its grouping may be stale
    func testStructuralChangeIsRead() {
        let read = TabReadPolicy.windowsToRead([candidate(1, .seenTabGroup, changed: true)])
        XCTAssertEqual(read, [1])
    }

    // MARK: - B. Settled windows are skipped

    /// a settled window of an app that has never shown tabs is skipped once the backstop budget is spent
    func testSettledNonTabbingWindowIsSkipped() {
        let candidates = (1...10).map { candidate(CGWindowID($0), .neverSeenTabGroup, lastRead: UInt64(100 + $0)) }
        let read = TabReadPolicy.windowsToRead(candidates)
        XCTAssertFalse(read.contains(10))
    }

    /// the same for a tabbing app: capability alone never forces a read, which is what makes Finder and
    /// Terminal cheap
    func testSettledTabbingWindowIsSkipped() {
        let candidates = (1...10).map { candidate(CGWindowID($0), .seenTabGroup, lastRead: UInt64(100 + $0)) }
        let read = TabReadPolicy.windowsToRead(candidates)
        XCTAssertFalse(read.contains(10))
    }

    // MARK: - C. The rolling backstop

    /// exactly `backstopReadsPerPass` windows are re-read, stalest first
    func testBackstopReadsTheStalestOnly() {
        let candidates = (1...12).map { candidate(CGWindowID($0), lastRead: UInt64($0)) }
        let read = TabReadPolicy.windowsToRead(candidates)
        XCTAssertEqual(read.count, TabReadPolicy.backstopReadsPerPass)
        XCTAssertEqual(read, [1, 2, 3, 4, 5])
    }

    /// among equally stale windows, the ones whose app actually has tabs are re-checked first, so a missed
    /// notification is noticed sooner where tabs exist
    func testBackstopPrefersTabbingApps() {
        var candidates = (1...5).map { candidate(CGWindowID($0), .neverSeenTabGroup, lastRead: 50) }
        candidates += (6...10).map { candidate(CGWindowID($0), .seenTabGroup, lastRead: 50) }
        let read = TabReadPolicy.windowsToRead(candidates)
        XCTAssertEqual(read, [6, 7, 8, 9, 10])
    }

    /// fewer settled windows than the budget means all of them are re-read
    func testBackstopBudgetLargerThanCandidateSet() {
        let candidates = (1...3).map { candidate(CGWindowID($0), lastRead: UInt64($0)) }
        let read = TabReadPolicy.windowsToRead(candidates)
        XCTAssertEqual(read, [1, 2, 3])
    }

    // MARK: - D. Edges

    /// no candidates, nothing read
    func testEmptyInput() {
        XCTAssertEqual(TabReadPolicy.windowsToRead([]), [])
    }

    /// when every window already qualifies under rules 1-3, the backstop has nothing left to add
    func testAllQualifyingNeedsNoBackstop() {
        let candidates = (1...12).map { candidate(CGWindowID($0), .seenTabGroup, changed: true) }
        let read = TabReadPolicy.windowsToRead(candidates)
        XCTAssertEqual(read.count, 12)
    }
}
