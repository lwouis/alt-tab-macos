import Cocoa

fileprivate struct SettingsSearchToken {
    let normalized: [Character]
    let normalizedToOriginal: [Int]
}

struct SettingsSearchResult {
    let score: Double
    let ranges: [Range<Int>]
}

enum SettingsSearch {
    private struct TokenMatch {
        let score: Double
        let ranges: [Range<Int>]
    }

    static func isQueryEmpty(_ query: String) -> Bool {
        tokens(query).flatMap { $0.normalized }.isEmpty
    }

    static func match(_ query: String, in text: String) -> SettingsSearchResult? {
        let mergeAcrossSeparators = hasInterTermSeparator(query)
        let queryTokens = tokens(query).map(\.normalized)
        guard !queryTokens.isEmpty else { return nil }
        let textTokens = tokens(text)
        guard !textTokens.isEmpty else { return nil }
        var tokenScores = [Double]()
        var matchedRanges = [Range<Int>]()
        for queryToken in queryTokens {
            guard let bestMatch = bestMatch(for: queryToken, in: textTokens) else { return nil }
            tokenScores.append(bestMatch.score)
            matchedRanges.append(contentsOf: bestMatch.ranges)
        }
        let averageScore = tokenScores.reduce(0, +) / Double(tokenScores.count)
        guard averageScore >= minimumScore(queryTokens.map { $0.count }.max() ?? 0) else { return nil }
        if mergeAcrossSeparators && matchedRanges.count > 1 {
            return SettingsSearchResult(score: averageScore, ranges: mergeRangesAcrossSeparators(matchedRanges, in: Array(text)))
        }
        return SettingsSearchResult(score: averageScore, ranges: mergeRanges(matchedRanges))
    }

    private static func bestMatch(for queryToken: [Character], in textTokens: [SettingsSearchToken]) -> TokenMatch? {
        var best: TokenMatch?
        textTokens.forEach { token in
            guard let candidate = scoreTokenMatch(queryToken, token) else { return }
            if best == nil || candidate.score > best!.score {
                best = candidate
            }
        }
        return best
    }

    private static func scoreTokenMatch(_ query: [Character], _ token: SettingsSearchToken) -> TokenMatch? {
        let tokenChars = token.normalized
        let queryLength = query.count
        let tokenLength = tokenChars.count
        guard queryLength > 0, tokenLength > 0 else { return nil }
        if queryLength <= 2 {
            guard let exactRange = firstExactRange(of: query, in: tokenChars) else { return nil }
            return TokenMatch(score: 1, ranges: [originalRange(from: exactRange, using: token)])
        }
        let maxLength = max(queryLength, tokenLength)
        let minLength = min(queryLength, tokenLength)
        let distance = damerauLevenshteinDistance(query, tokenChars)
        let distanceScore = 1 - Double(distance) / Double(maxLength)
        let prefixLength = commonPrefixLength(query, tokenChars)
        let prefixScore = Double(prefixLength) / Double(minLength)
        let lcsIndexes = lcsTokenIndexes(query, tokenChars)
        let coverageScore = Double(lcsIndexes.count) / Double(queryLength)
        var score = distanceScore * 0.64 + prefixScore * 0.23 + coverageScore * 0.13
        if tokenChars.starts(with: query) {
            score = max(score, 0.92 - Double(max(0, tokenLength - queryLength)) * 0.015)
        }
        if let exactRange = firstExactRange(of: query, in: tokenChars) {
            score = max(score, 0.86 - Double(max(0, tokenLength - queryLength)) * 0.01)
            guard score >= minimumScore(queryLength) else { return nil }
            return TokenMatch(score: score, ranges: [originalRange(from: exactRange, using: token)])
        }
        guard lcsIndexes.count >= minimumLcsLength(queryLength) else { return nil }
        guard score >= minimumScore(queryLength) else { return nil }
        let ranges = originalRanges(from: lcsIndexes, using: token)
        guard !ranges.isEmpty else { return nil }
        return TokenMatch(score: score, ranges: ranges)
    }

    private static func minimumScore(_ queryLength: Int) -> Double {
        switch queryLength {
        case 0...2: return 1
        case 3: return 0.74
        case 4: return 0.68
        case 5: return 0.64
        case 6...7: return 0.60
        default: return 0.56
        }
    }

    private static func minimumLcsLength(_ queryLength: Int) -> Int {
        if queryLength <= 2 { return queryLength }
        if queryLength == 3 { return 2 }
        if queryLength <= 5 { return Int(ceil(Double(queryLength) * 0.6)) }
        return Int(ceil(Double(queryLength) * 0.55))
    }

    private static func mergeRanges(_ ranges: [Range<Int>]) -> [Range<Int>] {
        mergeRanges(ranges) { _, _ in false }
    }

    private static func mergeRangesAcrossSeparators(_ ranges: [Range<Int>], in textCharacters: [Character]) -> [Range<Int>] {
        mergeRanges(ranges) {
            onlySeparatorsBetween($0, $1, in: textCharacters)
        }
    }

