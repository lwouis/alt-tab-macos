# WindowEventReducer — what may move the window order — Specs

## Summary

Two things, and only two, move MRU slot 0 inside the reducer: a decision from `AttentionModel` arriving as
`.attentionCommitted`, and a structural repair. `window-tracking/AttentionOrderSpecs.md` states the same rule
for the whole app; this covers the reducer's half of it. Everything the WindowServer says about order and
focus is kept for what it is authoritative about — a window exists, is on screen, moved, changed Space — and is
refused as a statement about the user.

Specs + Tests without a same-named kernel (like `WindowEventReducerPhantom`): the subject is a set of reducer
decisions, not a pure function of its own. Sequence-shaped scenarios are driven through `TestReducerRunner`;
rule-level ones drive `WindowEventReducer.reduce` directly.

## Why the physical events lost the order

Measured across twelve focus scenarios, all four signal sources on one clock:

- accessibility names the window in 10 of 12 and is the earliest window-naming source in 8, including the
  Space-switch follow-up and every healthy in-app case
- the WindowServer is never the best source in any scenario where anything else speaks, and has no exclusive
  scenario at all
- on an activation it fires once per on-Space window, which is a set rather than an answer
- on an in-app raise it emits no 808 at all, and its 815 trails the app's own notification by 0.5-4ms

So every rule that read an 808 or an 815 as "the user went here" was reconstructing, later and less reliably,
something the app had already said. All of them are gone rather than gated: there is one engine, no mode and
no runtime switch.

## The removal repair (#5346)

**macOS never moves focus to another app because a window closed.** When the removed window held slot 0, the
front goes to the frontmost app's own next window, not to the global runner-up. The reporter's REAPER window
stopped moving in the switcher because closing a dialog handed slot 0 to a Finder window they had left
minutes ago, and nothing afterwards corrected it: re-focusing the already-focused window of the
already-frontmost app emits nothing at all.

---

## Test scenarios

Mirrors `WindowEventReducerFocusTests.swift` 1:1.

### A. The front of the MRU after a removal (#5346)

- **testRemovingTheFocusedWindowPromotesTheFrontmostAppsNextWindow** — another app holds slot 1; the
  frontmost app's own next window is promoted over it, and `.applyFocus` names it.
- **testRemovingANonFrontWindowPromotesNothing** — a window at slot 2 closes: slot 0 is untouched, so nothing
  is re-fronted and no ordinary close churns the MRU.
- **testRemovingTheFrontmostAppsOnlyWindowPromotesNothing** — with no sibling left, the repair has nothing to
  promote and must not reach into another app.
- **testMinimizedWindowsAreNotPromoted** / **testInactiveTabsAreNotPromoted** — a window the user cannot see
  is not a successor.
- **testMinimizingTheFocusedWindowPromotesTheFrontmostAppsNextWindow** — minimizing slot 0 is the same
  structural vacancy as removing it. The frontmost app's next visible window takes the slot; a background
  app's minimize cannot trigger this repair.

### B. Nothing physical may move the order

Pinned here rather than left implicit: the WindowServer's order and focus family keeps every physical and
invalidation job it had and loses the one it was never entitled to. This is also why #5936 (a wake or Mission
Control re-showing every window at once) and #5974 (an app raising all of its windows) need no rule of their
own any more — both were bursts of 815s and 808s, and neither event can reach the order at all.

- **testAFocusEventCannotMoveTheOrder** / **testAnOrderInCannotMoveTheOrder** — an 808 and an 815 leave the
  order exactly as they found it.
- **testCommittedAttentionMovesTheOrder** — a decision from `AttentionModel` is what moves it, and it requests
  an immediate repaint so an open switcher does not spend the structural-event throttle before showing it.
- **testCommittedAttentionForAnUnknownWindowIsIgnored** — a decision naming a window nobody tracks is
  dropped, never fabricated into one.
- **testAStructuralRepairStillWrites** — the other writer: not a claim about the user, so it is never gated.

### C. A window being born

- **testAWindowBornInTheBackgroundDoesNotTakeTheFront** — an app finishing its launch behind the user
  is discovered without taking the front from where they are.
- **testABurstOfWindowsBornInTheFrontmostAppDoesNotMoveTheFront** — the same rule when the newcomers
  belong to the app the user is already in, which the frontmost-app test alone cannot catch.

### D. Tabs — the app naming one of its own tabs

- **testNamingABackgroundTabMovesTheGroupRepresentative** — an app answering with one of its background tabs
  moves the tile that stands for it, because that is what the switcher draws.
- **testSemanticFocusCarriesAHeldGroupPastAnAmbiguousPhysicalJoin** — when fullscreen Finder publishes two
  joining surfaces for one tab and the physical handover pairs the wrong one, the semantic focus answer names
  the real destination while the outgoing group is still held. The outgoing tab is already Space-less, so
  its recorded `lastLeftSpaceId` proves the shared Space and carries the whole group to the destination.
- **testSemanticFocusDoesNotCarryAHeldGroupFromAnotherSpace** — a held group whose recorded departure names
  another Space remains separate; timing and app identity alone cannot merge it.
- **testSemanticFocusDoesNotCarryAHeldWindowThatCarriesNoGroup** — the held side must bring tab evidence of
  its own; the hold is not any. A window ENTERING FULLSCREEN is held by accident (it goes Space-less while the
  transition mints its own surfaces, which arms the recent-create hold), and the app then answers the
  activation with its other window on the Space the held one just left — so every other clause passes and two
  SEPARATE windows became one group. Nothing re-splits an established group, so the window that went
  fullscreen stayed hidden for the session (measured 2026-09-09).
- **testSemanticFocusCarriesAHeldWindowLinkedByTheMintedChain** — the second form that evidence takes, for the
  case where no group exists yet: a cmd+T burst mints a wid per tab and hands the membership down
  `pendingGroupInheritance`, so a chain member adopted mid-burst has both wids in one chain. Without it the
  adopted wid stood as a second tile until the burst's last mint was discovered (measured 2026-09-10).
- **testSemanticFocusDoesNotCarryAHeldWindowOutsideTheChain** — a chain naming only the held window is what
  the fullscreen transition arms, so it links nothing and the two windows stay apart.
- **testNamingAWindowInNoGroupJustMovesTheOrder** — the same decision for an ordinary window touches no
  grouping at all.

### E. App Exposé — the re-show around a pick

- **testAnAppExposePickMovesOnlyThePickedWindow** — the pick is a click naming one window, and the re-show
  that puts every window of the app back lands either side of it. Only the picked window may move. The #5936
  mute never covered this: it was armed when Exposé opened, seconds before the pick. Live QA is the
  counterpart.
