@include ./AGENTS.md

# Fix: Escape (cancelShortcut) not closing the overlay

**Bug**: pressing Escape while the AltTab overlay is open does nothing in some conditions.
Issues: #5018, #1835, #44. **Status: FIXED on branch `alkjdla`.**

**Root cause**: `cancelShortcut` is `.local` scope (`NSEvent.addLocalMonitorForEvents`), which
only fires when `TilesPanel` is the key window. macOS can revoke that key status before Escape
is pressed, silently dropping the event. Confirmed via debug log: Cmd+Escape never reached
`handleKeyboardEvent`.

**Fix**: added a second `CGEventTap` (`localShortcutEventTap`) with `.defaultTap` on `keyDown`,
at `.headInsertEventTap`. While `App.appIsBeingUsed`, it calls `handleKeyboardEvent(..., localOnly: true)`,
skipping `scope == .global` shortcuts (already handled by `RegisterEventHotKey` + `KeyRepeatTimer`)
and only intercepting `scope == .local` shortcuts (cancelShortcut etc.).

**Regression fixed**: without `localOnly`, Tab/Cmd+Tab double-triggered `nextWindowShortcut`
alongside the Carbon hotkey handler, causing infinite window cycling.

**Debug**: `bash ai/debug-escape.sh` — kills competing switchers, sets `shortcutStyle=searchOnRelease`,
launches the debug build. Restores settings on exit.

**Details**: `ai/bug-escape-cancel-shortcut.md`
