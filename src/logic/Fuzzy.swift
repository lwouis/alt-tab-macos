import Foundation

struct Fuzzy {
    /// Returns true if `query` is a fuzzy subsequence of `target`.
    /// Matching is case-insensitive and ignores leading/trailing whitespace.
    /// Example: "slk" matches "Slack", "gc" matches "Google Chrome".
    static func matches(_ query: String, in target: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let q = trimmed.lowercased()
        let t = target.lowercased()
        var qi = q.startIndex
        var ti = t.startIndex
        while qi < q.endIndex && ti < t.endIndex {
            if q[qi] == t[ti] {
                qi = q.index(after: qi)
            }
            ti = t.index(after: ti)
        }
        return qi == q.endIndex
    }
}

