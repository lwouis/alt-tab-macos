# GestureTriggerKernel — Specs

## Summary

`GestureTriggerKernel` is the pure state machine for the trackpad gesture *trigger*: the decision,
taken while the switcher is **closed**, of whether the fingers on the trackpad just performed
AltTab's summon swipe. `GestureTracker` is its bookkeeping — where each finger of the current gesture
started, so travelled distance can be measured.

`TrackpadEvents` stays the adapter: it owns the event taps, maps `NSTouch` into `GestureTouch`
values, and applies the outcome (haptics, `showUiOrCycleSelection`, swallowing the event). Once the
switcher is open the kernel is not consulted at all — `NavigationSwipeDetector` handles stepping the
selection, and the kernel's state is left untouched until the session ends.

Distances are fractions of the trackpad surface, the way `NSTouch.normalizedPosition` reports them.

## Why it is extracted (#5137)

"The trackpad gesture stops working, several times a day, and only relaunching AltTab fixes it." The
trigger keeps state that outlives a single gesture, and two pieces of it could hold a value that made
every later swipe fail. Neither is reachable from a live pass, and neither left a trace in the log,
so the only way to hold the behaviour still is to test the state machine directly.

**Root cause — recycled touch identities.** `GestureTracker` keys start positions by
`NSTouch.identity`. From `NSTouch.h`: *"while touch identities may be re-used, they are unique during
the life of the touch"*. Start positions were never removed when a finger left the trackpad, so a
recycled identity inherited an unrelated finger's start position from an earlier gesture, and the
travel measured from it was meaningless — typically large, and typically off the gesture's axis.

**Why it never recovered — the `swipeStillPossible` latch.** Travelling too far across the gesture's
axis cancels the swipe until the fingers are raised (imitating the native Space swipe). That flag is
read by the entry guard *before* anything can recompute it, so it is a latch by design. But nothing
on the "fingers raised" path cleared it: the `fingersDown <= 1` branch reset only the "another gesture
claimed these fingers" flag, and `TrackpadEvents.reset` deliberately skipped the trigger state
("no need to call TriggerSwipeDetector.reset; it does it itself when triggering" — it only does so on
a *successful* trigger). One bogus off-axis measurement therefore killed the gesture permanently.

That combination also explains the reporter's two observations: *"a longer drag would sometimes
work"* (a stale start position offsets the measurement, so extra travel can still clear the
threshold) and *"sometimes it recovers"* (a 2-finger scroll trips the `requiredFingers` mismatch
branch, which was the one path that did reset the trigger).

## Leniency about reusing fingers (found in live testing, 2026-08-17)

Both of these predate the extraction; the pure kernel is just where they became visible and testable.

**A long off-axis wander was forgiven mid-gesture.** Swipe up and down repeatedly, then horizontally,
and the switcher triggered. `swipeStillPossible` is meant to hold until the fingers are raised, but the
"wrong finger count" branch called a reset that cleared it along with the start positions — and that
branch is hit constantly, because a single finger pausing takes `activeTouches.count` off
`requiredFingers`. Split into `rebaseTrigger` (start positions only, for a pause) and `resetTrigger`
(also the verdict, only when the gesture ends).

## Accepted leniency: fewer fingers than wanted do not spend the session

`userHasDoneAnotherGesture` latches only on **more** active fingers than `requiredFingers`, which is
what prevents a 4→3 trigger. The mirror case is deliberately not covered: with a 3-finger gesture, a
2-finger scroll followed by a third finger does trigger the switcher, and the comment that used to sit
here claiming otherwise ("prevents 2->3 trigger") was aspirational.

Widening the condition to `count != requiredFingers` was implemented and **reverted** on 2026-08-17.
It works, but it is not safe on its own: fingers never land on the same event, so a 3-finger gesture
passes through 1 and 2 active fingers on the way in, and a finger pausing mid-swipe drops the count
again. Keeping that from spending the gesture's own session needs a per-configuration travel baseline,
and the whole apparatus buys less than it costs. `testFingersArrivingOneByOneStillTrigger` is the guard
that keeps the simple rule honest.

## Fixes

1. `GestureTracker.prune(toTouchesDown:)` drops start positions for fingers that are no longer on the
   trackpad, called on every event. It keys off the touches that are **down**, not the ones being
   measured, so a finger that pauses for one event keeps its start position.
2. `GestureTracker.isNewGesture` also treats a `.began` touch as a new gesture, rather than inferring
   newness only from whether a start position happens to be on file.
3. Everything that ends a gesture clears **all** trigger state: `fingersDown <= 1` and `reset()` both
   go through the same path. `maxFingersDownDuringTrigger` is cleared with it, since it describes one
   trigger.
4. `TrackpadEvents` logs its two gesture taps being disabled, naming the tap and the cause, the way
   `KeyboardEvents` already does. A dead gesture tap presents identically to this bug from the
   outside, and the log used to be silent about it.

## Decision order (matters — tested)

Per event, while the switcher is closed:

