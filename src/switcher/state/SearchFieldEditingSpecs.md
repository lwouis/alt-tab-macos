# SearchFieldEditing — Specs

## Summary

Typing in the switcher's search field is plain AppKit text editing: `NSSearchField` puts an `NSTextView`
field editor behind its cell, and that field editor already knows how to insert, delete, replace a
selection, handle ⌘A/⌘C/⌘V/⌘X, and walk grapheme clusters. AltTab reimplements none of it.

The one thing AltTab owns is **who has the caret, and where it sits when we take it**. `SearchFieldEditing`
is that rule as a pure kernel; `TilesView` performs it (`makeFirstResponder`, `NSText.selectedRange`).

### Why the rule exists at all

Focus is handed to the field a runloop turn late, so the panel's reveal commits first (#5981 —
activating the text-input context is a synchronous XPC that once timed out for 3.0s). A key can beat that
deferred pass, so `handleKeyboardEvent` calls `giveTheFieldTheCaretNow` on every key routed to the field
(`.passToField`), rather than betting on the race.

Taking the caret has to place it: AppKit hands a text field its **whole content selected** when it becomes
first responder, so without a collapse the first keystroke would wipe what is already typed. The caret goes
to the end of the text, in UTF-16 units (what `selectedRange` counts, so emoji and CJK land correctly).

### The rule

- Search off → do nothing.
- Editing, field does NOT have the caret → take it, collapse the selection to the end of the text.
- Editing, field HAS the caret → **do nothing at all**. Its selection is the user's.

That last line is #6019. Every key-down went through the same call, so the field's selection was reset to
an empty caret at the end before the field ever saw the key: ⌘A then Delete deleted one character instead
of clearing the search, ⌘A then typing appended instead of replacing, and a caret placed mid-text by
clicking jumped back to the end. Making the call a no-op once the field holds the caret fixes all of them
at once, and it is what the method's doc comment already claimed ("a no-op once the field already has it").

## Behavior & edge cases

- **The caret is taken once per focus.** After the first key, the field holds it and later keys leave the
  selection alone; losing it (a tile takes first responder back) re-arms the rule.
- **Selections come from ⌘A and the mouse, not from shift-arrows.** While editing, arrow keys cycle the
  tile selection (`SearchModeResolver.routeKey`), so they never reach the field — with or without Shift.
  A partial selection is made by dragging or double-clicking in the field.
- **IME composing is unaffected**: marked text implies the field is first responder, so the rule is already
  a no-op there. `routeKey` also sends every composing keystroke straight to the field.
- **Empty selection, empty field**: Delete at position 0, forward-delete at the end, and ⌘A on an empty
  field are all no-ops, exactly as in any macOS text field.
- **Grapheme clusters**: one Delete removes a whole emoji, ZWJ sequence, composed accent or CJK character.
  AppKit's doing; pinned here because it's what the user sees.
- **Not modeled here**: mode transitions, key routing and the Pro gate (`SearchModeResolver`); the deferral
  and first-responder calls themselves (`TilesView`); how the resulting text ranks windows (`Search`).

---

## Test scenarios

Mirrors `SearchFieldEditingTests.swift` 1:1. The tests drive a real `NSTextView` field editor through the
same caret rule the production key path applies, so they assert AppKit's editing behavior, not a model of it.

