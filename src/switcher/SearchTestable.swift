import Foundation

struct SWOp {
    let op: Character
    let qi: Int
    let tj: Int
}

struct SWResult {
    let score: Int
    let similarity: Double
    let span: Range<Int>
    let subspans: [Range<Int>]
    let ops: [SWOp]
}

struct MatchResult {
    let score: Int
    let tier: Int
    let span: Range<Int>
    let subspans: [Range<Int>]

    func toSWResult() -> SWResult {
        SWResult(score: score, similarity: Double(score) / 1200.0, span: span, subspans: subspans, ops: [])
    }
}

class SearchTestable {
    static let tierExactBase = 1000
    static let tierPrefixBase = 800
    static let tierWordPrefixBase = 600
    static let tierSubstringBase = 400
    static let tierAcronymBase = 200
    static let tierFuzzyBase = 100

    struct Normalized {
        let text: String
        let chars: [Character]
        let toOriginal: [Int]
        let isWordStart: [Bool]      // includes camelCase splits (used by T3 / T5)
        let isHardWordStart: [Bool]  // only non-alphanum boundaries, no camelCase (used by T6)
    }

    static func normalize(_ text: String) -> Normalized {
        let original = Array(text)
        var chars: [Character] = []
        var toOriginal: [Int] = []
        var isWordStart: [Bool] = []
        var isHardWordStart: [Bool] = []
        chars.reserveCapacity(original.count)
        toOriginal.reserveCapacity(original.count)
        isWordStart.reserveCapacity(original.count)
        isHardWordStart.reserveCapacity(original.count)
        for i in 0..<original.count {
            let c = original[i]
            if isWhitespace(c) { continue }
            let folded = String(c).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            let start = computeIsWordStart(original, i)
            let hardStart = computeIsHardWordStart(original, i)
            var first = true
            for fc in folded {
                chars.append(fc)
                toOriginal.append(i)
                isWordStart.append(first ? start : false)
                isHardWordStart.append(first ? hardStart : false)
                first = false
            }
        }
        return Normalized(text: String(chars), chars: chars, toOriginal: toOriginal, isWordStart: isWordStart, isHardWordStart: isHardWordStart)
    }

    static func tierMatch(query: String, text: String) -> MatchResult? {
        let qNorm = normalize(query)
        let tNorm = normalize(text)
        if qNorm.chars.isEmpty || tNorm.chars.isEmpty { return nil }
        let q = qNorm.chars
        let t = tNorm.chars
        let qLen = q.count
        let tLen = t.count
        let words = wordSpans(in: tNorm)
        let queryHasUpper = query.contains(where: { $0.isUppercase })

        // Tier 1: exact
        if qLen == tLen && q == t {
            return makeResult(tierBase: tierExactBase, tier: 1, normSpan: 0..<tLen,
                              subspans: nil, qNorm: qNorm, tNorm: tNorm, query: query, text: text,
                              queryHasUpper: queryHasUpper, words: words, edits: 0)
        }
        // Tier 2: text prefix
        if qLen < tLen && Array(t.prefix(qLen)) == q {
            return makeResult(tierBase: tierPrefixBase, tier: 2, normSpan: 0..<qLen,
                              subspans: nil, qNorm: qNorm, tNorm: tNorm, query: query, text: text,
                              queryHasUpper: queryHasUpper, words: words, edits: 0)
        }
        // Tier 3: word prefix
        for word in words {
            let wLen = word.upperBound - word.lowerBound
            if wLen < qLen { continue }
            if word.lowerBound == 0 { continue } // already tried T2
            var match = true
            for k in 0..<qLen {
                if t[word.lowerBound + k] != q[k] { match = false; break }
            }
            if match {
                let span = word.lowerBound..<(word.lowerBound + qLen)
                return makeResult(tierBase: tierWordPrefixBase, tier: 3, normSpan: span,
                                  subspans: nil, qNorm: qNorm, tNorm: tNorm, query: query, text: text,
                                  queryHasUpper: queryHasUpper, words: words, edits: 0)
            }
        }
        // Tier 4: contiguous substring
        if let span = findSubarray(in: t, sub: q) {
            return makeResult(tierBase: tierSubstringBase, tier: 4, normSpan: span,
                              subspans: nil, qNorm: qNorm, tNorm: tNorm, query: query, text: text,
                              queryHasUpper: queryHasUpper, words: words, edits: 0)
        }
        // Tier 5: acronym (subsequence of word starts)
        if let acronym = matchAcronym(query: q, text: t, words: words) {
            return makeResult(tierBase: tierAcronymBase, tier: 5, normSpan: acronym.span,
                              subspans: acronym.subspans, qNorm: qNorm, tNorm: tNorm, query: query, text: text,
                              queryHasUpper: queryHasUpper, words: words, edits: 0)
        }
        // Tier 6: fuzzy prefix-of-word match (handles typos AND partial-prefix typing)
        // Use whole words (NOT camelCase-split) so e.g. "gthub" matches "GitHub" as one fuzzy unit.
        if qLen >= 3 {
            let maxEdits = qLen <= 9 ? 1 : 2
            var best: MatchResult? = nil
            let fuzzyWords = wholeWordSpans(in: tNorm)
            for word in fuzzyWords {
                let wLen = word.upperBound - word.lowerBound
                let mLo = max(1, qLen - maxEdits)
                let mHi = min(wLen, qLen + maxEdits)
                if mLo > mHi { continue }
                let wordChars = Array(t[word.lowerBound..<word.upperBound])
                for m in mLo...mHi {
                    let prefix = m == wLen ? wordChars : Array(wordChars[0..<m])
                    guard let dist = damerauLevenshtein(q, prefix, k: maxEdits) else { continue }
                    let unmatched = wLen - m
                    let partialPenalty = min(30, 5 * unmatched)
                    let baseScore = tierFuzzyBase - 25 * dist - partialPenalty
                    let span = word.lowerBound..<(word.lowerBound + m)
                    let candidate = makeResult(tierBase: baseScore, tier: 6, normSpan: span,
                                               subspans: nil, qNorm: qNorm, tNorm: tNorm, query: query, text: text,
                                               queryHasUpper: queryHasUpper, words: words, edits: dist)
                    if best == nil || candidate.score > best!.score {
                        best = candidate
                    }
                }
            }
            if let result = best { return result }
        }
        return nil
    }

