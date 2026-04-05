import Foundation

class UsageStatsTestable {
    private static let proFeatureKeys: [(key: String, name: String)] = [
        ("searches", NSLocalizedString("Search", comment: "")),
        ("triggersAppIcons", NSLocalizedString("App Icons appearance", comment: "")),
        ("triggersTitles", NSLocalizedString("Titles appearance", comment: "")),
        ("triggersExtraShortcuts", NSLocalizedString("Extra shortcuts", comment: "")),
    ]

    static func proFeatureNames() -> [(key: String, name: String)] { proFeatureKeys }

    /// Trigger-time features share the trigger timestamp by construction (same `recordTrigger` call).
    /// Searches happen later in the session, so map each back to the latest trigger ≤ search ts.
    /// Final intersect clamps the result to actual triggers — guarantees column 2 ≤ column 1.
    static func proFeatureSessionCount(triggers: [Int], appIcons: [Int], titles: [Int],
                                       extraShortcuts: [Int], searches: [Int]) -> Int {
        guard !triggers.isEmpty else { return 0 }
        var sessions = Set<Int>()
        sessions.formUnion(appIcons)
        sessions.formUnion(titles)
        sessions.formUnion(extraShortcuts)
        let sortedTriggers = triggers.sorted()
        for s in searches {
            if let owning = mostRecentTrigger(in: sortedTriggers, atOrBefore: s) {
                sessions.insert(owning)
            }
        }
        sessions.formIntersection(triggers)
        return sessions.count
    }

    private static func mostRecentTrigger(in sorted: [Int], atOrBefore target: Int) -> Int? {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let m = (lo + hi) / 2
            if sorted[m] <= target { lo = m + 1 } else { hi = m }
        }
        return lo > 0 ? sorted[lo - 1] : nil
    }

    static func formatCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}
