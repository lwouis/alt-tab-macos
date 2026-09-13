# EmailLineWrap — Specs

## Summary

The Settings sidebar's bottom pill (`UpgradeButton`) shows "Pro activated" over the customer's email.
The email is often the person's name, so it keeps the big 13pt semibold font and the pill grows
instead: the address wraps over up to 3 lines, and only past that does it lose its tail to an
ellipsis (with the full address in the tooltip).

AppKit can't do that on its own. `NSButtonCell` either wraps or truncates, never both, and its
wrapping breaks mid-word because an email has no spaces:
`christopher.vandenbe` / `rghe@universiteit-am`. `EmailLineWrap` measures and breaks the lines
itself; `UpgradeButton` joins them with `\n` and sizes its height constraint from the count.

## Behavior & edge cases

- A line ends at the longest prefix that fits, pulled back to just after a separator (`@ . - _ +`)
  when one is close enough to the end: after `@` if the line is then still ≥45% full, after any
  other separator if ≥55% full. Below those ratios the stubby line reads worse than the mid-word
  break, so the greedy cut stands.
- The `@` wins over later separators, which puts the domain on its own line:
  `jean-francois.dubois@` / `entreprise-solutions.fr`.
- Wrapping is lossless: joining the lines of an untruncated result gives the address back. Nothing
  is inserted at the break, since a hyphen would be indistinguishable from one in the address.
- Past the line budget the last line is shortened until it plus `…` fits. `isTruncated` then tells
  the caller to put the full address in the tooltip.
- A line always advances by at least one character, so a width too narrow for even one character
  terminates instead of looping.
- `fittedFont` drops the size in half-point steps down to `minSize`, and only if that removes a whole
  line: `john@cool-software.com` otherwise leaves a lonely `com` on line 2. An address that overflows
  the budget at every size keeps the base font, since shrinking can't save it.

## Test scenarios

Mirrors `EmailLineWrapTests.swift` 1:1.

- **testShortEmailStaysOnOneLine** — an address that fits is returned as a single untruncated line.
- **testBreaksAfterTheAtSign** — the domain goes on its own line.
- **testBreaksAfterASeparatorWhenTheAtSignIsOutOfReach** — later lines break after `-`, not mid-word.
- **testKeepsEveryLineWithinTheAvailableWidth** — no line overflows the pill.
- **testUntruncatedLinesRebuildTheAddress** — joining the lines gives the address back.
- **testTruncatesTheTailPastTheLineBudget** — a 78-char address yields 3 lines, the last ending in `…`, showing a prefix of the address.
- **testBreaksAnywhereWhenThereIsNoSeparatorToBreakOn** — a separator-free local part fills each line.
- **testMakesProgressWhenNotEvenOneCharacterFits** — a 2pt width still terminates.
- **testEmptyEmailProducesNoLines** — empty in, empty out, not truncated.
- **testShrinksTheFontOnlyWhenThatSavesALine** — `john@cool-software.com` drops below 13pt and fits on one line.
- **testKeepsTheBaseFontWhenShrinkingWouldNotSaveALine** — a one-liner and an over-budget address both keep 13pt.
