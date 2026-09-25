# WindowAdmissionResolver — Specs

## Product object

AltTab offers switch destinations, not every rectangle WindowServer paints. `PhysicalSurface` owns existence,
geometry, level and parentage. `SemanticSurface` owns AX meaning. `SwitchDestinationDecision` joins them without
giving either source universal authority.

## Rules

1. WID zero is invalid.
2. A WindowServer parent is an exact relationship: represent the parent, regardless of level, size or attention.
3. **Placement gates every surface, on every channel.** A destination sits at the ordinary window level or
   covers the screen, unless AX positively marks it `kAXMain`. Above that level an app puts its HUDs, panels
   and overlays, and no subrole distinguishes them: Chromium describes ChatGPT's dictation strip as a titled
   `AXDialog` and its sidebar as `AXStandardWindow`, the same subroles every ordinary AppKit window carries.
   The gate binds exact attention too, because an app key-focuses its own HUD through `kAXFocusedWindow`
   exactly as a real window does, so gating only discovery would delay the surface by one focus event.
4. Exact attention makes a parentless, admissibly-placed surface a destination even when AX is absent or
   unconventional, but it cannot override an auxiliary subrole or a role that is not a window. It never
   refuses what discovery admits: Emacs 29.4 reports its frames as role `AXTextField` with subrole
   `AXStandardWindow`, and they stay destinations when focused.
5. Floating/system-dialog subroles are auxiliary. AppKit can mark a floating panel `kAXMain`; that does not
   turn the panel into a switch destination.
6. A non-auxiliary AXWindow marked `kAXMain` is a destination.
7. `AXStandardWindow` is a destination. A titled `AXDialog` is a destination; an untitled one remains latent.
8. A substantial, titled AXWindow root is a custom-toolkit destination. This generic rule replaces app-name
   exceptions for Steam, Wine, presentation windows and similar unconventional apps.
9. Size is an acquisition prior, never a rejection gate: level-zero surfaces are inspected even when small,
   substantial surfaces are inspected at every level, and exact attention bypasses the optimization.
10. A result is recomputed whenever semantic evidence is refreshed. No acceptance or rejection is permanent.

## Boundaries

`100×50` is substantial. Native AppKit tabs are logical destinations handled by `TabGroupResolver`; WindowServer
parentage intentionally says nothing about them because both active and background native tabs report parent zero.

## Application boundary

Window admission and application admission use the same evidence without conflating their permissions. Ordinary
discovery still excludes XPC processes unless they are an established user-facing exception. Exact attention may
admit the process which owns that destination; zombie status always rejects it, and so does being the window
manager (`com.apple.WindowManager`), which draws the wallpaper, the Stage Manager strip and the Mission Control
overlays and owns no window a user can switch to. Owning an exact destination does not
grant speculative placeholders: only regular apps get one. An accessory or prohibited process that briefly took
focus (Raycast's palette, CoreServicesUIAgent's Gatekeeper alert) is not an app the user can switch back to.
When WindowServer has already named a positive process id, that id remains the application's identity even if
`NSRunningApplication.processIdentifier` reports `-1` (briefly during lifecycle notifications, or permanently for
Xcode's Device Hub). Discovery without either positive id is ignored.
