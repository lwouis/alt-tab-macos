# MissionControlOverlay — Specs

## Summary

`MissionControlOverlay.gesture` works out which gesture is on screen from the window manager's surfaces.
`MissionControl.overlayState` feeds it the on-screen window list and the display sizes. The result is
the only gesture signal on macOS 27, where the Dock no longer posts the `AXExpose*` notifications.
`Windows.updatesBeforeShowing` aborts a summon while Mission Control or App Exposé is reported, so a false
positive here stops the switcher from appearing at all.

## Behavior & edge cases

- Only surfaces owned by the `WindowManager` process count.
- A shield (level 19) counts only when it is at least as large as one of the screens. The window manager
  keeps a small 66×82 surface at that level, off-screen, while an app window is focused on macOS 27.
  Counting it made every summon abort.
- Shield plus Spaces bar (level 14) is Mission Control. Shield alone is App Exposé.
- With no shield, the Show Desktop overlay (level 18) is Show Desktop.
- A shield with no bounds is not a gesture.

## Test scenarios

Mirrors `MissionControlOverlayTests.swift` 1:1.

- **testNothingUpIsNoGesture** — only a level-0 window-manager surface: no gesture.
- **testFullScreenShieldIsAppExpose** — a screen-sized shield: App Exposé.
- **testShieldWithSpacesBarIsMissionControl** — screen-sized shield plus Spaces bar: Mission Control.
- **testShowDesktopOverlayIsShowDesktop** — a Show Desktop overlay: Show Desktop.
- **testSmallSurfaceAtShieldLevelIsNotAGesture** — the observed 66×82 off-screen surface at level 19: no gesture.
- **testShieldMatchesAnyScreenSize** — a shield the size of the second, smaller screen: App Exposé.
- **testOtherOwnersAtShieldLevelAreIgnored** — a screen-sized level-19 window of another app: no gesture.
- **testShieldWithoutBoundsIsNotAGesture** — a shield whose bounds are missing: no gesture.
