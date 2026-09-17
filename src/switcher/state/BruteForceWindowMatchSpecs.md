# BruteForceWindowMatch — Specs

## Summary

`BruteForceWindowMatch` is the pure decision kernel for `AXUIElement.windowsByBruteForce`: given one remote
AX element found during the brute-force scan for requested wids, is it a window's ROOT element, or one of
that window's descendants that happens to resolve to the same wid?

The brute-force scan (`bruteForceElements`) walks remote-token AXUIElementIDs and asks each candidate
"do you belong to wid W?" via `_AXUIElementGetWindow`. The trap: that call returns the CONTAINING
window's id for a window's DESCENDANTS too — every button, outline, tab bar, and menu of window W also
answers "W". Those descendants routinely sit at a LOWER AXUIElementID than the window element itself, so
a scan that stopped at the first wid match returned a descendant (role `AXOutline` / `AXGroup` /
`AXTabGroup` / `AXMenuButton`, subrole nil). `WindowAdmissionResolver` then rejected it for lacking a window
subrole, and the window disappeared from the switcher entirely.

That is the #5849 regression: the v11.4 WindowServer migration dropped the old fallback's subrole filter,
so the scan started stopping on descendants. Reporters saw a visible, normal Finder window (owning
element `AXWindow`, but preceded in the scan by an `AXOutline` sharing its wid) vanish, and Telegram's
"Main menu" (`AXMenuButton`) stand in for the real Telegram window.

## The rule (tested)

`isTargetWindowRoot` is true iff BOTH hold:

1. **Owns the target wid** — `candidateWid == targetWid`.
2. **Is the window ROOT** — `candidateRole == kAXWindowRole` ("AXWindow").

Gate on ROLE, not subrole. A real window's subrole is judged downstream by `WindowAdmissionResolver`
(`AXStandardWindow` OR `AXDialog`, plus app-specific carve-outs), and filtering by standard subrole here
would drop apps with nonstandard trees. Role `AXWindow` is the narrowest gate that still lets the scan
skip descendants and land on the root.

`windowsByBruteForce` is the thin impure adapter: it reads the wid first (cheap), reads the role only after
the wid belongs to the remaining target set (so IPC for the role is paid only on requested windows'
descendants), then routes the verdict here. A `false` for a descendant means "keep scanning"; a root removes
that wid from the set, and the traversal stops only when every requested root is found or its budget expires.

## The second rule: WHOSE tab is it? (`isPlausibleInactiveTab`)

The same file also gates the OTHER brute-force scan — `Applications.discoverInactiveTabs`, which hunts an
app's inactive tabs, since no CGS list holds them. That scan is run for ONE window's missing tab titles and
matches candidates on TITLE alone, which cannot tell two windows apart at all: two Finder windows browsing
the same folders each have a tab called "lwouis" (#5785: tab titles are not window titles, and no reliable
tab→window mapping exists).

Captured live (2026-08-01): the scan run for window A adopted a tab of window B. Nothing broke
immediately — a non-representative member is simply hidden — but when the user later switched to that tab it
became the REPRESENTATIVE of A's group, so every real member of A stopped being drawn and A vanished from the
switcher, with the default pick landing past where it had been.

The on-screen gate added for the same collision does not reach this one: an inactive tab of another window is
not on screen either, so it looks exactly like one of ours.

**The caller must source those frames from the WindowServer, not from the tracked window list.** The rule can
only reject what it knows about, and at launch this scan routinely runs before the app's second window has
been tracked: the list is then empty, every candidate sits on top of nothing, and the tabs of a window we had
not seen yet are adopted as the requester's. Two real windows end up in one tab group, the second hidden
inside it and no longer offered (live 2026-08-25: `requester=#52149@(80,600) others=[]`, then two tabs at
(80,80) adopted). The WindowServer's on-screen list is complete from the first scan. Read `requester=`/
`others=` in the scan log before believing this gate did anything.

