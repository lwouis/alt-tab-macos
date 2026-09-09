# AxTitleNotificationPolicy

Decides whether the title an app just announced is the **window's** title.

## Why it exists

`AxObserverRegistry` subscribes to `kAXTitleChangedNotification` on the **application** element, so the
delivery can name any element in the app: a window, a static text, a group, a toolbar. The element is then
asked for its wid, and `_AXUIElementGetWindow` answers with the **containing window's** id for a descendant.

So a wid says *which window the element sits in*. It never says *the element is that window*. Two other
places in AltTab already pay a role read against exactly this fact, before a brute-force scan accepts a
candidate (`BruteForceWindowMatch.isTargetWindowRoot`, #5849) and before a pushed element is adopted as a
window's own (`Applications.applyObservedElement`). The title path is the third.

## What went wrong without it (#6011)

Chromium posts `AXTitleChanged` for nodes inside its window. Their `kAXTitle` is empty, and an empty title
is what `Window.bestEffortTitle` resolves to the **app name**, once the WindowServer has no title either —
which is every window of an app that draws its own title bar.

So the switcher listed a live Chromium window as "Chromium" instead of the page it was showing. It corrected
itself a few summons later, when `TabReadPolicy`'s rolling cursor next re-read that window, and broke again
on the next inner-node rename.

## The rules, in order

1. **The element is not `AXWindow`** → ignore. Not the window renaming itself.
2. **The window answered no title** (`kAXTitle` absent) → ignore. An absent attribute is not an answer.
3. **Otherwise** → apply the string, empty included.

### Why the role is checked before the string

A descendant's title is refused even when it reads perfectly well. A plausible string from the wrong element
is the harder bug to see than an obviously empty one, and there is no string a descendant could carry that
would make it the window.

### Why an empty title from the window IS applied

The window really has no title then. What the user should see in that case is
`Window.bestEffortTitle`'s decision (the WindowServer's title, then the app name), taken in one place for
every path that reads a title, rather than a second opinion here.

## What is deliberately NOT done

An ignored notification is dropped, not turned into a read of the window's own element. A window whose title
really changed announces it on its own element — AppKit posts that edge for any real `NSWindow` — and
chasing every inner node would pay a main hop plus an AX read for the many an app posts that leave the
window's title untouched. If some app ever turns out to announce renames only on descendants, its titles
lean on `TabReadPolicy`'s rolling cursor, and the `axTitle … ignored` debug line names the role it used.

## Test scenarios

### A. The window's own rename
- **testWindowTitleIsApplied** — an `AXWindow` naming a title records that title.
- **testEmptyWindowTitleIsApplied** — an `AXWindow` with an empty title is applied as empty, leaving the
  fallback to `Window.bestEffortTitle`.

### B. Deliveries that say nothing about the window's title
- **testMissingTitleIsIgnored** — the window element answered no `kAXTitle` at all.
- **testEmptyDescendantTitleIsIgnored** — the #6011 shape: a static text inside the window with an empty
  title, which would otherwise relabel the window with the app name.
- **testDescendantWithATitleIsIgnored** — the role decides before the string: a descendant carrying a
  perfectly good title is still not the window.
- **testGroupDescendantIsIgnored** — the same for the `AXGroup` shape Slack and Electron shells present.
- **testUnknownRoleIsIgnored** — an element that would not say what it is proves nothing, so it is refused.
