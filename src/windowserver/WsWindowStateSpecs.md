# WsWindowState — Specs

## Summary

`WsWindowState` is the pure decode of a `WsRawWindow` (the raw fields read from the WindowServer in one
`SLSWindowQueryWindows` batch) into the booleans AltTab's model needs: on-screen (ordered-in), **minimized**,
fullscreen, and an application-window-level hint. The bit and mask constants below were reverse-engineered
live on macOS 26 by diffing the same window across states; the tests pin those exact observed values so a
future macOS that shifts them fails loudly here rather than silently mis-decoding.

## Reverse-engineered constants (the evidence)

- **`attributes & 0x2` = on-screen / ordered-in.** A standard window reads `attributes = 0x3`; the bit drops
  to `0x1` whenever the window orders out — minimize, app-hide, moving to another Space, or a closing window
  mid-teardown all clear it. So this is purely an ordered-in signal (used for capture/visibility decisions),
  **not** a minimized signal — `tags` bit 60 is.
- **`tags & (1 << 60)` = minimized.** `tags` is a SECOND bitfield (`SLSWindowIteratorGetTags`), declared in
  the SkyLight wrapper since the migration but never decoded until 2026-08-04. See the state matrix below
  for the evidence that it is specific rather than merely correlated.
- **`tags & (1 << 39)` = the window's app is hidden.** Not read today (`ApplicationState.isHidden` comes
  from AppKit) but named in `WsWindowState`, because it is the bit that would otherwise be mistaken for
  minimized. Worth knowing: in the mapping run `NSRunningApplication.isHidden` read FALSE while the app was
  genuinely hidden and this bit was set.
- **`spaceTypeMask & 0x20` = on a fullscreen Space.** A window on a normal Space reads mask `0x1`; entering
  fullscreen (which moves it to its own fullscreen Space) flips it to `0x20`.
- **`level == 0` = application window.** Real app windows sit at level 0; chrome does not (floating panels
  3, menu bar 24, Control Center 25, wallpaper/backstop large ±). This is only a coarse hint — it cannot
  distinguish `AXStandardWindow` from `AXDialog`/`AXUnknown`, so discrimination still needs the AX subrole.

## The minimized bit: the state matrix (2026-08-04, macOS 26 / Darwin 25)

One window walked through every state, diffing `tags`. Baseline for a plain windowed window is
`0x0300000100482001`. Verified on TextEdit, Chrome, Finder and an own-process `NSWindow` (the last one built
for the probe, because the two #5714 phantom shapes cannot be produced on demand in someone else's app).

| state | tags | vs baseline |
|---|---|---|
| normal | `0x0300000100482001` | — |
| **minimized** | `0x1300000100480001` | **+60**, −13 |
| app-hidden | `0x0300008100480001` | +39, −13 |
| hidden + minimized | `0x1300008100480001` | +39 **+60**, −13 |
| fullscreen | `0x0300048100082401` | +10 +42, −22 |
| fullscreen + hidden | same as fullscreen | — |
| fullscreen + minimize attempt | unchanged | macOS refuses to minimize a fullscreen window |
| `orderOut:` (#5714 phantom) | `0x0300000100480001` | −13 only, **no bit 60** |
| alpha=0 (#5714 phantom) | unchanged from normal | tags do not see alpha at all |
| background tab, Space-less | `0x0300000100480001` | −13 only, **no bit 60** |
| restored | back to baseline | bit 60 clears — it is not sticky |

**Bit 60 is specific.** Every state that otherwise looks identical from CGS — both #5714 phantom shapes,
app-hidden alone, fullscreen, and a native background tab — leaves it clear. It composes independently with
bit 39. Tab cases were measured on Finder and Terminal `AXTabGroup`s (4 tabs each), not on Chrome, whose tabs
are not native windows: **minimizing a tab group sets bit 60 on every member**, active and background alike,
which is the same fact `mirrorActiveTabStateToInactiveTabs` derives.

**Bit 13 is noise** — cleared by hidden, minimized AND `orderOut:`. It is the on-screen bit already modelled
as `attributes & 0x2`; nothing should be built on it.

**Timing, and the one thing this bit does NOT solve.** It sets ~35ms after a minimize (all three apps) and
the query costs ~100–200µs against the WindowServer, never against the app — which is the whole reason it
replaced `kAXMinimized`, a call into the window's own app that stalls for as long as that app is animating
(~500ms measured, unbounded for a beach-balling one). Live, the order-out's query now flags the window
minimized 11ms after the event, where the AX read took ~500ms.
**But on a Dock RESTORE the bit clears LATE (~644ms), later even than AX** — the window genuinely is still
minimized until the animation ends. So no query is prompt on the way out, and the un-minimize is derived
from the order-in event instead (`WindowEventReducerMinimizeSpecs.md`). Both the reducer's
`windowServerStateRead` and its `movedResizedOrOrderedIn` therefore believe a `true` only while the
WindowServer still says the window is off screen.

**Re-diff on a new major macOS.** These are undocumented bit positions, exactly like the two constants above.

## Test scenarios

Mirrors `WsWindowStateTests.swift` 1:1.

### A. Ordered-in / on-screen (NOT a minimized signal — that is `tags` bit 60, section C)
- **testVisibleWhenAttributeBitSet** — `attributes = 0x3` (observed normal on-screen) → visible.
- **testNotVisibleWhenAttributeBitClear** — `attributes = 0x1` (observed after the window ordered out) → not visible.

### B. Fullscreen
- **testFullscreenWhenSpaceMaskBitSet** — `spaceTypeMask = 0x20` (observed fullscreen) → fullscreen.
- **testNotFullscreenOnNormalSpace** — `spaceTypeMask = 0x1` (observed normal Space) → not fullscreen.

### C. Minimized
- **testMinimizedWhenTagBitSet** — `tags = 0x1300000100480001` (observed minimized) → minimized.
- **testNotMinimizedWhenTagBitClear** — `tags = 0x0300000100482001` (observed normal) → not minimized.
- **testOrderedOutWindowIsNotMinimized** — `tags = 0x0300000100480001`, the observed `orderOut:` / background-tab
  value: ordered out, but NOT minimized. This is the discrimination the whole change rests on (#5714).
- **testFullscreenWindowIsNotMinimized** — `tags = 0x0300048100082401` (observed fullscreen) → not minimized.
- **testHiddenAppsWindowIsNotMinimized** — `tags = 0x0300008100480001` (observed app-hidden) → not minimized.
- **testHiddenAndMinimizedComposes** — `tags = 0x1300008100480001` → minimized, the two bits being independent.
