# Search (ranking algorithm) — Specs

> **Line coverage:** `SearchTestable.swift` 98% · _refreshed 2026-05-27 by `/coverage-explore`_

## Summary

When the user types in the switcher's search box, `SearchTestable` scores each window so the best match
floats to the top. It's a **6-tier** matcher (best tier wins; ties broken by score), scoring a query
against both the **app name** and the **window title** and keeping the higher (app name weighted slightly
above title). It also produces **highlight spans** so the UI can bold the matched characters.

The tiers, best to worst:
1. **Exact** (case-insensitive, whitespace-agnostic)
2. **Text prefix** (query starts the app/title)
3. **Word prefix** (query starts any word — incl. camelCase / punctuation boundaries)
4. **Contiguous substring**
5. **Acronym** (first letters of words)
6. **Fuzzy** (typo-tolerant via Damerau-Levenshtein; substitution/transposition/insertion/deletion), plus
   a partial-prefix-with-typo rescue for incremental typing.

This suite is large and example-driven — it pins tier ordering, scoring relativities, Unicode handling,
and several regressions from real user screenshots — because the ranking is easy to subtly break.

## Behavior & edge cases

- **Diacritics** fold both ways; highlight spans map back to the original (un-folded) string offsets.
- **Word boundaries**: spaces, camelCase, `_`, `.`, `/`, `:`, emoji, and digit/letter transitions all
  start new words for prefix/acronym matching.
- **Case bonus**: an uppercase query character that matches case adds a small bonus, but never enough to
  cross a tier gap; applies across tiers (T3/T4/T5).
- **Fuzzy is bounded**: short queries allow fewer edits than long ones; a transposition is one edit;
  scattered characters and random noise are rejected (the ky/Kyoto/Slack regressions).
- **Single/two-char queries** don't use fuzzy. **Empty/whitespace** queries match nothing.
- App-name matches surface even when the title doesn't, and rank above title matches at the same tier.

## Test scenarios

Mirrors `SearchTests.swift` 1:1.

### Tier 1 — exact
- **testT1Exact** · **testT1ExactIgnoresSpaces** · **testT1NotMatchedWhenDifferent**

### Tier 2 — text prefix
- **testT2TextPrefix** · **testT2NotPrefix**

### Tier 3 — word prefix
- **testT3WordPrefix** · **testT3PunctuationAsBoundary**

### Tier 4 — contiguous substring
- **testT4Substring** · **testT4SubstringSpansAcrossCamelCase**

### Tier 5 — acronym
- **testT5Acronym** · **testT5AcronymWithEmoji**

### Tier 6 — fuzzy
- **testT6FuzzySubstitution** · **testT6FuzzyTransposition** · **testT6FuzzyInsertionAndDeletion**

### Tier 6 — partial-prefix-with-typo (incremental typing rescue)
- **testT6PartialPrefixWithTypo** · **testT6PartialPrefixOutgrows** · **testT6FullWordRanksAbovePartial** · **testT6PartialPenalizesLongWord** · **testT6PartialOutranksWhenMoreCoverage** · **testT6FirstCharTypoRequiresMoreChars**

### Rejection regressions (user screenshots)
- **testRejectKyAgainstSlackChannel** · **testRejectKyAgainstResidency** · **testKyoRanksKyotoFarAboveUnderrated** · **testAcceptKyoAgainstKyoto**

### Single-char queries (no fuzzy)
- **testSingleCharNoFuzzy** · **testTwoCharQueryNoFuzzy**

### Diacritics
- **testDiacriticsFoldingAtTextStart** · **testDiacriticsFoldingMidText** · **testDiacriticsBidirectional** · **testDiacriticHighlightSpansMapToOriginal**

### Emojis
- **testEmojiAsBoundary** · **testTitleAllEmojiNoMatch**

### Case-sensitivity
- **testLowercaseQueryHasNoCaseBonus** · **testUppercaseQueryBoostsCaseExact** · **testCaseBonusNeverCrossesTierGap** · **testCaseBonusForT3WordPrefix**

### App-name vs title ranking
- **testAppNameMatchSurfacesEvenWhenTitleDoesNot** · **testAppNameWeightedAboveTitleAtSameTier**

### Tier ordering
- **testTierOrdering_ChrAcrossCandidates** · **testEarlyMatchBeatsLateMatch**

### Word boundary
- **testT6OperatesPerWord** · **testCamelCaseSplitProvidesWordBoundary**

### Edit-distance edge cases
- **testTwoEditsRejectedForShortQuery** · **testTwoEditsAcceptedForLongQuery** · **testTranspositionIsOneEdit**

### Rejection variants
- **testRejectsScatteredChars** · **testRejectsRandomNoise**

### Scoring relative ranking
- **testFuzzyRanksBelowExactInSameField** · **testWordPrefixBeatsSubstring**

### acronymBonus (preserved behavior)
- **testAcronymBonusPrefixMatch** · **testAcronymBonusWordStarts** · **testAcronymBonusPrefersEarlierMatch** · **testAcronymBonusIgnoresSpacesInQuery**

### Boundary characters
- **testUnderscoreAsWordBoundary** · **testDotAsWordBoundary** · **testSlashAsWordBoundary** · **testColonAsWordBoundary**

### Numbers
- **testSingleDigitMatchesNumberWord** · **testMultiDigitWordPrefix** · **testAlphanumericMix**

### Empty / whitespace inputs
- **testEmptyQueryProducesNoMatch** · **testWhitespaceQueryNormalizesToEmpty** · **testEmptyTextNoMatch**

### Highlight spans
- **testHighlightSpansForT3WordPrefix** · **testHighlightSpansForT4Substring** · **testHighlightSubspansForT5Acronym** · **testHighlightSpansForT6PartialPrefix**

### Case bonus across tiers
- **testCaseBonusAppliesToT5Acronym** · **testCaseBonusAppliesToT4Substring**

### Combined scenarios
- **testTitleCombinedWithEmoji** · **testCJKDoesNotCrash** · **testLongTitleDoesNotMatchScatteredChars**

### Long-query fuzzy (regression: shinkansen)
- **testShinkansenWithSubstitution** · **testShinkansenWithDeletion** · **testShinkansenInLongerTitle**

### damerauLevenshtein primitive
- **testDLEdits**

### MatchResult → SWResult bridging
The renderer consumes `SWResult`; `MatchResult.toSWResult()` converts the kernel's output, deriving similarity = score/1200 and dropping the unused `ops` field.
- **testToSWResultBridgesMatchResultFields** — score, span, subspans copy verbatim; similarity = score/1200; ops cleared.
- **testToSWResultScalesSimilarityProportionally** — similarity scales linearly with score (600 → 0.5).