    private static func makeResult(tierBase: Int, tier: Int, normSpan: Range<Int>,
                                   subspans: [Range<Int>]?, qNorm: Normalized, tNorm: Normalized,
                                   query: String, text: String, queryHasUpper: Bool,
                                   words: [Range<Int>], edits: Int) -> MatchResult {
        let bonus = computeBonuses(normSpan: normSpan, tier: tier, qNorm: qNorm, tNorm: tNorm,
                                   query: query, text: text, queryHasUpper: queryHasUpper, words: words)
        let nextTierBase: Int
        switch tier {
        case 1: nextTierBase = tierBase + 1000
        case 2: nextTierBase = tierExactBase
        case 3: nextTierBase = tierPrefixBase
        case 4: nextTierBase = tierWordPrefixBase
        case 5: nextTierBase = tierSubstringBase
        case 6: nextTierBase = tierAcronymBase
        default: nextTierBase = tierBase + 100
        }
        let cap = nextTierBase - 1
        let score = min(tierBase + bonus, cap)
        let originalSpan = mapSpan(normSpan, tNorm)
        let originalSubspans: [Range<Int>]
        if let subs = subspans {
            originalSubspans = subs.compactMap { mapSpan($0, tNorm) }
        } else {
            originalSubspans = originalSpan.map { [$0] } ?? []
        }
        return MatchResult(score: score, tier: tier,
                           span: originalSpan ?? (0..<0),
                           subspans: originalSubspans)
    }

    private static func computeBonuses(normSpan: Range<Int>, tier: Int,
                                       qNorm: Normalized, tNorm: Normalized,
                                       query: String, text: String, queryHasUpper: Bool,
                                       words: [Range<Int>]) -> Int {
        var bonus = 0
        let startIdx = normSpan.lowerBound
        // Position bonus
        bonus += max(0, 60 - startIdx)
        // Word boundary at start
        let isStartAtBoundary = startIdx == 0 || (startIdx < tNorm.isWordStart.count && tNorm.isWordStart[startIdx])
        if isStartAtBoundary { bonus += 15 }
        // Whole-word bonus (only for contiguous tiers 1-4)
        if tier >= 1 && tier <= 4 {
            let endIdx = normSpan.upperBound
            let isEndAtBoundary: Bool
            if endIdx >= tNorm.chars.count {
                isEndAtBoundary = true
            } else if !isAlphaNum(tNorm.chars[endIdx]) {
                isEndAtBoundary = true
            } else if tNorm.isWordStart[endIdx] {
                isEndAtBoundary = true
            } else {
                isEndAtBoundary = false
            }
            if isStartAtBoundary && isEndAtBoundary { bonus += 10 }
        }
        // Length-ratio bonus
        let qLen = qNorm.chars.count
        let tLen = tNorm.chars.count
        if tLen > 0 {
            let ratio = Int((Double(30 * qLen) / Double(tLen)).rounded())
            bonus += min(30, max(0, ratio))
        }
        // Case-exact bonus (only when query has uppercase, only for tiers 1-5)
        if queryHasUpper && tier >= 1 && tier <= 5 {
            let caseExact = countCaseExactMatches(normSpan: normSpan, tier: tier,
                                                   qNorm: qNorm, tNorm: tNorm,
                                                   query: query, text: text, words: words)
            bonus += min(30, 5 * caseExact)
        }
        return bonus
    }

