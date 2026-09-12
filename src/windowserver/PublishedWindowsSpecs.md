# PublishedWindows — Specs

## Summary

`PublishedWindows` is the pure kernel behind `AXUIElement.windowsIncludingKeyAndMain`, the ONE batched AX
read `WindowElementAcquisition` makes per process before it falls back to `windowsByBruteForce`. It owns two
things: the attribute list that read asks for, and how the three answers fold into one list of window
elements.

## Why the app hides other-Space windows, and where it does not

`-[NSApplication accessibilityWindowsAttribute]` (read off the macOS 26.6.2 disassembly) is:

1. if the app is hidden, enumerate `_hiddenWindows` — no Space involved;
2. otherwise ask the WindowServer
   `windowsWithOptions:0x2a2 onSpaces:(currentManagedSpaces ∪ allUnmanagedSpaces) forConnectionID:<own cid>`,
   and map each returned wid back through `-[NSApplication windowWithWindowNumber:]`;
3. either way, append every `isMiniaturized` window from the app's complete `[self windows]` list;
4. `NSAccessibilityUnignoredChildren`, which is where the AX ids get minted.

So the omission of other-Space windows is not an accessibility policy and nothing in a request can influence
it — not the requester class, not a parameterized attribute, not a bulk hierarchy call, which is why the
~30 candidate reverse brokers surveyed in `window-acquisition/cross-space-reverse-lookup` all failed. It is
step 2's space list, and that is all.

`kAXFocusedWindow` and `kAXMainWindow` do not go through step 2. Each is an `objc_loadWeak` of
`NSApplication._keyWindow` / `._mainWindow`, a `respondsToSelector` check, and a return: no Space query, no
`isVisible` test, no WindowServer call.

The reason this was never noticed is that the public getter it resembles disagrees with it. Measured on the
same build:

```text
after deactivate: active=false keyWindow=nil mainWindow=nil
                  AXFocusedWindow="keyalive fixture" AXMainWindow="keyalive fixture"
```

`-[NSApplication keyWindow]` guards on the app being active and returns nil for a background app; the AX
attribute reads the same ivar unguarded. And with the window moved off-Space:

```text
target wid=115299 spaces=[3] currentSpaces=[4]
kAXWindows      = [115300]                     <- filtered out
AXFocusedWindow = wid=115299 role=AXWindow title="TARGET (moved off-Space)"
```

That is a genuine other-Space `AXWindow` root obtained by one attribute read: no AXUIElementID enumeration,
no cached element from an earlier process, no state change of any kind.

## What it is worth

**One window per app**, since `_keyWindow` and `_mainWindow` are usually the same window and there is no
third ivar. It shrinks the brute-force sweep; it does not replace it. It is free: the same
`AXUIElementCopyMultipleAttributeValues` round trip that already fetched `kAXWindows` fetches all three.

Two more exemptions in the filter above need no code, because they already land in the `kAXWindows` half of
this same read: an other-Space **minimized** window (step 3 is unconditional) and every window of a **hidden**
app (step 1). Neither should ever reach the sweep.

## The rules (tested)

`merge(windows:focused:main:)`:

1. **Order is `kAXWindows` first, then focused, then main**, so the result is deterministic and the
   Space-filtered answer keeps priority when a wid is reachable both ways.
2. **Duplicates are dropped**, keeping first occurrence. `kAXWindows` really does repeat elements (Mail
   starting at login), and focused/main are normally already in it for a current-Space app, so the common
   case must not grow the list at all.
3. **A nil `windows` is "the app did not answer that attribute", not "no windows"** — focused/main still
   count.
4. **An empty `windows` is not an empty answer.** An app with every window on another Space returns `[]`
   there and still names its key window. Returning early on empty is exactly the shortcut that would silently
   delete this whole feature, which is what scenario D exists to catch.

`attributes` must contain all three keys, for the same reason.

---

## Test scenarios

Mirrors `PublishedWindowsTests.swift` 1:1.

### A. The attribute list is the contract
- **testAsksForTheTwoAttributesTheSpaceFilterDoesNotApplyTo** — `attributes` is exactly
  `[kAXWindows, kAXFocusedWindow, kAXMainWindow]`, in that order.

### B. The ordinary current-Space app
- **testKeepsWindowsOrderAndDropsFocusedAndMainAlreadyInIt** — focused and main are members of `kAXWindows`;
  the result is `kAXWindows` unchanged.
- **testDropsDuplicatesWithinWindows** — the Mail-at-login duplicate bug: `[a, a, b]` → `[a, b]`.

### C. The app with a window on another Space
- **testAppendsFocusedWindowMissingFromWindows** — the measured case: `kAXWindows` holds only the
  current-Space window, focused names the off-Space one → both, current-Space first.
- **testAppendsMainWindowMissingFromWindows** — same for `kAXMainWindow`.
- **testAppendsFocusedAndMainOnlyOnceWhenTheyAreTheSameElement** — the usual case where both ivars point at
  one window.
- **testAppendsBothWhenFocusedAndMainDiffer** — a panel is key while a document is main.

### D. The app whose windows are ALL on another Space (the regression guard)
- **testReturnsFocusedWindowWhenWindowsIsEmpty** — `kAXWindows == []`, focused names the off-Space root →
  `[focused]`. Goes red the moment someone reinstates an "empty → return `[]`" shortcut.
- **testReturnsFocusedWindowWhenWindowsIsNil** — the app did not answer `kAXWindows` at all → `[focused]`.

### E. Nothing to report
- **testReturnsEmptyWhenTheAppNamesNothing** — all three nil → `[]`, so the caller falls through to the
  brute-force exactly as before.
