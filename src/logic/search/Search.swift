import Foundation

final class Search {
    static func normalizedQuery(_ query: String) -> String {
        normalizeForSpaceInsensitiveSearch(query).text
    }

    static func matches(_ window: Window, query: String) -> Bool {
        let normalized = normalizedQuery(query)
        if normalized.isEmpty { return true }
        ensureCache(for: window, normalizedQuery: normalized)
        return !window.swAppResults.isEmpty || !window.swTitleResults.isEmpty
    }

    static func relevance(for window: Window, query: String) -> Double {
        let normalized = normalizedQuery(query)
        if normalized.isEmpty { return 0.0 }
        ensureCache(for: window, normalizedQuery: normalized)
        return window.swBestSimilarity
    }

    private static func ensureCache(for window: Window, normalizedQuery normalized: String) {
        let cacheKey = normalized + "|2"
        if window.lastSearchQuery == cacheKey { return }
        if normalized.isEmpty {
            window.lastSearchQuery = cacheKey
            window.swAppResults = []
            window.swTitleResults = []
            window.swBestSimilarity = 0
            return
        }
        let appName = window.application.localizedName ?? ""
        let title = window.title ?? ""
        let topK = 3
        let appResList = smithWatermanHighlightsIgnoringSpaces(query: normalized, text: appName, topK: topK, allowOverlaps: false)
        let titleResList = smithWatermanHighlightsIgnoringSpaces(query: normalized, text: title, topK: topK, allowOverlaps: false)
        window.swAppResults = appResList
        window.swTitleResults = titleResList
        let nameSim = appResList.first?.similarity ?? 0.0
        let titleSim = titleResList.first?.similarity ?? 0.0
        var similarity = max(nameSim * 1.02, titleSim)
        similarity += max(SearchTestable.acronymBonus(query: normalized, text: appName), SearchTestable.acronymBonus(query: normalized, text: title))
        window.swBestSimilarity = similarity
        window.lastSearchQuery = cacheKey
    }

    static func smithWatermanHighlightsIgnoringSpaces(query: String, text: String, topK: Int = 1, allowOverlaps: Bool = false) -> [SWResult] {
        let normalized = normalizedQuery(query)
        if normalized.isEmpty { return [] }
        let normalizedText = normalizeForSpaceInsensitiveSearch(text)
        if normalizedText.text.isEmpty { return [] }
        let normalizedResults = smithWatermanHighlights(query: normalized, text: normalizedText.text, topK: topK, allowOverlaps: allowOverlaps)
        return normalizedResults.compactMap { mapNormalizedResultToOriginal($0, normalizedText.normalizedToOriginal) }
    }