### A. The caret rule
- **testCaretIntentLeavesSelectionAloneWhenSearchIsOff** — search off → nothing to place, either way.
- **testCaretIntentTakesTheCaretWhenTheFieldDoesNotHaveIt** — editing without the caret → take it, collapse to end.
- **testCaretIntentLeavesSelectionAloneOnceTheFieldHasTheCaret** — editing with the caret → hands off (#6019).
- **testEndOfTextIsACollapsedCaretAfterTheLastCharacter** — the placed range is `(length, 0)`, empty text included.

### B. Taking the caret
- **testFirstKeyAfterFocusAppendsInsteadOfReplacing** — the key that beats the deferred focus pass appends; it does not replace the content AppKit handed over selected.
- **testFirstKeyAfterFocusDeletesTheLastCharacterInsteadOfEverything** — same for Delete: one character, not the whole field.
- **testCaretIsTakenOnlyOnTheFirstKey** — later keys find the field already first responder.
- **testCaretIsNotTakenWhenSearchIsOff** — the switcher is cycling tiles; the field is not ours to focus.

### C. Typing
- **testTypingAppendsCharacters** — characters land in order, caret follows.
- **testTypingInsertsAtTheCaretWhenItSitsMidText** — a caret placed by clicking stays put.
- **testTypingReplacesTheSelection** — a full selection is replaced by what is typed.
- **testTypingReplacesAPartialSelectionOnly** — the rest of the query survives.
- **testTypingASpaceIsKeptInTheField** — spaces are ordinary text (the query is trimmed later, by `Search`).

### D. Backspace
- **testBackspaceDeletesTheCharacterBeforeTheCaret** — the plain case.
- **testBackspaceMidTextDeletesOnlyThere** — deletes at the caret, not at the end.
- **testBackspaceAtTheStartDoesNothing** — nothing before the caret.
- **testBackspaceOnAnEmptyFieldDoesNothing** — no text at all.
- **testRepeatedBackspacesEmptyTheField** — and one extra press past empty is harmless.
- **testBackspaceAfterSelectAllClearsTheField** — #6019, the reported sequence: ⌘A then Delete clears the search.
- **testBackspaceDeletesAPartialSelectionAndNothingElse** — a dragged selection is removed whole.
- **testBackspaceOnASelectionDoesNotAlsoEatThePrecedingCharacter** — the character before the selection survives.

### E. Forward delete (fn+Delete)
- **testForwardDeleteRemovesTheCharacterAfterTheCaret** — the plain case.
- **testForwardDeleteAtTheEndDoesNothing** — nothing after the caret.
- **testForwardDeleteAfterSelectAllClearsTheField** — ⌘A then fn+Delete clears too.
- **testForwardDeleteRemovesASelectionInsteadOfOneCharacter** — a selection wins over the next character.

### F. Word and line deletes
- **testOptionBackspaceDeletesThePreviousWord** — ⌥Delete takes the word.
- **testOptionBackspaceTwiceDeletesBothWords** — repeated, it empties the field.
- **testOptionBackspaceOnASelectionDeletesJustTheSelection** — a selection wins over the word before it.
- **testOptionBackspaceAfterSelectAllClearsTheField** — ⌘A then ⌥Delete clears.
- **testOptionForwardDeleteRemovesTheNextWord** — ⌥fn+Delete takes the word ahead.
- **testCommandBackspaceClearsEverythingBeforeTheCaret** — ⌘Delete from the end clears the query.
- **testCommandBackspaceMidTextKeepsWhatIsAfterTheCaret** — from mid-text, only the left side goes.

### G. ⌘A
- **testSelectAllSelectsTheWholeField** — the selection covers the whole content.
- **testSelectAllSurvivesWhenTheFieldOnlyJustTookTheCaret** — ⌘A is itself a key routed to the field; taking the caret on that same key must not eat it.
- **testTypingAfterSelectAllReplacesTheWholeQuery** — retyping a query from scratch, the point of the selection.
- **testSelectAllOnAnEmptyFieldSelectsNothing** — nothing to select, Delete stays a no-op.
- **testClickingAfterSelectAllGoesBackToASingleCharacterDelete** — a click collapses the selection; Delete is one character again.
- **testSelectAllThenSelectAllAgainIsStillTheWholeField** — idempotent.

### H. Caret movement keys
- **testHomeMovesTheCaretToTheStart** — Home, then typing inserts at the front.
- **testEndMovesTheCaretBackToTheEnd** — End returns to the tail.
- **testHomeCollapsesASelection** — moving the caret drops the selection, so Delete deletes nothing at position 0.

### I. Paste
- **testPasteOverASelectionReplacesIt** — ⌘V over ⌘A swaps the query.
- **testPasteAtTheCaretInsertsWithoutLosingText** — pasting appends at the caret.

### J. Non-ASCII text
- **testBackspaceDeletesAWholeEmoji** — one press, one emoji.
- **testBackspaceDeletesAWholeZwjSequence** — a ZWJ family emoji goes as one character.
- **testBackspaceDeletesAComposedAccentAsOneCharacter** — `e` + combining acute is one grapheme.
- **testBackspaceDeletesOneCjkCharacter** — 京都 → 京.
- **testCaretAfterFocusLandsAtTheEndOfNonAsciiText** — the placed caret is in UTF-16 units, so emoji don't shift it.
- **testSelectAllThenBackspaceClearsNonAsciiText** — #6019 holds for mixed scripts.

### K. Longer sessions
- **testTypeCorrectSelectAllAndRetype** — type, fix a typo, ⌘A + retype, ⌘A + Delete, type again: a whole search as it is really used.
- **testTypingResumesAtTheEndAfterTheCaretIsLost** — losing the caret mid-session re-arms the rule, and typing resumes at the end.
