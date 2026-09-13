# KeyRepeatTimer — Specs

## Summary

`KeyRepeatTimerTestable.shouldApplyArtificialRepeat` is the pure decision kernel for the artificial
key-repeat (hold-to-cycle for modifier-only shortcuts). `KeyRepeatTimer` owns the `DispatchSource`
timer; on each tick it asks this kernel whether the tick should actually advance the selection.

The artificial repeat exists because a modifier-only shortcut (e.g. ⌥⇥ where ⇥ has no keycode of its
own once ⌥ is the hold) gets no OS key-repeat, so AltTab synthesizes one. The timer is armed at
show-invoke time with the user's `InitialKeyRepeat` delay + `KeyRepeat` rate.

## The problem it guards (why gate on visibility)

When the user summons the switcher right after a fullscreen/Space transition, the WindowServer is busy
settling the transition and can't paint AltTab's `.canJoinAllSpaces` panel until it finishes — the
panel's pixels can land ~500ms after the timer was armed. The timer's background `DispatchSource`
keeps ticking through that gap; the queued ticks then all fire the instant the panel appears and jump
the selection several tiles, with no input from the user (they'd pressed once and were waiting for the
switcher to show).

So the initial-delay grace must be measured from when the panel was actually **visible**, not from arm
time. A fast, normal summon is unaffected (visible within ~tens of ms of arming).

## The anchor that went missing (live QA, 2026-07-30)

Anchoring only on `SwitcherSession.panelBecameVisibleAt` — our own panel's WindowServer `orderedIn` —
made the fallback the NORMAL path, because that notification never arrives. Order-in is only delivered
for wids in the per-window opt-in set (`WindowServerEvents.wsWindows`, mandatory since Sequoia), and the
panel is not in it. So every tick fell through and hold-to-cycle started at
`armedAt + initialDelay + 1s`: measured **1377ms** against a system `InitialKeyRepeat` of **417ms**, on
every hold, felt by every user. (Carbon hotkeys fire once per press and ignore auto-repeat keyDowns —
verified in the log: 14 auto-repeat keyDowns produced exactly one `state:down` — so the artificial repeat
is the only thing that can advance the selection while the key is held.)

The panel was NOT added to the opt-in set to fix this: that would feed our own panel's order/geometry
events into the reducer as inputs for an untracked wid, which is a real risk for a timing nicety.
Instead `TilesPanel.show()` sets `SwitcherSession.panelShownAt` as it orders the panel front — an anchor
that cannot go missing. It is slightly EARLY (the WindowServer paints after the order-front returns), so
the visible signal stays above it as the correction rather than replacing it, and the tradeoff is stated
plainly: on a genuinely slow show the grace now starts at the order-front instead of at the paint, which
can let ONE advance land early. That is the price of not being a second late on every ordinary summon.

## The stall AFTER the show (#5977)

The visibility anchor covers a stall BEFORE the panel is presented. A stall after it does the same damage,
and the anchor cannot see it: `panelShownAt` is set as the panel is ordered front, while the expensive part
of a summon (thumbnails for every window, the discovery and Space passes an idle app has to redo cold) runs
after. Reported live as: the first alt-tab after 5-10 idle minutes opens with the selection ~8 tiles into the
list instead of on the previous window, whatever the list length — a count set by elapsed time and the repeat
rate, not by the window set.

Two things made a backlog possible:

- the timer fired on a **repeating** schedule, on its own background queue, so a busy main thread piled up one
  queued block per missed interval;
- the key-up that stops the timer is an **event source**, and the run loop drains the whole main dispatch
  queue before it reads the next event. The backlog is therefore always applied BEFORE the release that
  cancels it, and each block re-checked `now`, which by then satisfied the grace.

Both are answered:

- the timer is **one-shot and re-arms itself from the handler**, so at most one tick can be in flight and a
  stall delays the next one instead of queueing more. The interval becomes handler-to-handler rather than
  fire-to-fire, which drifts by the cost of one cycle (sub-millisecond against a 33-500ms `KeyRepeat`).
