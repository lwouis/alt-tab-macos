# PhantomWindowDetector — Specs

## Summary

`PhantomWindowDetector` decides whether a window is a **phantom** — present in macOS APIs (AX returns it
as a live window with a valid `CGWindowID`) but not something the app means to show the user, so AltTab
shouldn't offer it as a switch target. The pixel content may be absent, black, or anything; that's the
symptom, not the definition. Producers: alpha=0 Outlook reminders (#5170/#5448), `orderOut:` /
`show:false` Electron windows (Codex/Slack #5714, Joplin #5495, Sprig #5496), WeChat/Teams/DingTalk
hidden windows (#5508). Extracted as a pure kernel from `Window` / `Applications` so the "is this a
phantom?" decision is unit-testable without CGS/AX. Full investigation: `PhantomWindowDetection.swift`.

A phantom is read on **two orthogonal CGS axes**:

- **Space assignment** (`cgWindowId.spaces()` → `CGSCopySpacesForWindows(…, .all, …)`) — which Space a
  window *belongs to*. `orderOut:` / `setAlphaValue:0` does **not** un-assign it.
- **On-screen membership** (`CGSCopyWindowsWithOptionsAndTags` with vs. without the `.invisible1/.invisible2`
  bits) — the `inVisibleList` (excludes the invisible tags) vs `inAllList` (includes them) pair.

They're independent, which gives two strengths of phantom:

1. **Strong** — WID missing from *both* CGS lists; CGS evicted it entirely, so `spaceIds` comes back `[]`.
2. **Weak** — WID in `inAllList` but not `inVisibleList`; CGS still tracks it (so `spaceIds` is
   **non-empty**) but tags it invisible. **Non-empty `spaceIds` therefore does not imply visibility.**

## Two entry points

- **`syncVerdict(s, app)`** — synchronous, cheap, runs on every show (`Window.recomputeIsPhantom`). Has
  only local facts, so it can observe only the strong signal. **Monotonic for the weak signal**: it ORs
  the strong signal onto the current `s.isPhantom`, so it may raise the flag but never clears it on a
  non-empty Space. A weak-signal phantom keeps its Space, which this path can't see; clearing there would
  clobber `cgsVerdict`'s verdict on every show and the phantom would reappear on every summon (the #5714
  bug). **Exception — `isTabbed` clears**: AX tab detection is authoritative but lands after a window is
  first seen, so an inactive tab is briefly flagged phantom (empty `spaceIds`, not-yet-known tabbed); once
  AX confirms the tab this path un-flags it (a real phantom is never part of an AXTabGroup). Without it,
  the monotonic OR left inactive tabs stuck phantom and "separate window per tab" showed one per app.
- **`cgsVerdict(s, app, inVisibleList, inAllList, visibleSpaceIds)`** — authoritative, runs ~250ms
  post-show off-main (`Applications.refreshIsPhantom`) with the two CGS lists. Knows both signals; owns
  the full verdict, including clearing. Disambiguation order (first match wins):
  1. minimized / hidden app / tabbed → not a phantom (legitimate; CGS may list none of these in any Space —
     a background tab especially — so they must clear *before* the strong signal or they'd trip it)
  2. not in `inAllList` → **phantom** (strong)
  3. in `inVisibleList` → not a phantom (currently rendered)
  4. non-empty `spaceIds` ∩ `visibleSpaceIds` == ∅ → not a phantom (other-Space window)
  5. else → **phantom** (weak: alpha=0 / `orderOut:` on a visible Space)

## Test scenarios

Mirrors `PhantomWindowDetectorTests.swift` 1:1. Each test starts from an all-permissive baseline window
and flips the knobs it exercises.

### A. syncVerdict (synchronous, assert-only)
- **testEmptySpacesIsPhantom** — no Space + not tabbed/minimized/hidden → flagged phantom (strong signal).
- **testNonEmptySpacesAloneNotRaised** — a window with a Space is not flagged.
- **testNeverClearsAPhantom** — already a phantom + non-empty `spaceIds` → **stays a phantom** (the #5714
  invariant: the synchronous path never clears an authoritative verdict).
- **testTabbedWithEmptySpacesNotRaised** — empty Space but tabbed → not flagged.
- **testTabbedClearsAStalePhantom** — already a phantom + empty Space but now tabbed → **cleared** (the
  inactive-tab regression: AX confirms the tab, so the synchronous path drops the stale verdict).
- **testMinimizedWithEmptySpacesNotRaised** — empty Space but minimized → not flagged.
- **testHiddenAppWithEmptySpacesNotRaised** — empty Space but app hidden → not flagged.

### B. cgsVerdict (authoritative, per-app table)
- **testMissingFromAllListsIsPhantom** — missing from both CGS lists → phantom (strong; Joplin / Sprig).
- **testInVisibleListIsNotPhantom** — in the CGS visible list → not a phantom (currently rendered).
- **testWeakSignalOnVisibleSpaceIsPhantom** — in-all, not-visible, on a visible Space, not
  minimized/hidden/tabbed → phantom (weak; Codex / Slack / Outlook — the #5714 case).
- **testOtherSpaceWindowIsNotPhantom** — in-all, not-visible, Space not among the visible ones → not a phantom.
- **testMinimizedIsNotPhantom** — in-all, not-visible, minimized → not a phantom.
- **testHiddenAppIsNotPhantom** — in-all, not-visible, app hidden → not a phantom.
- **testTabbedIsNotPhantom** — in-all, not-visible, tabbed → not a phantom.
- **testTabbedMissingFromAllListsIsNotPhantom** — tabbed but missing from *both* CGS lists (the real
  inactive background tab: CGS lists no tab, so its `spaceIds` are sibling-backfilled) → not a phantom.
  Regression for the fullscreen-tab / "separate window per tab" disappearance — the legitimate-window
  exemption must beat the strong signal.
- **testMinimizedMissingFromAllListsIsNotPhantom** — minimized and missing from both CGS lists → not a
  phantom (same exemption: a legitimate window CGS dropped from its per-Space lists).
