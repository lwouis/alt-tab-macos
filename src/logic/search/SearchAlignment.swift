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

func smithWatermanHighlights(query: String,
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
            let sDiag = H[i-1][j-1] + (qArr[i-1] == tArr[j-1] ? match : mismatch)
            let sUp   = H[i-1][j] + gap
            let sLeft = H[i][j-1] + gap
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
    candidates.sort { (a, b) in a.score > b.score }

    var results: [SWResult] = []
    var usedSpans: [Range<Int>] = []

    func rangesOverlap(_ a: Range<Int>, _ b: Range<Int>) -> Bool {
        return a.lowerBound < b.upperBound && b.lowerBound < a.upperBound
    }

    func backtrack(_ iStart: Int, _ jStart: Int) -> (ops: [SWOp], span: Range<Int>, subspans: [Range<Int>], score: Int) {
        var opsRev: [SWOp] = []
        var consumedJ: [Int] = []
        var i = iStart
        var j = jStart
        while i > 0 && j > 0 && H[i][j] > 0 {
            let p = bt[i][j]
            if p == "D" {
                opsRev.append(SWOp(op: qArr[i-1] == tArr[j-1] ? "M" : "S", qi: i-1, tj: j-1))
                consumedJ.append(j-1)
                i -= 1; j -= 1
            } else if p == "U" {
                opsRev.append(SWOp(op: "D", qi: i-1, tj: j))
                i -= 1
            } else if p == "L" {
                opsRev.append(SWOp(op: "I", qi: i, tj: j-1))
                consumedJ.append(j-1)
                j -= 1
            } else {
                break
            }
        }
        let ops = opsRev.reversed()
        let jStartIdx = consumedJ.min() ?? jStart
        let jEndIdx = (consumedJ.max() ?? (jStart-1)) + 1
        let span = jStartIdx..<jEndIdx
        var subs: [Range<Int>] = []
        var runStart: Int? = nil
        var jCursor = jStartIdx
        for op in ops {
            switch op.op {
            case "M":
                if runStart == nil { runStart = jCursor }
                jCursor += 1
            case "S":
                if let rs = runStart { subs.append(rs..<jCursor); runStart = nil }
                jCursor += 1
            case "I":
                if let rs = runStart { subs.append(rs..<jCursor); runStart = nil }
                jCursor += 1
            case "D":
                if let rs = runStart { subs.append(rs..<jCursor); runStart = nil }
            default:
                break
            }
        }
        if let rs = runStart { subs.append(rs..<jCursor) }
        return (Array(ops), span, subs, H[iStart][jStart])
    }

    for (score, i, j) in candidates {
        if results.count >= topK { break }
        if score < minScore { break }
        let res = backtrack(i, j)
        if !allowOverlaps && usedSpans.contains(where: { rangesOverlap($0, res.span) }) { continue }
        let sim = Double(res.score) / Double(max(1, match * n))
        results.append(SWResult(score: res.score, similarity: sim, span: res.span, subspans: res.subspans, ops: res.ops))
        usedSpans.append(res.span)
    }
    return results
}

func smithWatermanSimilarity(query: String, text: String) -> Double {
    return smithWatermanHighlights(query: query, text: text, topK: 1).first?.similarity ?? 0.0
}

