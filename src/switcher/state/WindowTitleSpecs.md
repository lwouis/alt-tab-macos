# WindowTitle — Specs

## Summary

A window title is whatever the app wrote into `kAXTitle`, and nothing stops it holding several lines.
Two apps do it in ordinary use:

- **Telegram Desktop** titles its window with the beginning of the post the open channel is showing, newlines
  and all.
- **Warp** titles its window with the command it is asking about, so a Claude Code permission prompt over a
  pasted script arrives as a paragraph.

The switcher treats a title as one line everywhere — one label, one line height, one measured width. AppKit
does not: `NSCell.cellSize.height` is one font line height *per line* in the string. A single such window on
the desktop made `TilesView.layoutCache.labelHeight` two or three times what it should be, and every tile in
the grid inherited it: the thumbnails were pushed down inside their tiles almost onto the next row, and the
title drew over the image (#6010).

`WindowTitle.singleLine` flattens the string where `Window.bestEffortTitle` records it, so the model has no
multi-line titles in it and every consumer downstream — layout, search ranges, tooltips, VoiceOver, the
`--list` CLI — keeps the single-line assumption it already makes. `TilesView.labelLineHeight()` is the second
half of the same fix, and does not depend on this one: it makes the line height a property of the font, so
no string that gets in by another route can move the grid again.

## Behavior & edge cases

- **Every break AppKit lays out is flattened**: LF, CR, CRLF, VT, FF, NEL (U+0085), and the Unicode line and
  paragraph separators (U+2028 / U+2029). `CharacterSet.newlines` is the same set, but membership is checked
  against a scalar range instead: this runs per character of every title of every window on every AX update,
  and the bridged `CharacterSet.contains` is not free there.
- **A run of breaks becomes one space, not one per break.** `\r\n` is a pair, and a blank line between two
  paragraphs is two more; a title made of them would otherwise be mostly gaps.
- **The indentation around a break goes with it.** A wrapped post or a pasted script is indented, and the
  spaces on either side of the newline are an artifact of the layout the app was drawing, not of the text.
- **A leading or trailing break produces no space at all**, so a title never starts or ends with one.
- **Nothing else is touched.** Tabs and runs of spaces inside a line are left as the app wrote them: they do
  not change the measured height, and collapsing them would change titles no user reported a problem with.
- **A title with no break is returned as-is**, allocating nothing. That is every title of every ordinary app,
  and this sits on the AX update path.
- **The empty string stays empty** — `bestEffortTitle` already fell back to the app name before reaching here,
  and an app with no localized name legitimately yields `""`.

---

## Test scenarios

Mirrors `WindowTitleTests.swift` 1:1.

### A. Nothing to do
- **testPlainTitleIsUntouched** — an ordinary one-line title comes back identical.
- **testEmptyTitleStaysEmpty** — `""` → `""`.
- **testTabsAndDoubleSpacesInsideALineAreKept** — only line breaks are the target.

### B. The break becomes a separator
- **testLineFeedBecomesOneSpace** — the Telegram shape: `"Channel\nFirst line of the post"`.
- **testCarriageReturnBecomesOneSpace** — a lone CR breaks a line for AppKit too.
- **testCrlfBecomesOneSpaceNotTwo** — the pair is one break.
- **testBlankLineBetweenParagraphsBecomesOneSpace** — `"a\n\n\nb"` → `"a b"`.
- **testVerticalTabAndFormFeedAreFlattened** — the other two C0 breaks.
- **testNextLineAndUnicodeSeparatorsAreFlattened** — U+0085, U+2028, U+2029.

### C. Whitespace around the break
- **testIndentationAfterABreakIsDropped** — the Warp shape: a pasted script's leading indent.
- **testTrailingSpacesBeforeABreakAreDropped** — `"a  \n  b"` → `"a b"`.

### D. Breaks at the edges
- **testLeadingBreakProducesNoSpace** — `"\nTitle"` → `"Title"`.
- **testTrailingBreakProducesNoSpace** — `"Title\n"` → `"Title"`.
- **testATitleOfNothingButBreaksIsEmpty** — `"\n\n"` → `""`.

### E. The measurement this exists for
- **testFlattenedTitleMeasuresOneLineHigh** — the real assertion behind #6010: a multi-line title measured
  through an `NSTextField` cell is several line heights tall, and the flattened one is exactly as tall as a
  plain title. Pins the AppKit behaviour the rest of the file is reasoning about.