    private static func normalizeForSpaceInsensitiveSearch(_ text: String) -> (text: String, normalizedToOriginal: [Int]) {
        let chars = Array(text)
        var normalizedChars = [Character]()
        var normalizedToOriginal = [Int]()
        normalizedChars.reserveCapacity(chars.count)
        normalizedToOriginal.reserveCapacity(chars.count)
        for (idx, c) in chars.enumerated() {
            if c.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) { continue }
            normalizedChars.append(c)
            normalizedToOriginal.append(idx)
        }
        return (String(normalizedChars), normalizedToOriginal)
    }

    private static func mapNormalizedResultToOriginal(_ result: SWResult, _ normalizedToOriginal: [Int]) -> SWResult? {
        guard let span = mapNormalizedRangeToOriginal(result.span, normalizedToOriginal) else { return nil }
        let subspans = result.subspans.compactMap { mapNormalizedRangeToOriginal($0, normalizedToOriginal) }
        let ops = result.ops.compactMap { mapNormalizedOpToOriginal($0, normalizedToOriginal) }
        return SWResult(score: result.score, similarity: result.similarity, span: span, subspans: subspans, ops: ops)
    }

    private static func mapNormalizedRangeToOriginal(_ range: Range<Int>, _ normalizedToOriginal: [Int]) -> Range<Int>? {
        if range.isEmpty { return nil }
        guard range.lowerBound >= 0, range.upperBound <= normalizedToOriginal.count else { return nil }
        let start = normalizedToOriginal[range.lowerBound]
        let end = normalizedToOriginal[range.upperBound - 1] + 1
        return start..<end
    }

    private static func mapNormalizedOpToOriginal(_ op: SWOp, _ normalizedToOriginal: [Int]) -> SWOp? {
        if op.op == "D" {
            if normalizedToOriginal.isEmpty { return SWOp(op: op.op, qi: op.qi, tj: 0) }
            if op.tj <= 0 { return SWOp(op: op.op, qi: op.qi, tj: normalizedToOriginal[0]) }
            if op.tj >= normalizedToOriginal.count { return SWOp(op: op.op, qi: op.qi, tj: normalizedToOriginal[normalizedToOriginal.count - 1] + 1) }
            return SWOp(op: op.op, qi: op.qi, tj: normalizedToOriginal[op.tj])
        }
        guard op.tj >= 0, op.tj < normalizedToOriginal.count else { return nil }
        return SWOp(op: op.op, qi: op.qi, tj: normalizedToOriginal[op.tj])
    }

    static func smithWatermanHighlights(query: String,
                                 text: String,
                                 match: Int = 2,
                                 mismatch: Int = -1,
                                 gap: Int = -2,
                                 topK: Int = 1,
                                 minScore: Int = 1,
                                 allowOverlaps: Bool = false,
                                 caseInsensitive: Bool = true) -> [SWResult] {
        let qArr = Array(caseInsensitive ? query.lowercased() : query)
        let tArr = Array(caseInsensitive ? text.lowercased() : text)
        let n = qArr.count
        let m = tArr.count
        if n == 0 || m == 0 { return [] }
        var H = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        var bt = Array(repeating: Array(repeating: Character("\0"), count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                let sDiag = H[i - 1][j - 1] + (qArr[i - 1] == tArr[j - 1] ? match : mismatch)
                let sUp = H[i - 1][j] + gap
                let sLeft = H[i][j - 1] + gap
                var val = sDiag
                var ptr: Character = "D"
                if sUp > val { val = sUp; ptr = "U" }
                if sLeft > val { val = sLeft; ptr = "L" }
                if val < 0 { val = 0; ptr = "\0" }
                H[i][j] = val
                bt[i][j] = ptr
            }
        }
        var candidates: [(score: Int, i: Int, j: Int)] = []
        for i in 1...n {
            for j in 1...m {
                let s = H[i][j]
                if s > 0 { candidates.append((s, i, j)) }
            }
        }
        if candidates.isEmpty { return [] }
        candidates.sort { $0.score > $1.score }
        var results: [SWResult] = []
        var usedSpans: [Range<Int>] = []
        func rangesOverlap(_ a: Range<Int>, _ b: Range<Int>) -> Bool { a.lowerBound < b.upperBound && b.lowerBound < a.upperBound }
        func backtrack(_ iStart: Int, _ jStart: Int) -> (ops: [SWOp], span: Range<Int>, subspans: [Range<Int>], score: Int) {
            var opsRev: [SWOp] = []
            var consumedJ: [Int] = []
            var i = iStart
            var j = jStart
            while i > 0 && j > 0 && H[i][j] > 0 {
                let p = bt[i][j]
                if p == "D" {
                    opsRev.append(SWOp(op: qArr[i - 1] == tArr[j - 1] ? "M" : "S", qi: i - 1, tj: j - 1))
                    consumedJ.append(j - 1)
                    i -= 1
                    j -= 1
                } else if p == "U" {
                    opsRev.append(SWOp(op: "D", qi: i - 1, tj: j))
                    i -= 1
                } else if p == "L" {
                    opsRev.append(SWOp(op: "I", qi: i, tj: j - 1))
                    consumedJ.append(j - 1)
                    j -= 1
                } else {
                    break
                }
            }
            let ops = Array(opsRev.reversed())
            let jStartIdx = consumedJ.min() ?? jStart
            let jEndIdx = (consumedJ.max() ?? (jStart - 1)) + 1
            let span = jStartIdx..<jEndIdx
            var subspans: [Range<Int>] = []
            var runStart: Int? = nil
            var jCursor = jStartIdx
            for op in ops {
                switch op.op {
                case "M":
                    if runStart == nil { runStart = jCursor }
                    jCursor += 1
                case "S":
                    if let runStart { subspans.append(runStart..<jCursor) }
                    runStart = nil
                    jCursor += 1
                case "I":
                    if let runStart { subspans.append(runStart..<jCursor) }
                    runStart = nil
                    jCursor += 1
                case "D":
                    if let runStart { subspans.append(runStart..<jCursor) }
                    runStart = nil
                default:
                    break
                }
            }
            if let runStart { subspans.append(runStart..<jCursor) }
            return (ops, span, subspans, H[iStart][jStart])
        }
        for (score, i, j) in candidates {
            if results.count >= topK || score < minScore { break }
            let result = backtrack(i, j)
            if !allowOverlaps && usedSpans.contains(where: { rangesOverlap($0, result.span) }) { continue }
            let similarity = Double(result.score) / Double(max(1, match * n))
            results.append(SWResult(score: result.score, similarity: similarity, span: result.span, subspans: result.subspans, ops: result.ops))
            usedSpans.append(result.span)
        }
        return results
    }

    static func smithWatermanSimilarity(query: String, text: String) -> Double {
        smithWatermanHighlights(query: query, text: text, topK: 1).first?.similarity ?? 0.0
    }
}

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