- a tick that **reached the main thread late is refused**, since a tick that waited is not evidence that the
  key is still down.

This was masked until v11.4.4: with no anchor at all, every tick took the `initialDelay + 1s` fallback, which
swallowed backlogs shorter than ~1.4s.

## The rule (tested)

Inputs are `systemUptime` timestamps. `firedAt` is when the timer fired, `now` when the main thread got to it.

1. **the tick is late** — `now - firedAt >= max(repeatRate, 20ms)` → refuse, whatever the anchors say.
2. **an anchor is known** (`panelBecameVisibleAt ?? panelShownAt`) → apply iff `now - anchor >= initialDelay`.
   The WindowServer's visible timestamp wins when present, being the true pixels-on-screen moment; the show
   timestamp is the guaranteed stand-in.
3. **neither known** → hold off, but fall back to arm-relative timing after
   `initialDelay + missedVisibleSignalBudget` (1s), so a missing anchor can never wedge hold-to-cycle
   permanently. A genuine safety net now, rather than the path every tick took.

The late budget is floored at 20ms because `defaults write -g KeyRepeat 0` is legal, and a zero-length budget
would refuse every tick.

---

## Test scenarios

Mirrors `KeyRepeatTimerTests.swift` 1:1.

### A2. The show-time anchor
- **testAppliesFromTheShowAnchorWhenNoWindowServerSignalArrives** — the 1.4s bug: with no WindowServer
  signal the grace runs from `panelShownAt`, not from arm + 1s.
- **testTheWindowServerSignalOverridesTheShowAnchor** — when both are known the visible signal wins, so a
  slow show still can't start the grace early.

### A. Visible timestamp known — gate from visibility
- **testAppliesOnceVisibleForInitialDelay** — visible 0.5s ago, initialDelay 0.4s → applies.
- **testSkipsWhenNotVisibleLongEnough** — visible 0.1s ago, initialDelay 0.4s → skips (the core fix: a
  slow show presented the panel, but the grace hasn't elapsed since it became visible).
- **testAppliesExactlyAtInitialDelayBoundary** — visible exactly initialDelay ago → applies (`>=`).

### B. Visible timestamp unknown — arm-relative fallback
- **testSkipsBeforeFallbackBudgetWhenNeverVisible** — never visible, armed 0.5s ago, initialDelay 0.4s
  → skips (the queued-burst case: repeats due at ~arm+initialDelay are suppressed while the panel still
  isn't up). Fallback only opens at `initialDelay + 1s`.
- **testAppliesAfterFallbackBudgetWhenNeverVisible** — never visible, armed 1.5s ago, initialDelay 0.4s
  → applies (`>= 0.4 + 1`), so a missed visible signal doesn't wedge hold-to-cycle.

### C. The tick reached the main thread late
- **testSkipsATickThatWaitedLongerThanOneRepeatInterval** — #5977: fired 0.6s before it ran, refused.
- **testAppliesATickThatReachedMainPromptly** — the ordinary microsecond hop still cycles.
- **testTheLateBudgetIsOneRepeatInterval** — a slower `KeyRepeat` tolerates a proportionally longer wait.
- **testAZeroRepeatRateStillAppliesPromptTicks** — the 20ms floor keeps `KeyRepeat 0` working.

## Cycling boundaries

By default, holding the shortcut (OS key repeats and the artificial held-shortcut repeats) stops at the first and last
window, so a held key can't overshoot. Individual presses always wrap.

**Keep cycling while holding the shortcut** (Controls > Additional controls, off by default) lets held repeats wrap
too, in both directions and across rows, so holding the shortcut loops through the windows until it is released.
Trackpad navigation passes `allowWrap: false` and keeps its edge stops either way.

The timer still reads macOS `InitialKeyRepeat` and `KeyRepeat` at each start; no faster timer is added. Visibility
gating, late-tick rejection and one-shot rearming stay in effect, so a busy main thread may lower the achieved rate.

Runtime check: with the setting on, hold the shortcut for several laps, then in reverse; releasing must stop
immediately. With it off, holding must stop at the ends. Trackpad swipes stop at the ends in both cases.
