import XCTest

final class SearchTests: XCTestCase {

    // MARK: - Helpers

    private func match(_ query: String, _ text: String) -> MatchResult? {
        SearchTestable.tierMatch(query: query, text: text)
    }

    private func tier(_ query: String, _ text: String) -> Int? {
        match(query, text)?.tier
    }

    private func score(_ query: String, _ text: String) -> Int {
        match(query, text)?.score ?? 0
    }

    private func combined(_ query: String, app: String, title: String) -> Double {
        SearchTestable.combinedScore(query: query, appName: app, title: title)
    }

    // MARK: - Tier 1: exact match

    func testT1Exact() throws {
        XCTAssertEqual(tier("kyoto", "Kyoto"), 1)
        XCTAssertEqual(tier("Kyoto", "Kyoto"), 1)
        XCTAssertEqual(tier("kyoto", "kyoto"), 1)
    }

    func testT1ExactIgnoresSpaces() throws {
        XCTAssertEqual(tier(" kyoto ", "Kyoto"), 1)
        XCTAssertEqual(tier("kyoto", "Ky oto"), 1)
    }

    func testT1NotMatchedWhenDifferent() throws {
        XCTAssertNotEqual(tier("kyoto", "Kyoto Trip"), 1)
    }

    // MARK: - Tier 2: text prefix

    func testT2TextPrefix() throws {
        XCTAssertEqual(tier("chr", "Chrome"), 2)
        XCTAssertEqual(tier("chr", "Chrome - About"), 2)
    }

    func testT2NotPrefix() throws {
        XCTAssertNotEqual(tier("chr", "My Chrome"), 2)
    }

    // MARK: - Tier 3: word prefix

    func testT3WordPrefix() throws {
        XCTAssertEqual(tier("chr", "Google Chrome"), 3)
        XCTAssertEqual(tier("dev", "Chrome DevTools"), 3) // camelCase split
        XCTAssertEqual(tier("kyo", "Airbnb | Kyoto - Locations"), 3)
    }

    func testT3PunctuationAsBoundary() throws {
        XCTAssertEqual(tier("kyo", "Trip-Kyoto"), 3)
    }

    // MARK: - Tier 4: contiguous substring

    func testT4Substring() throws {
        XCTAssertEqual(tier("rome", "Google Chrome"), 4)
        XCTAssertEqual(tier("oogl", "Google"), 4)
    }

    func testT4SubstringSpansAcrossCamelCase() throws {
        XCTAssertEqual(tier("github", "🎉 Project · GitHub"), 4)
    }

    // MARK: - Tier 5: acronym

    func testT5Acronym() throws {
        XCTAssertEqual(tier("cd", "Chrome DevTools"), 5)
        XCTAssertEqual(tier("vsc", "Visual Studio Code"), 5)
        XCTAssertEqual(tier("gcd", "Google Chrome DevTools"), 5)
    }

    func testT5AcronymWithEmoji() throws {
        XCTAssertEqual(tier("pg", "🎉 Project · GitHub"), 5)
    }

    // MARK: - Tier 6: fuzzy

    func testT6FuzzySubstitution() throws {
        XCTAssertEqual(tier("tokio", "Tokyo"), 6)
        XCTAssertEqual(tier("shrome", "Chrome"), 6) // sub 'c'→'s' = 1 edit
        XCTAssertEqual(tier("chrime", "Chrome"), 6) // sub 'o'→'i' = 1 edit
    }

    func testT6FuzzyTransposition() throws {
        XCTAssertEqual(tier("tkyo", "Tokyo"), 6)
        XCTAssertEqual(tier("develpoment", "Development"), 6)
    }

    func testT6FuzzyInsertionAndDeletion() throws {
        XCTAssertEqual(tier("chrme", "Chrome"), 6)   // 1 deletion (missing 'o')
        XCTAssertEqual(tier("chrrome", "Chrome"), 6) // 1 insertion (extra 'r')
    }

    // MARK: - Tier 6: partial-prefix-with-typo (incremental typing rescue)

    func testT6PartialPrefixWithTypo() throws {
        // user typed half the word with a typo — should still match
        XCTAssertEqual(tier("kio", "Kyoto"), 6)        // qLen 3 < wLen 5, sub i→y in prefix "kyo"
        XCTAssertEqual(tier("chrm", "Chrome"), 6)      // qLen 4 < wLen 6, missing 'o' in prefix
        XCTAssertEqual(tier("gthub", "GitHub"), 6)     // qLen 5 < wLen 6, missing 'i' in whole word
    }