    private static func mergeRanges(_ ranges: [Range<Int>], _ shouldMergeGap: (Int, Int) -> Bool) -> [Range<Int>] {
        if ranges.isEmpty { return [] }
        let sorted = ranges.sorted {
            if $0.lowerBound == $1.lowerBound {
                return $0.upperBound < $1.upperBound
            }
            return $0.lowerBound < $1.lowerBound
        }
        var merged = [sorted[0]]
        sorted.dropFirst().forEach { range in
            let lastIndex = merged.count - 1
            let lastRange = merged[lastIndex]
            if range.lowerBound <= lastRange.upperBound || shouldMergeGap(lastRange.upperBound, range.lowerBound) {
                merged[lastIndex] = lastRange.lowerBound..<max(lastRange.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func onlySeparatorsBetween(_ start: Int, _ end: Int, in textCharacters: [Character]) -> Bool {
        guard start < end else { return true }
        guard start >= 0, end <= textCharacters.count else { return false }
        for index in start..<end {
            if !normalizedCharacters(textCharacters[index]).isEmpty { return false }
        }
        return true
    }

    private static func firstExactRange(of query: [Character], in token: [Character]) -> Range<Int>? {
        if query.isEmpty || query.count > token.count { return nil }
        for start in 0...(token.count - query.count) {
            if Array(token[start..<(start + query.count)]) == query {
                return start..<(start + query.count)
            }
        }
        return nil
    }

    private static func commonPrefixLength(_ lhs: [Character], _ rhs: [Character]) -> Int {
        let commonLength = min(lhs.count, rhs.count)
        if commonLength == 0 { return 0 }
        for i in 0..<commonLength where lhs[i] != rhs[i] {
            return i
        }
        return commonLength
    }

    private static func damerauLevenshteinDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        let n = lhs.count
        let m = rhs.count
        if n == 0 { return m }
        if m == 0 { return n }
        var matrix = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { matrix[i][0] = i }
        for j in 0...m { matrix[0][j] = j }
        if n == 0 || m == 0 { return matrix[n][m] }
        for i in 1...n {
            for j in 1...m {
                let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                let deletion = matrix[i - 1][j] + 1
                let insertion = matrix[i][j - 1] + 1
                let substitution = matrix[i - 1][j - 1] + cost
                var value = min(deletion, insertion, substitution)
                if i > 1, j > 1, lhs[i - 1] == rhs[j - 2], lhs[i - 2] == rhs[j - 1] {
                    value = min(value, matrix[i - 2][j - 2] + 1)
                }
                matrix[i][j] = value
            }
        }
        return matrix[n][m]
    }

    private static func lcsTokenIndexes(_ query: [Character], _ token: [Character]) -> [Int] {
        let n = query.count
        let m = token.count
        if n == 0 || m == 0 { return [] }
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                if query[i] == token[j] {
                    dp[i][j] = 1 + dp[i + 1][j + 1]
                } else {
                    dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var i = 0
        var j = 0
        var matchedIndexes = [Int]()
        while i < n && j < m {
            if query[i] == token[j] {
                matchedIndexes.append(j)
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return matchedIndexes
    }

    private static func originalRange(from normalizedRange: Range<Int>, using token: SettingsSearchToken) -> Range<Int> {
        let start = token.normalizedToOriginal[normalizedRange.lowerBound]
        let end = token.normalizedToOriginal[normalizedRange.upperBound - 1] + 1
        return start..<end
    }

    private static func originalRanges(from normalizedIndexes: [Int], using token: SettingsSearchToken) -> [Range<Int>] {
        if normalizedIndexes.isEmpty { return [] }
        var ranges = [Range<Int>]()
        var runStart = normalizedIndexes[0]
        var runEnd = normalizedIndexes[0]
        normalizedIndexes.dropFirst().forEach { index in
            if index == runEnd + 1 {
                runEnd = index
            } else {
                ranges.append(originalRange(from: runStart..<(runEnd + 1), using: token))
                runStart = index
                runEnd = index
            }
        }
        ranges.append(originalRange(from: runStart..<(runEnd + 1), using: token))
        return mergeRanges(ranges)
    }

    private static func tokens(_ text: String) -> [SettingsSearchToken] {
        let characters = Array(text)
        var tokens = [SettingsSearchToken]()
        var normalized = [Character]()
        var normalizedToOriginal = [Int]()
        func flushCurrentToken() {
            guard !normalized.isEmpty else { return }
            tokens.append(SettingsSearchToken(normalized: normalized, normalizedToOriginal: normalizedToOriginal))
            normalized.removeAll(keepingCapacity: true)
            normalizedToOriginal.removeAll(keepingCapacity: true)
        }
        for (originalIndex, character) in characters.enumerated() {
            let normalizedChars = normalizedCharacters(character)
            if normalizedChars.isEmpty {
                flushCurrentToken()
                continue
            }
            normalizedChars.forEach {
                normalized.append($0)
                normalizedToOriginal.append(originalIndex)
            }
        }
        flushCurrentToken()
        return tokens
    }

    private static func hasInterTermSeparator(_ query: String) -> Bool {
        var sawSearchCharacter = false
        var sawSeparatorAfterSearchCharacter = false
        for character in query {
            if normalizedCharacters(character).isEmpty {
                if sawSearchCharacter {
                    sawSeparatorAfterSearchCharacter = true
                }
                continue
            }
            if sawSearchCharacter && sawSeparatorAfterSearchCharacter {
                return true
            }
            sawSearchCharacter = true
            sawSeparatorAfterSearchCharacter = false
        }
        return false
    }

    private static func normalizedCharacters(_ character: Character) -> [Character] {
        let folded = String(character).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
        var chars = [Character]()
        folded.unicodeScalars.forEach {
            if isSearchScalar($0) {
                chars.append(Character(String($0)))
            }
        }
        return chars
    }

    private static func isSearchScalar(_ scalar: UnicodeScalar) -> Bool {
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
        if CharacterSet.punctuationCharacters.contains(scalar) { return false }
        if CharacterSet.symbols.contains(scalar) { return false }
        return true
    }
}
