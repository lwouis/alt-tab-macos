# WindowEventReducer — un-minimize — Specs

## Summary

Covers the un-minimize branch of `WindowEventReducer.movedResizedOrOrderedIn`: a WindowServer order-in (815)
for a window the model believes is minimized clears `isMinimized` and earns the MRU front. Specs + Tests
without a same-named kernel (like `WindowEventReducerFocus`): the subject is a reducer decision, not a pure
function of its own.

## Why this exists

A reporter (2026-08-04, log 09:24:56–09:25:15) unminimized a Chrome window from the Dock and then could not
reach it with quick alt+tabs — each press just toggled between the two OTHER windows. A long press finally
showed the panel and "the queue flashed", adding the window back. Their capture:

    09:25:03.530 windowOrderedOut #30718                      ← minimized
    09:25:03.623 liveness #30718 result=0 verdict=alive         (correctly kept, not a close)
    09:25:03.580 windowFocused #16 | mru bump #16 from=2       ← Chrome focuses its other window
    09:25:06.540 windowOrderedIn #30718                        ← the Dock restore. NOTHING else.
    09:25:07.914 mru bump #30767 Finder from=2                 ← #30718 still holds rank 1

Two defects, one event.

**The flag never cleared.** MEASURED live on 2026-08-04 (macOS 26, `AXPress` on the Dock's
`AXMinimizedWindowDockItem`, 8/8): the Dock press emits the 815 within ~30ms, but the app keeps answering
`kAXMinimized = true` for **~530ms**, and the WindowServer's own `tags` bit for ~644ms — later still. So on
this path NOTHING a query can ask is prompt: the window genuinely is still minimized until the animation
ends. The order-in's follow-up read landed inside that window and wrote the stale `true` straight back, and
nothing re-read it — `manuallyRefreshAllWindows` runs on `windowDidBecomeKey`, i.e. only when the panel
actually SHOWS, which a burst of quick presses never does. Restoring the same window through AX instead does
NOT reproduce it (there the flag flips in ~35ms), which is why every AX-driven test path stayed green.

This is why the un-minimize is derived from the EVENT and not from a better source: moving minimized onto
`WsWindowState.minimizedTag` (which did fix the minimize direction, and the phantom race with it) does not
help here, because that bit is late in this direction too. Both readers therefore apply the same rule — a
`true` is believed only while `carried.offScreen` still holds the wid.