    func testT6PartialPrefixOutgrows() throws {
        // user typed slightly more than the prefix, with a typo
        XCTAssertEqual(tier("kiot", "Kyoto"), 6)
    }

    func testT6FullWordRanksAbovePartial() throws {
        // full-word match (5/5) ranks above partial-prefix match (3/5) at the same edit count
        let full = score("tokio", "Tokyo")     // 5 of 5 chars, 1 sub
        let partial = score("kio", "Kyoto")    // 3 of 5 chars, 1 sub
        XCTAssertGreaterThan(full, partial)
    }

    func testT6PartialPenalizesLongWord() throws {
        // matching a short query against a long word should score lower than matching a short word
        let shortTarget = score("kio", "Kyoto")              // 3 of 5
        let longTarget = score("kio", "kyototokyolongname")  // 3 of 18
        XCTAssertGreaterThan(shortTarget, longTarget)
    }

    func testT6PartialOutranksWhenMoreCoverage() throws {
        // same edit count, but more characters of the word matched → higher score
        let shortPrefix = score("kio", "Kyoto")  // m=3 of 5
        let longerPrefix = score("kioto", "Kyoto") // m=5 of 5 (full word)
        XCTAssertGreaterThan(longerPrefix, shortPrefix)
    }

    func testT6FirstCharTypoRequiresMoreChars() throws {
        // 3-char query with the first char as typo can't match (would need 2 edits at qLen=3)
        XCTAssertNil(match("xio", "Kyoto")) // sub k→x + sub i→y = 2 edits
        // but a longer query with first-char typo can match at qLen=10+
        XCTAssertEqual(tier("xevelopment", "Development"), 6) // sub d→x = 1 edit
    }

    // MARK: - Rejection tests (regressions for the user's screenshots)

    func testRejectKyAgainstSlackChannel() throws {
        XCTAssertNil(match("ky", "général (Channel) - Engineering Managers Community - Slack"))
    }

    func testRejectKyAgainstResidency() throws {
        XCTAssertNil(match("ky", "japan permanent residency - Google Search"))
    }

    func testKyoRanksKyotoFarAboveUnderrated() throws {
        // "kyo" matches Kyoto exactly at T3; it may match the title with "known" via T6 partial-prefix-with-typo
        // (kno ≈ kyo with 1 sub). The CRITICAL property is that Kyoto ranks far above the noisy match.
        let kyoto = score("kyo", "Airbnb | Kyoto - Locations de vacances et logements - Kyoto")
        let underrated = score("kyo", "Underrated Osaka: 10 lesser known attractions & hidden gems - Home in the World")
        XCTAssertEqual(tier("kyo", "Airbnb | Kyoto - Locations de vacances et logements - Kyoto"), 3)
        XCTAssertGreaterThan(kyoto, underrated * 2) // Kyoto at least 2x the noisy match
    }

    func testAcceptKyoAgainstKyoto() throws {
        XCTAssertEqual(tier("kyo", "Airbnb | Kyoto - Locations de vacances et logements - Kyoto"), 3)
    }

    // MARK: - Single-char queries (no fuzzy)

    func testSingleCharNoFuzzy() throws {
        XCTAssertNil(match("k", "abcdef"))           // no T1-T4 hit
        XCTAssertEqual(tier("a", "Apple"), 2)        // T2 prefix on single char
        XCTAssertEqual(tier("p", "Apple"), 4)        // T4 substring (mid-word)
    }

    func testTwoCharQueryNoFuzzy() throws {
        XCTAssertNil(match("ky", "kno"))             // T6 disabled at len 2
    }

    // MARK: - Diacritics

    func testDiacriticsFoldingAtTextStart() throws {
        // text starts with diacritic-folded query → T2
        XCTAssertEqual(tier("general", "général (Channel) - Engineering Managers"), 2)
        XCTAssertEqual(tier("cafe", "Café Wifi"), 2)
    }

    func testDiacriticsFoldingMidText() throws {
        // diacritic-folded query matches a non-leading word → T3
        XCTAssertEqual(tier("general", "App: général"), 3)
        XCTAssertEqual(tier("cafe", "Trip - Café Wifi"), 3)
    }

    func testDiacriticsBidirectional() throws {
        // query has diacritics, text doesn't — still match
        XCTAssertEqual(tier("général", "general settings"), 2)
    }

