# WsWindowState — Specs

## Summary

`WsWindowState` is the pure decode of a `WsRawWindow` (the raw fields read from the WindowServer in one
`SLSWindowQueryWindows` batch) into the booleans AltTab's model needs: on-screen (ordered-in), fullscreen,
and an application-window-level hint. The bit and mask constants below were reverse-engineered live on
macOS 26 by diffing the same window across states; the tests pin those exact observed values so a future
macOS that shifts them fails loudly here rather than silently mis-decoding.

Note: minimized is deliberately NOT decoded here. The WS ordered-out bit (below) conflates minimize with
app-hide / other-Space / closing, so minimized is read from AX (`kAXMinimized`) instead — the reliable,
unambiguous source (same as yabai).

## Reverse-engineered constants (the evidence)

- **`attributes & 0x2` = on-screen / ordered-in.** A standard window reads `attributes = 0x3`; the bit drops
  to `0x1` whenever the window orders out — minimize, app-hide, moving to another Space, or a closing window
  mid-teardown all clear it. So this is purely an ordered-in signal (used for capture/visibility decisions),
  **not** a minimized signal; minimized is read from AX `kAXMinimized`.
- **`spaceTypeMask & 0x20` = on a fullscreen Space.** A window on a normal Space reads mask `0x1`; entering
  fullscreen (which moves it to its own fullscreen Space) flips it to `0x20`.
- **`level == 0` = application window.** Real app windows sit at level 0; chrome does not (floating panels
  3, menu bar 24, Control Center 25, wallpaper/backstop large ±). This is only a coarse hint — it cannot
  distinguish `AXStandardWindow` from `AXDialog`/`AXUnknown`, so discrimination still needs the AX subrole.

## Test scenarios

Mirrors `WsWindowStateTests.swift` 1:1.

### A. Ordered-in / on-screen (NOT a minimized signal — minimized comes from AX kAXMinimized)
- **testVisibleWhenAttributeBitSet** — `attributes = 0x3` (observed normal on-screen) → visible.
- **testNotVisibleWhenAttributeBitClear** — `attributes = 0x1` (observed after the window ordered out) → not visible.

### B. Fullscreen
- **testFullscreenWhenSpaceMaskBitSet** — `spaceTypeMask = 0x20` (observed fullscreen) → fullscreen.
- **testNotFullscreenOnNormalSpace** — `spaceTypeMask = 0x1` (observed normal Space) → not fullscreen.

### C. Application-window level hint
- **testApplicationWindowAtLevelZero** — `level = 0` → application-window level.
- **testChromeAndPanelsAreNotApplicationLevel** — floating panel (3), menu bar (24), Control Center (25), and a large chrome level are all not application-window level.
