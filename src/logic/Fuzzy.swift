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

    /// Returns the indices in `target` that match `query` using subsequence matching.
    /// Matching is case-insensitive and ignores leading/trailing whitespace.
    /// Returns an empty array if `query` is empty, or `nil` if there is no match.
    static func matchIndices(_ query: String, in target: String) -> [Int]? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let qLower = trimmed.lowercased()
        let tLower = target.lowercased()
        var qi = qLower.startIndex
        var ti = tLower.startIndex
        var indices = [Int]()
        while qi < qLower.endIndex && ti < tLower.endIndex {
            if qLower[qi] == tLower[ti] {
                let dist = tLower.distance(from: tLower.startIndex, to: ti)
                indices.append(dist)
                qi = qLower.index(after: qi)
            }
            ti = tLower.index(after: ti)
        }
        return qi == qLower.endIndex ? indices : nil
    }
}
