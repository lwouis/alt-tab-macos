import Foundation

class SearchTestable {
    static func acronymBonus(query: String, text: String) -> Double {
        let q = normalizedQuery(query)
        if q.isEmpty { return 0 }
        let t = text.lowercased()
        if t.hasPrefix(q) { return 6.0 + min(2.0, Double(q.count) * 0.25) }
        let starts = wordStarts(in: text)
        if starts.isEmpty { return 0 }
        let qChars = Array(q)
        var qi = 0
        var firstMatch: Int?
        for (i, c) in starts.enumerated() {
            if qi >= qChars.count { break }
            if c == qChars[qi] {
                if firstMatch == nil { firstMatch = i }
                qi += 1
            }
        }
        guard qi == qChars.count else { return 0 }
        let pos = firstMatch ?? 0
        return 4.0 + min(2.0, Double(q.count) * 0.2) + (pos == 0 ? 1.0 : max(0.0, 0.6 - Double(pos) * 0.15))
    }

    private static func normalizedQuery(_ query: String) -> String {
        String(Array(query).filter { c in !c.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) } }).lowercased()
    }

    private static func wordStarts(in text: String) -> [Character] {
        let chars = Array(text)
        if chars.isEmpty { return [] }
        var starts: [Character] = []
        starts.reserveCapacity(min(16, chars.count))
        for i in 0..<chars.count {
            let c = chars[i]
            if !isAlphaNum(c) { continue }
            if i == 0 || !isAlphaNum(chars[i - 1]) || (isLower(chars[i - 1]) && isUpper(c)) {
                starts.append(Character(String(c).lowercased()))
            }
        }
        return starts
    }

    private static func isAlphaNum(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) } }
    private static func isLower(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { CharacterSet.lowercaseLetters.contains($0) } }
    private static func isUpper(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { CharacterSet.uppercaseLetters.contains($0) } }
}
