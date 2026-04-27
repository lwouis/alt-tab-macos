@include ./AGENTS.md

# Active investigation: Escape (cancelShortcut) not closing the overlay

**Bug**: pressing Escape while the AltTab overlay is open does nothing in some conditions.
Issues: #5018, #1835, #44.

**Root cause**: `cancelShortcut` is registered as `.local` scope via `NSEvent.addLocalMonitorForEvents`.
This only fires when `TilesPanel` is the key window. Because `TilesPanel` uses `.nonactivatingPanel`,
it doesn't activate the app; `makeKeyAndOrderFront` gives it key focus, but any competing app
(e.g. Contexts.app, which installs its own CGEventTap) can cause the panel to resign key status
before the user presses Escape. When that happens, the local monitor never sees the event.

**Why 'c' works and Escape doesn't**: In `searchOnRelease` / `doNothingOnRelease` shortcut styles,
'c' (`closeWindowShortcut`) is handled the normal `.local` shortcut path too — it has the same
reliability problem. The difference is that the bug most visibly manifests with Escape because
Escape is the *only* way to dismiss the overlay in those modes. `closeWindowShortcut` only comes up
if you're already inside the overlay and pressed a specific key.

**Fix direction**: add a CGEventTap for `.keyDown` events (not just `flagsChanged`) while
`App.appIsBeingUsed == true`, so local shortcuts are intercepted globally rather than relying on
TilesPanel being key. This is how Contexts.app handles it.

**Debug**: `bash ai/debug-escape.sh` — kills Contexts.app, sets `shortcutStyle=searchOnRelease`,
launches the debug build. Restores settings on exit.

**Suggested branch**: `fix/cancel-shortcut-key-window-reliability`