    private static func countCaseExactMatches(normSpan: Range<Int>, tier: Int,
                                              qNorm: Normalized, tNorm: Normalized,
                                              query: String, text: String,
                                              words: [Range<Int>]) -> Int {
        let originalQuery = Array(query)
        let originalText = Array(text)
        var count = 0
        if tier == 5 {
            // Acronym: each subspan is one char from one word; match query[i] vs text at that position
            // For acronym, we know the matching follows word starts in order.
            var qi = 0
            for word in words {
                if qi >= qNorm.chars.count { break }
                if word.lowerBound >= tNorm.chars.count { continue }
                if tNorm.chars[word.lowerBound] == qNorm.chars[qi] {
                    let qOrig = qNorm.toOriginal[qi]
                    let tOrig = tNorm.toOriginal[word.lowerBound]
                    if qOrig < originalQuery.count && tOrig < originalText.count
                        && originalQuery[qOrig] == originalText[tOrig] {
                        count += 1
                    }
                    qi += 1
                }
            }
            return count
        }
        // Tiers 1-4: contiguous, qLen == normSpan.count
        var seenQOrig = Set<Int>()
        let qLen = qNorm.chars.count
        for k in 0..<qLen {
            let nIdx = normSpan.lowerBound + k
            if nIdx >= tNorm.toOriginal.count { break }
            if k >= qNorm.toOriginal.count { break }
            let qOrig = qNorm.toOriginal[k]
            let tOrig = tNorm.toOriginal[nIdx]
            if seenQOrig.contains(qOrig) { continue }
            seenQOrig.insert(qOrig)
            if qOrig < originalQuery.count && tOrig < originalText.count
                && originalQuery[qOrig] == originalText[tOrig] {
                count += 1
            }
        }
        return count
    }