    func testDiacriticHighlightSpansMapToOriginal() throws {
        let r = match("cafe", "Café Wifi")
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.span, 0..<4)               // covers C, a, f, é (4 graphemes)
    }

    // MARK: - Emojis

    func testEmojiAsBoundary() throws {
        XCTAssertEqual(tier("project", "🎉 Project · GitHub"), 3)
        XCTAssertEqual(tier("github", "🎉 Project · GitHub"), 4)
    }

    func testTitleAllEmojiNoMatch() throws {
        XCTAssertNil(match("anything", "🎉🚀⭐"))
    }

    // MARK: - Case-sensitivity

    func testLowercaseQueryHasNoCaseBonus() throws {
        XCTAssertEqual(score("chrome", "Chrome"), score("chrome", "chrome"))
    }

    func testUppercaseQueryBoostsCaseExact() throws {
        XCTAssertGreaterThan(score("Chrome", "ChromeOS"), score("Chrome", "chromeos"))
        XCTAssertGreaterThan(score("Ch", "Chrome"), score("Ch", "chrome"))
    }

    func testCaseBonusNeverCrossesTierGap() throws {
        // T2 (Chronicle starts with Chro) > T3 (Mozilla Chronicle word-prefix) regardless of case.
        let t2 = score("Chro", "Chronicle")           // T2 base 800
        let t3 = score("Chro", "Mozilla Chronicle")   // T3 base 600
        XCTAssertGreaterThan(t2, t3)
        XCTAssertEqual(tier("Chro", "Chronicle"), 2)
        XCTAssertEqual(tier("Chro", "Mozilla Chronicle"), 3)
    }

    func testCaseBonusForT3WordPrefix() throws {
        XCTAssertGreaterThan(score("Chrome", "Google Chrome"), score("Chrome", "google chrome"))
    }

    // MARK: - App-name vs title ranking

    func testAppNameMatchSurfacesEvenWhenTitleDoesNot() throws {
        let s = combined("safari", app: "Safari", title: "google.com - Search")
        XCTAssertGreaterThan(s, 0)
    }

    func testAppNameWeightedAboveTitleAtSameTier() throws {
        let appWin = combined("chrome", app: "Chrome", title: "Issues")
        let titleWin = combined("chrome", app: "Other", title: "Chrome Tab")
        XCTAssertGreaterThan(appWin, titleWin)
    }

    // MARK: - Tier ordering

    func testTierOrdering_ChrAcrossCandidates() throws {
        let exact = score("chr", "chr")
        let prefix = score("chr", "Chrome")
        let wordPrefix = score("chr", "Google Chrome")
        let strictSubstring = score("chr", "abchrxx")  // "chr" inside "abchrxx" — no word-prefix match
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, wordPrefix)
        XCTAssertGreaterThan(wordPrefix, strictSubstring)
        // sanity: tiers are correct
        XCTAssertEqual(tier("chr", "chr"), 1)
        XCTAssertEqual(tier("chr", "Chrome"), 2)
        XCTAssertEqual(tier("chr", "Google Chrome"), 3)
        XCTAssertEqual(tier("chr", "abchrxx"), 4)
    }

    func testEarlyMatchBeatsLateMatch() throws {
        // both T3 word prefix
        let early = score("chr", "Chrome xxxxxx")
        let late = score("chr", "Aaaaa Bbbbb Chrome")
        XCTAssertGreaterThan(early, late)
    }

    // MARK: - Word boundary

    func testT6OperatesPerWord() throws {
        // T6 runs DL only against complete words (from wordSpans), not arbitrary text positions.
        // For "kyo" against single word "Skzo": T4 fails (no "kyo" substring), T6 runs DL("kyo","skzo")
        // which exceeds k=1 (would need 2+ edits). Result: REJECT.
        XCTAssertNil(match("kyo", "Skzo"))
    }

    func testCamelCaseSplitProvidesWordBoundary() throws {
        XCTAssertEqual(tier("dev", "MyDevTools"), 3)
    }

    // MARK: - Edit-distance edge cases

    func testTwoEditsRejectedForShortQuery() throws {
        // 2 substitutions in a 6-char query → REJECT (only 1 edit at len 6)
        XCTAssertNil(match("chrome", "ahromf"))
    }

    func testTwoEditsAcceptedForLongQuery() throws {
        // 11-char query with transposition (1 edit) — accepted at len 10+
        XCTAssertEqual(tier("development", "developmnet"), 6)
    }

    func testTranspositionIsOneEdit() throws {
        XCTAssertEqual(tier("tkyo", "Tokyo"), 6)
    }

    // MARK: - Rejection variants

    func testRejectsScatteredChars() throws {
        // 'k' is in known and 'b' is in attractions; should not match across words.
        XCTAssertNil(match("kb", "known attractions"))
    }

    func testRejectsRandomNoise() throws {
        XCTAssertNil(match("xyzqw", "Hello World"))
    }

    // MARK: - Scoring relative ranking (acceptance)

    func testFuzzyRanksBelowExactInSameField() throws {
        // exact "tokyo" match must rank above fuzzy "tokio" match for the same target
        let exactScore = score("tokyo", "Tokyo")
        let fuzzyScore = score("tokio", "Tokyo")
        XCTAssertGreaterThan(exactScore, fuzzyScore)
    }

    func testWordPrefixBeatsSubstring() throws {
        let wp = score("chrome", "Google Chrome - About")            // T3
        let sub = score("chrome", "abcdchromexyz")                    // T4
        XCTAssertGreaterThan(wp, sub)
    }

    // MARK: - Existing acronymBonus behavior (preserved)

    func testAcronymBonusPrefixMatch() throws {
        XCTAssertGreaterThan(SearchTestable.acronymBonus(query: "chr", text: "Chrome"), 0)
        XCTAssertEqual(SearchTestable.acronymBonus(query: "chr", text: "My Chrome"), 0)
    }

    func testAcronymBonusWordStarts() throws {
        XCTAssertGreaterThan(SearchTestable.acronymBonus(query: "cd", text: "Chrome DevTools"), 0)
        XCTAssertEqual(SearchTestable.acronymBonus(query: "cd", text: "Chrome"), 0)
    }

    func testAcronymBonusPrefersEarlierMatch() throws {
        let early = SearchTestable.acronymBonus(query: "cd", text: "Chrome DevTools")
        let later = SearchTestable.acronymBonus(query: "cd", text: "Google Chrome DevTools")
        XCTAssertGreaterThan(early, later)
    }

    func testAcronymBonusIgnoresSpacesInQuery() throws {
        let compact = SearchTestable.acronymBonus(query: "cd", text: "Chrome DevTools")
        let spaced = SearchTestable.acronymBonus(query: " c d ", text: "Chrome DevTools")
        XCTAssertEqual(compact, spaced)
    }

    // MARK: - Boundary characters (inspired by fzf algo tests)

    func testUnderscoreAsWordBoundary() throws {
        XCTAssertEqual(tier("func", "my_func_name"), 3) // T3 word prefix on "func"
        XCTAssertEqual(tier("name", "my_func_name"), 3)
    }

    func testDotAsWordBoundary() throws {
        XCTAssertEqual(tier("readme", "project.readme.md"), 3)
    }

    func testSlashAsWordBoundary() throws {
        XCTAssertEqual(tier("settings", "app/main/settings"), 3)
    }

    func testColonAsWordBoundary() throws {
        XCTAssertEqual(tier("title", "App: Title"), 3)
    }

    // MARK: - Numbers

    func testSingleDigitMatchesNumberWord() throws {
        XCTAssertEqual(tier("3", "Mac mini 3"), 3) // word "3" prefix
    }

    func testMultiDigitWordPrefix() throws {
        XCTAssertEqual(tier("2024", "Report 2024 Q1"), 3)
    }

    func testAlphanumericMix() throws {
        XCTAssertEqual(tier("v2", "App v2.0"), 3)
    }

    // MARK: - Empty / whitespace inputs

    func testEmptyQueryProducesNoMatch() throws {
        XCTAssertNil(match("", "Anything"))
        XCTAssertNil(match("", ""))
    }

    func testWhitespaceQueryNormalizesToEmpty() throws {
        XCTAssertNil(match("   ", "Anything"))
        XCTAssertNil(match("\t\n", "Anything"))
    }

    func testEmptyTextNoMatch() throws {
        XCTAssertNil(match("anything", ""))
    }

    // MARK: - Highlight spans (inspired by VS Code matchesFuzzy tests)

    func testHighlightSpansForT3WordPrefix() throws {
        // span covers exactly the matched prefix within the matched word
        let r = match("chr", "Google Chrome")
        XCTAssertEqual(r?.tier, 3)
        XCTAssertEqual(r?.span, 7..<10)
        XCTAssertEqual(r?.subspans, [7..<10])
    }

    func testHighlightSpansForT4Substring() throws {
        let r = match("rome", "Google Chrome")
        XCTAssertEqual(r?.tier, 4)
        XCTAssertEqual(r?.span, 9..<13)
    }

    func testHighlightSubspansForT5Acronym() throws {
        // each subspan covers exactly one matched word-start char
        let r = match("cd", "Chrome DevTools")
        XCTAssertEqual(r?.tier, 5)
        XCTAssertEqual(r?.subspans.count, 2)
        XCTAssertEqual(r?.subspans[0], 0..<1) // 'C' in Chrome
        XCTAssertEqual(r?.subspans[1], 7..<8) // 'D' in DevTools (orig idx 7 — past the space)
    }

    func testHighlightSpansForT6PartialPrefix() throws {
        // span only covers the matched prefix, not the whole word
        let r = match("kio", "Kyoto")
        XCTAssertEqual(r?.tier, 6)
        XCTAssertEqual(r?.span, 0..<3) // K, y, o
    }

    // MARK: - Case bonus across tiers

    func testCaseBonusAppliesToT5Acronym() throws {
        // upper-case query → bigger acronym score when target word starts also match case
        let upper = score("CD", "Chrome DevTools")
        let lower = score("cd", "Chrome DevTools")
        XCTAssertGreaterThan(upper, lower)
    }

    func testCaseBonusAppliesToT4Substring() throws {
        let upper = score("Rome", "Google Chrome")
        let lower = score("rome", "google chrome")
        XCTAssertGreaterThan(upper, lower)
    }

    // MARK: - Combined scenarios (inspired by fuzzysort tests)

    func testTitleCombinedWithEmoji() throws {
        // emoji + camelCase + punctuation in one title — query still finds the right word
        XCTAssertEqual(tier("dev", "🎉 MyDevTools - v2"), 3)
    }

    func testCJKDoesNotCrash() throws {
        // Japanese and Chinese chars — whitespace-less; we just verify it doesn't crash and behaves sensibly.
        XCTAssertNil(match("xyz", "東京タワー"))
        // exact-ish match: query in CJK matches when present as substring
        XCTAssertNotNil(match("東京", "東京タワー")) // T2 prefix: text starts with "東京"
    }

    func testLongTitleDoesNotMatchScatteredChars() throws {
        // 'a' in many places; query "abc" should NOT match a long unrelated title
        XCTAssertNil(match("abc", "Quick brown fox jumps over the lazy dog"))
    }

    // MARK: - Long-query fuzzy matches (regression: shinkansen)

    func testShinkansenWithSubstitution() throws {
        // 10-char query, 1 sub at position 0
        XCTAssertEqual(tier("chinkansen", "shinkansen"), 6)
    }

    func testShinkansenWithDeletion() throws {
        // 9-char query, 1 deletion at position 3 (missing 'n')
        XCTAssertEqual(tier("shikansen", "shinkansen"), 6)
    }

    func testShinkansenInLongerTitle() throws {
        // realistic window title
        XCTAssertEqual(tier("shikansen", "Tokyo Shinkansen Schedule"), 6)
        XCTAssertEqual(tier("chinkansen", "Shinkansen - Wikipedia"), 6)
    }

    // MARK: - damerauLevenshtein primitive

    func testDLEdits() throws {
        XCTAssertEqual(SearchTestable.damerauLevenshtein(Array("kitten"), Array("kitten"), k: 2), 0)
        XCTAssertEqual(SearchTestable.damerauLevenshtein(Array("tokio"), Array("tokyo"), k: 1), 1)
        XCTAssertEqual(SearchTestable.damerauLevenshtein(Array("tkyo"), Array("tokyo"), k: 1), 1) // transposition
        XCTAssertNil(SearchTestable.damerauLevenshtein(Array("abcd"), Array("efgh"), k: 1))
    }

    // MARK: - MatchResult → SWResult bridging

    /// `toSWResult` is called by `Search.swift` to hand match data to the rendering layer. It
    /// derives similarity from score / 1200, copies span and subspans verbatim, and clears `ops`
    /// (operations metadata is unused downstream).
    func testToSWResultBridgesMatchResultFields() {
        let m = MatchResult(score: 1200, tier: 1, span: 0..<5, subspans: [0..<2, 3..<5])
        let sw = m.toSWResult()
        XCTAssertEqual(sw.score, 1200)
        XCTAssertEqual(sw.similarity, 1.0, accuracy: 0.001, "1200/1200 normalizes to 1.0")
        XCTAssertEqual(sw.span, 0..<5)
        XCTAssertEqual(sw.subspans, [0..<2, 3..<5])
        XCTAssertTrue(sw.ops.isEmpty, "ops is dropped on the way out — unused by the renderer")
    }

    func testToSWResultScalesSimilarityProportionally() {
        let m = MatchResult(score: 600, tier: 3, span: 1..<3, subspans: [])
        let sw = m.toSWResult()
        XCTAssertEqual(sw.similarity, 0.5, accuracy: 0.001, "600 / 1200 = 0.5")
    }
}