**A candidate is never its own blocker**, which is why each frame travels with its wid. The inventory can be
LONG as well as short: a row keeps its last-known `visible` bit until a full sweep refreshes it, so a window
ordered out a moment ago is still in it. Merge All Windows orders every absorbed window out at once, and the
candidate's own stale row then sits at the candidate's own frozen frame — the rule read "parked on another
window" off the candidate itself and deferred it to a window that no longer exists, so it was never adopted
and its row was never refreshed. A deadlock: two tabs of a 6-tab merge were lost from the group for good
(live, 2026-09-17), while a cold rescan of the same merge found all six.

`isPlausibleInactiveTab` rejects a candidate that sits **exactly on another of this app's tracked windows**
while not sitting on the requester — a tab is positioned by its parent, so that frame names its parent. The
test is one-sided on purpose. Merge All Windows never converges the absorbed windows' frames (they keep their
own cascade positions, frozen), so demanding a match with the requester would make a merged group's tabs
permanently un-adoptable; those frozen frames sit on top of nothing, so they are waved through. Position only,
not size: a tabbed window's members diverge in size as the tab bar resizes them, the same reason
`TabGroupResolver.framePartitions` keys on position.

---

## Test scenarios

Mirrors `BruteForceWindowMatchTests.swift` 1:1.

### A. The root window element is accepted
- **testAcceptsAxWindowRootForTargetWid** — wid matches, role `AXWindow` → true.

### B. Descendants sharing the wid are skipped (the #5849 regression guard)
- **testSkipsAxOutlineDescendant** — Finder's case: wid matches, role `AXOutline` → false (the scan
  continues to the `AXWindow` that follows it).
- **testSkipsAxMenuButtonDescendant** — Telegram's "Main menu": wid matches, role `AXMenuButton` → false.
- **testSkipsAxGroupDescendant** — Slack's transient `AXGroup`: wid matches, role `AXGroup` → false.
- **testSkipsNilRoleDescendant** — wid matches, role nil → false.

### C. A window element belonging to a DIFFERENT wid is not the target
- **testRejectsAxWindowOfOtherWid** — role `AXWindow` but wid differs → false.
- **testRejectsNilWid** — no owning wid → false.

### D. Scan-order invariant (descendant before root)
- **testScanSelectsRootNotEarlierDescendant** — hodeinavarro's exact rows: candidates
  `[(wid W, AXOutline), (wid W, AXWindow)]`; `firstIndex(isTargetWindowRoot)` selects index 1, proving
  the earlier `AXOutline` no longer wins.

### E. One traversal can collect several target roots
- **testBatchCollectsEveryRequestedRootWithoutAcceptingDescendants** — two target wids have descendants and
  roots interleaved with an unrelated window; one traversal accepts both roots and neither descendant.

### F. Whose tab is it? (`isPlausibleInactiveTab`, the 2026-08-01 cross-window adoption)
- **testAdoptsATabParkedOnTheRequester** — the ordinary case: candidate at the requester's origin → true.
- **testRejectsATabParkedOnAnotherWindowOfTheSameApp** — the captured failure: the scan run for the window at
  y=80 found a candidate sitting exactly on the window at y=600 → false.
- **testAdoptsATabWhoseOwnStaleSurfaceRowIsStillListed** — the candidate's own row is still listed as visible
  at its own frame (the inventory has not caught up with the merge's order-out) → true; matching it would
  defer the tab to itself forever.
- **testAdoptsAMergedTabAtItsOwnFrozenCascadePosition** — Merge All Windows leaves absorbed tabs at their own
  frozen frames, on top of nothing → true (the merged-group cases go red otherwise).
- **testAdoptsATabWhoseSizeDriftedFromItsParent** — same origin, different size → true.
- **testAdoptsWhenTheRequestersFrameIsUnknown** — no evidence to reject on → true.