    /// Whole-word spans — split only on non-alphanumeric chars in the ORIGINAL text
    /// (whitespace, punctuation, emoji), NOT on camelCase boundaries. Used by T6 fuzzy
    /// matching so e.g. "gthub" can match "GitHub" as one fuzzy unit, while "Tokyo Shinkansen"
    /// is still split into two words.
    static func wholeWordSpans(in normalized: Normalized) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        var start: Int? = nil
        for i in 0..<normalized.chars.count {
            let isAlpha = isAlphaNum(normalized.chars[i])
            if normalized.isHardWordStart[i] {
                if let s = start { spans.append(s..<i) }
                start = i
            } else if !isAlpha {
                if let s = start { spans.append(s..<i); start = nil }
            }
        }
        if let s = start { spans.append(s..<normalized.chars.count) }
        return spans
    }

    static func wordSpans(in normalized: Normalized) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        var start: Int? = nil
        for i in 0..<normalized.chars.count {
            let isAlpha = isAlphaNum(normalized.chars[i])
            if normalized.isWordStart[i] {
                if let s = start { spans.append(s..<i) }
                start = i
            } else if !isAlpha {
                if let s = start { spans.append(s..<i); start = nil }
            }
        }
        if let s = start { spans.append(s..<normalized.chars.count) }
        return spans
    }

    private static func matchAcronym(query: [Character], text: [Character], words: [Range<Int>]) -> (span: Range<Int>, subspans: [Range<Int>])? {
        if query.isEmpty || words.isEmpty { return nil }
        var qi = 0
        var matches: [Int] = []
        for word in words {
            if qi >= query.count { break }
            if word.lowerBound >= text.count { continue }
            if text[word.lowerBound] == query[qi] {
                matches.append(word.lowerBound)
                qi += 1
            }
        }
        guard qi == query.count else { return nil }
        let firstStart = matches.first!
        let lastEnd = matches.last! + 1
        let subspans = matches.map { $0..<($0 + 1) }
        return (firstStart..<lastEnd, subspans)
    }

    static func damerauLevenshtein(_ a: [Character], _ b: [Character], k: Int) -> Int? {
        let n = a.count, m = b.count
        if abs(n - m) > k { return nil }
        let inf = Int.max / 2
        var dp = Array(repeating: Array(repeating: inf, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        for i in 1...n {
            let lo = max(1, i - k)
            let hi = min(m, i + k)
            if lo > hi { continue }
            var rowMin = inf
            for j in lo...hi {
                let costSub = a[i - 1] == b[j - 1] ? 0 : 1
                var v = dp[i - 1][j - 1] + costSub
                if dp[i - 1][j] != inf { v = min(v, dp[i - 1][j] + 1) }
                if dp[i][j - 1] != inf { v = min(v, dp[i][j - 1] + 1) }
                if i >= 2 && j >= 2 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                    if dp[i - 2][j - 2] != inf { v = min(v, dp[i - 2][j - 2] + 1) }
                }
                dp[i][j] = v
                if v < rowMin { rowMin = v }
            }
            if rowMin > k { return nil }
        }
        let result = dp[n][m]
        return result <= k ? result : nil
    }

    private static func findSubarray(in haystack: [Character], sub: [Character]) -> Range<Int>? {
        let n = haystack.count, m = sub.count
        if m == 0 || n < m { return nil }
        for i in 0...(n - m) {
            var ok = true
            for j in 0..<m {
                if haystack[i + j] != sub[j] { ok = false; break }
            }
            if ok { return i..<(i + m) }
        }
        return nil
    }

    private static func mapSpan(_ normSpan: Range<Int>, _ tNorm: Normalized) -> Range<Int>? {
        if normSpan.isEmpty { return nil }
        guard normSpan.lowerBound >= 0, normSpan.upperBound <= tNorm.toOriginal.count else { return nil }
        let start = tNorm.toOriginal[normSpan.lowerBound]
        let end = tNorm.toOriginal[normSpan.upperBound - 1] + 1
        return start..<end
    }

    private static func computeIsWordStart(_ chars: [Character], _ idx: Int) -> Bool {
        let c = chars[idx]
        if !isAlphaNum(c) { return false }
        if idx == 0 { return true }
        let prev = chars[idx - 1]
        if !isAlphaNum(prev) { return true }
        if isLower(prev) && isUpper(c) { return true }
        return false
    }

    private static func computeIsHardWordStart(_ chars: [Character], _ idx: Int) -> Bool {
        let c = chars[idx]
        if !isAlphaNum(c) { return false }
        if idx == 0 { return true }
        let prev = chars[idx - 1]
        if !isAlphaNum(prev) { return true }
        return false
    }

    static func combinedScore(query: String, appName: String, title: String) -> Double {
        let appResult = tierMatch(query: query, text: appName)
        let titleResult = tierMatch(query: query, text: title)
        return max(Double(appResult?.score ?? 0) * 1.02, Double(titleResult?.score ?? 0))
    }

    static func acronymBonus(query: String, text: String) -> Double {
        let qNorm = normalize(query)
        let tNorm = normalize(text)
        if qNorm.chars.isEmpty || tNorm.chars.isEmpty { return 0 }
        if tNorm.chars.starts(with: qNorm.chars) {
            return 6.0 + min(2.0, Double(qNorm.chars.count) * 0.25)
        }
        let words = wordSpans(in: tNorm)
        if words.isEmpty { return 0 }
        let starts = words.map { tNorm.chars[$0.lowerBound] }
        var qi = 0
        var firstMatch: Int?
        for (i, c) in starts.enumerated() {
            if qi >= qNorm.chars.count { break }
            if c == qNorm.chars[qi] {
                if firstMatch == nil { firstMatch = i }
                qi += 1
            }
        }
        guard qi == qNorm.chars.count else { return 0 }
        let pos = firstMatch ?? 0
        return 4.0 + min(2.0, Double(qNorm.chars.count) * 0.2) + (pos == 0 ? 1.0 : max(0.0, 0.6 - Double(pos) * 0.15))
    }

    static func isAlphaNum(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) } }
    static func isLower(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { CharacterSet.lowercaseLetters.contains($0) } }
    static func isUpper(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { CharacterSet.uppercaseLetters.contains($0) } }
    static func isWhitespace(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) } }
}