With `showMinimizedWindows == .showAtTheEnd` (the reporter's setting) that stale flag drops the window into
the end bucket: their tile dump shows `#30718` at display index 10 while the `mru bump ... from=N` lines
prove its rank is 2. Under the default `.show` the same staleness is invisible in the ordering, which is
why this went unreported for so long.

**The restore took no front.** When its app was already frontmost the restore emits ONLY the 815 — the same
shape as Cmd+` — and `cameBackOnScreen` swallows the bump. That guard exists for Space re-shows (#5849) and
cannot tell a Dock restore from one. When the app was NOT frontmost the restore activates it and the
attention model uses the app's cached focused-window fact, or requests one bounded read if no fact exists.
That fronts the window a beat later, which is why the bug only bites on a same-app restore.

**And the panel may be OPEN while all this happens** (reported 2026-08-06). Minimizing from the switcher's
"m" shortcut does not close it, so the un-minimize that follows lands on a tile the user is looking at, and
clearing `isMinimized` in the model is only half the job. Nothing else on this event repaints: the WS query
it queues is a no-op (the window comes back to the frame it left, and its late `isMinimized = true` is
rejected the moment the wid leaves `carried.offScreen`), the title read reports no change, and the MRU bump
— the branch's only other `.refreshUi` — is gated on the restored window's app being frontmost, which it
never is while our own panel holds the key window. So the tile kept the minimized indicator until the panel
was closed and reopened. The un-minimize therefore asks for the repaint itself.

**And it asks for no capture — it asks for the captures to WAIT.** The other half of that same "m" press:
the restored window's tile became a mini window floating in transparent pixels. The OS draws a window scaled
down for the whole restore animation (~0.65s, the genie), and the un-minimize is precisely what sets off a
re-capture — the WindowServer geometry query the order-in queues comes back changed and asks for a fresh
screenshot ~200ms in, deep inside the animation. So a correct thumbnail is replaced by a partial frame, and
nothing later corrects it while the panel stays open. The reducer hands the wid to the shell
(`WindowThumbnails.deferCaptureUntilRestoreEnds`), which holds every capture of that window — the ones this
event sets off and anything else asking meanwhile — and takes a single one once the animation is over.

**The rule: an order-in of a window we believe is minimized IS the un-minimize.** A minimized window is
off-screen by definition, and the OS never orders one in for any other reason — a Space re-show brings back
the Space's on-screen windows and leaves its minimized ones minimized. So the event settles it with no
timing at all, and that same `true → false` transition is the one thing that distinguishes a restore from a
Space re-show. The follow-up query still runs; it just no longer gets to contradict the event.

---

## Test scenarios

Mirrors `WindowEventReducerMinimizeTests.swift` 1:1.

### A. The captured sequence

- **testRestoringFromTheDockClearsTheFlag** — the reporter's own steps: after the restore the window is no
  longer minimized. Without the fix it ends `isMinimized=true`, which with `showMinimizedWindows ==
  .showAtTheEnd` renders it at the very back of the list. The ORDER is not asserted: the restored window
  reaches the front when its app says it has focus, not because it was ordered in (seen live).
- **testTheOrderInAloneClearsTheMinimizedFlag** — no follow-up read is replayed, because on this path none
  of them is prompt (AX ~530ms, the WindowServer tag ~644ms). The flag must clear from the event alone, and
  say so in the log.

### B. Clearing the flag moves nothing

- **testABackgroundAppsRestoreClearsTheFlagWithoutStealingTheFront** — an app deminiaturizing one of its own
  windows while another app is frontmost: the flag clears (the window IS back on screen) and the MRU does
  not move. Clearing a state bit is not a claim about where the user is, and the two must stay separable.
- **testASpaceReShowStillDoesNotFrontItsWindows** — the counterfactual that keeps #5849 safe: windows the OS
  re-shows with a Space were never minimized, so the un-minimize path must not touch them. It keys on the
  flag precisely so it cannot widen into this.

### C. Repainting a switcher that is already open

- **testUnMinimizingRepaintsASwitcherThatIsAlreadyOpen** — reported 2026-08-06: minimize with the panel's
  "m" shortcut (the panel stays open), un-minimize, and the tile keeps the minimized indicator until the
  panel is closed and reopened. The state is right; the repaint is missing. Nothing else on this event
  supplies one — see below.
- **testAnOrderInThatIsNotAnUnMinimizeRepaintsNothing** — the counterfactual that keeps it narrow: a Space
  switch orders in every window it brings back, and none of those tiles changed.
- **testUnMinimizingHoldsCapturesUntilTheRestoreAnimationEnds** — the tile's other defect from the same
  press: mid-animation the OS draws the window scaled down, so the re-capture the un-minimize sets off
  returns a mini window in a transparent frame. The wid goes to the shell to be held back.
- **testAnOrderInThatIsNotAnUnMinimizeHoldsNoCapture** — the matching counterfactual: a window merely brought
  back on screen was never scaled down, and holding its captures would only delay a correct screenshot.

### D. The group half

- **testRestoringATabbedWindowClearsTheFlagOnItsInactiveTabs** — inactive tabs mirror their active tab's
  minimized state, so the un-minimize re-derives the group instead of just writing the field. Without the
  `reconcile` the background tabs stay flagged minimized behind a window plainly on screen.

## What no unit test can cover

That the live Dock path emits the 815 at all, and that every queryable source lags it. Both are OS facts;
they were established by measurement (above) and are re-checked live, not here.

### E. The on-screen bit that tab-grouping reads (#5954)

`TrackedWindow.isOrderedIn` is the WindowServer's ordered-in bit, and `TabGroupResolver` reads it to refuse
folding a window the OS still shows (an on-screen window is nobody's background tab — a real background tab
is ordered OUT, measured). The kernel rule has its own tests; these pin the PLUMBING, because every line
carrying the bit from the OS to the kernel could be deleted with the suite green otherwise.

- **testOrderInSetsTheOnScreenBitAndOrderOutClearsIt** — the 815/816 pair moves it.
- **testAMoveOrResizeLeavesTheOnScreenBitAlone** — a 806/807 shares that reducer branch with `orderedIn:
  false` meaning "not an order-in", and must not be read as "off screen"; entering fullscreen is a resize
  storm, which is precisely when the rule has to hold.
- **testTheWindowServerQueryResyncsTheOnScreenBit** — the batched query corrects a window whose order events
  were missed.
- **testDiscoverySeedsTheOnScreenBit** — seeded from the row discovery already holds, since no order event
  fires for windows that were open before AltTab started.
- **testAnAdoptedInactiveTabIsNeverSeededOnScreen** — except for a known background tab, whose row is stale.
- **testTheKernelProjectionCarriesTheOnScreenBit** — `tabWindow` forwards it, the last link no kernel test
  can check.
