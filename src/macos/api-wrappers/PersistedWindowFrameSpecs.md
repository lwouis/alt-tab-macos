# PersistedWindowFrame — Specs

## Summary

`NSWindow.isValidPersistedFrame(_:)` (defined in `HelperExtensionsTestable.swift`) decides whether a
window-frame string that AppKit persisted in `UserDefaults` (key `"NSWindow Frame <name>"`) is safe to
restore. AppKit's `setFrameAutosaveName` / `setFrameUsingName` **immediately apply** that string, and an
out-of-range or non-finite frame makes the apply throw `NSInternalInconsistencyException` and abort the
app (crash `f481d5b0`, `FeedbackWindow`). `setFrameAutosaveNameSafely` calls this predicate and drops a
corrupt value before AppKit ever sees it.

The persisted string is space-separated numbers: the window frame `x y w h`, optionally followed by the
save-time screen frame `x y w h` (so 4 or 8 tokens), with a trailing space. AppKit's own validity rule is
`CGRectContainsRect(CGRectMake(INT_MIN, INT_MIN, INT_MAX-INT_MIN, INT_MAX-INT_MIN), frame)` — i.e. every
edge must stay within `Int32` bounds and be finite. This predicate mirrors that rule exactly.

## Behavior & edge cases

- **At least 4 numeric tokens** are required (the window frame). Fewer → invalid.
- Parsing is C-locale via `Double(Substring)` (period decimal, never comma); `"nan"`/`"inf"` parse to
  non-finite values and are rejected by the `isFinite` check.
- Every token must be **finite** and within **`Int32` bounds** (`Int32.min ... Int32.max`) — this is the
  exact range AppKit's `CGRectContainsRect` enforces; values outside it are what abort the app.
- Width and height must be **non-negative**, and `x + w` / `y + h` must not overflow `Int32.max` (a frame
  whose origin is in range but whose far edge isn't is still rejected).
- Negative origins are **valid** (windows legitimately sit at negative coordinates on a secondary display
  placed left of / below the main one).
- Non-numeric junk tokens are dropped before counting (`compactMap`), so an all-garbage string yields zero
  tokens → invalid.

## Test scenarios

Mirrors `PersistedWindowFrameTests.swift` 1:1.

### A. Valid frames
- **testLiveEightTokenStringWithTrailingSpaceIsValid** — the real on-disk format (`"834 503 380 450 0 0 2048 1121 "`) is accepted, trailing space and all.
- **testFourTokenWindowOnlyFrameIsValid** — a bare `x y w h` (no screen tokens) is accepted.
- **testNegativeOriginIsValid** — a frame at negative coordinates (secondary-display placement) is accepted.
- **testInt32MaxBoundaryIsValid** — a frame whose far edge lands exactly on `Int32.max` is accepted.

### B. Non-finite / out-of-range (the crash cases)
- **testNaNTokenIsInvalid** — a `nan` token is rejected.
- **testInfiniteTokenIsInvalid** — an `inf` token is rejected.
- **testValueBeyondInt32IsInvalid** — a coordinate larger than `Int32.max` is rejected.
- **testFarEdgeOverflowIsInvalid** — an in-range origin with a width that pushes `x + w` past `Int32.max` is rejected.

### C. Malformed strings
- **testNegativeWidthOrHeightIsInvalid** — negative `w`/`h` is rejected.
- **testFewerThanFourTokensIsInvalid** — three tokens is rejected.
- **testAllJunkTokensIsInvalid** — non-numeric tokens yield zero numbers and are rejected.
- **testEmptyStringIsInvalid** — the empty string is rejected.