1. **Prune** both trackers to the fingers still down.
2. **`fingersDown <= 1`** — at most one finger is pointer mode, not a gesture. The gesture is over:
   reset everything, ignore. (Guarded so it costs nothing on the many events where state is already
   clean.)
3. **Another gesture claimed these fingers** — if *more* than `requiredFingers` are active and any of
   them has travelled `minSwipeDistance`, the user is doing a system swipe. Latches until the fingers
   are raised, which prevents a 4→3 trigger. Fewer fingers deliberately don't latch; see the section
   above. Ignore.
4. **Wrong finger count** — `activeTouches.count != requiredFingers`: *re-base* the trigger (start
   positions only) and ignore. This branch was the accidental cure for the #5137 latch, and it was also
   forgiving off-axis wanders; it must not clear any verdict about the session.
5. **The swipe itself** — needs `swipeStillPossible`, a gesture already under way (the first frame
   only records start positions), a non-empty set of readable distances, every touch within
   `maxSwipeDistanceInWrongDirection` across the axis, and every touch past `minSwipeDistance` along
   it. Then `.trigger`, and reset so the same gesture can't fire twice.

Constants: `minSwipeDistance` 0.015, `maxSwipeDistanceInWrongDirection` 0.1.

---

## Test scenarios

Mirrors `GestureTriggerKernelTests.swift` 1:1.

### A. `GestureTracker`: an identity means nothing once the finger is up
- **testRecycledIdentityIsNotMistakenForAnOngoingTouch** — record a gesture at 0.5, prune to no
  fingers down, then the same identities come back at 0.1 with no `.began` seen → new gesture, and
  distances measured from 0.1. The root-cause guard; without pruning this reads as the old touches
  still moving and measures −0.4.
- **testStationaryFingerKeepsItsStartPosition** — four fingers land, one goes stationary (still down,
  not active) → not a new gesture, and its start position is still on file when it rejoins.
- **testBeganPhaseAlwaysStartsANewGesture** — a `.began` touch re-bases even with a start position on
  file.
- **testTouchWithUnreadablePositionIsSkippedNotMeasured** — a touch whose `normalizedPosition` threw
  (#5499) contributes no distance.

### B. The `swipeStillPossible` latch (#5137)
- **testOffAxisWanderCancelsTheSwipeForTheRestOfTheGesture** — 0.15 across the axis, then a clean 0.2
  along it → still ignored. The latch is intended *within* a gesture.
- **testCancelledSwipeDoesNotSurviveTheFingersBeingRaised** — cancel, lift all fingers, swipe cleanly
  → triggers. The regression guard.
- **testCancelledSwipeDoesNotSurviveDownToOneFinger** — same, ending the gesture with one finger left
  on the trackpad. This is the frame the pre-fix code reached constantly while clearing only half the
  state.
- **testResetClearsACancelledSwipe** — `reset()` (what `TrackpadEvents.reset` calls when a session
  ends) clears it too; the pre-fix code deliberately skipped it.

### C. Triggering
- **testHorizontalSwipeTriggers** — 0.05 along the axis after landing → `.trigger`.
- **testVerticalSwipeTriggersWhenTheGestureIsVertical** — the axis follows the preference.
- **testSwipeShorterThanTheMinimumDoesNotTrigger** — 0.005 → ignored.
- **testSwipeAlongTheOtherAxisDoesNotTrigger** — vertical travel under a horizontal gesture.
- **testFirstFrameOfAGestureNeverTriggers** — the first frame only records start positions.
- **testThreeFingersDoNotTriggerAFourFingerGesture** — wrong finger count.
- **testThreeFingerGestureTriggersOnThreeFingers** — `requiredFingers` follows the preference.
- **testUnreadablePositionsNeverTrigger** — all positions unreadable → no distances → must not
  trigger on that emptiness (#5499).

### D. Another gesture already claimed these fingers
- **testExtraTravellingFingerBlocksTheTrigger** — five fingers, one travels; a clean four-finger
  swipe after that is still refused.
- **testClaimedFingersAreReleasedWhenTheFingersAreRaised** — raising the fingers clears the claim.

### E. `maxFingersDownDuringTrigger`
- **testMaxFingersDownIsRecordedDuringTheTrigger** — four active fingers plus a resting thumb → 5.
- **testMaxFingersDownIsClearedWhenTheGestureEnds** — it describes one trigger, so a stale value must
  not leak into the next gesture and make the switcher focus a finger too early.

### F. A gesture must not inherit a spent session
- **testOffAxisWanderIsNotForgivenByAFingerPausing** — wander 0.25 off-axis, let one finger pause for
  one event, then swipe cleanly along the axis → still ignored. Reported from live testing; the pause
  used to reset the off-axis cancel.
- **testFingersArrivingOneByOneStillTrigger** — fingers land over several events, so 1 then 2 then 3
  active must not spend the session on the way in. This is what makes "only more fingers than we want
  claim the session" safe, and why the stricter `!=` variant was reverted.
- **testFingerPausingMidSwipeOnlyRestartsTheMeasurement** — the line between the two things a pause may
  do: it re-bases the measurement (so travel must be fresh from there) but never spends the session.
