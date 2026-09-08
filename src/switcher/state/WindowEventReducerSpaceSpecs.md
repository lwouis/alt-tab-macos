# WindowEventReducer — Space-transition effects — Specs

## Summary

Pins the SPLIT between the two reactions to a Space switch: `spaceTransitionStarted` (the leading edge of
the 1329/1401 burst) and `spaceChangeSettled` (its trailing edge, 250ms later). Specs + Tests without a
same-named kernel, like `WindowEventReducerPhantom`: the subject is which effects each branch emits, not a
pure function of its own.

Driven through `WindowEventReducer.reduce` directly. The replay harness cannot judge this — it records both
branches' requests into the same `pendingRequests` bucket and swallows `.refreshUi` entirely as display-side,
so a scenario replay sees no difference between the two.

## Why this exists (#5864)

v11.3.1 reacted to a Space switch on the LEADING edge of `NSWorkspace.activeSpaceDidChange`. The WindowServer
migration replaced that with a trailing-only 250ms debounce, so the active Space stayed stale for ~273ms after
every switch (measured live) and a Cmd+Tab inside that window was filtered, sorted and DISCOVERED against the
Space the user had just left. That is not merely a display filter: `Window.init` defaults a new window to
`[Spaces.currentSpaceId]` and the Space-join branch gates promotion on `visibleSpaces`, so a stale active
Space poisons the model exactly while the arriving Space's windows are being reported.

The reaction is therefore split by cost, and the split is what these tests hold in place:

- the topology is **a fact that flips** — one CGS round-trip (p50 0.097ms, measured), valid immediately
  because CGS already answers with the new Space at the first 1329. It goes on the leading edge.
- per-window membership and the WindowServer state re-query are **a state that settles** — they are what the
  transition's window storm is churning, so an early answer is a wrong answer that has to be re-taken. They
  stay on the trailing edge.

**The trap the first test guards.** The leading edge must NOT repaint. `App.refreshOpenUiAfterExternalEvent`
is throttled at 200ms leading-edge, so a repaint fired the instant the Space flips SPENDS that edge, and the
update that actually matters — the semantic focus answer following the Space change — then waits out the
tail. Measured live with the switcher open across a transition: it pushed the MRU
correction from 19ms to 220ms after the summon. It looks free and it is not.

## Scenarios

### A. The leading edge is the topology read, and nothing else

- **testSpaceTransitionStartedEmitsTheTopologyReadAlone** — `.spaceTransitionStarted` emits exactly
  `[.refreshSpacesTopology]`: no repaint (the 200ms-throttle trap above), and none of the settled branch's
  expensive work.
- **testSpaceTransitionStartedTouchesNoWindowState** — the leading edge asks the shell to re-read the
  topology and writes nothing on the model itself, so the state it returns is byte-for-byte the one it got.

### B. The trailing edge keeps the expensive half

- **testSpaceChangeSettledKeepsMembershipAndTheStateRequery** — `.spaceChangeSettled` still emits the
  per-window Space sync, the WindowServer state re-query for every tracked window, the shortcut re-check and
  the repaint. Collapsing the two branches into one would either run this storm-time work early or lose it.

### C. Scope and completion are separate facts

`syncSpacesState` captures the tracked wid list on main, does its Space enumeration plus per-window backfill
off-main, and applies the result when it lands. A window discovered in that gap is in the model but was never
part of the question, so the pass has nothing to say about it unless its Space enumeration happened to list it.
Treating that silence as an answer turned it into a verdict — "CGS places this window nowhere", the strong
phantom signal — and hid a window whose own discovery had just read its Space correctly, until a later pass
happened to cover it. The input carries both the wids in the issue-time scope and the wids for which a query
actually completed. Silence outside the scope and failure inside it both preserve the last membership.

- **testAnAnswerDoesNotWipeAWindowItNeverAskedAbout** — a window outside `queried` keeps its Space and stays
  shown.
- **testAQueriedWindowWhoseDirectQueryFailedKeepsItsLastMembership** — a window inside `queried` but outside
  `answered` keeps its prior Space; attempted is not answered.
- **testAnExplicitEmptyAnswerWipesAQueriedWindow** — a completed `[]` is preserved as an explicit negative,
  turns the window phantom, and feeds the dead-window sweep.
- **testAnAnswerIsAppliedEvenToAWindowItNeverAskedAbout** — the map is built by enumerating every Space, not
  from the queried list, so a window appended mid-flight is usually in it. That answer is applied: skipping is
  for silence, and dropping a fact we hold would leave the window under the current-Space guess its discovery
  fell back on.

### D. An empty Space answer is not evidence on its own

`CGSCopySpacesForWindows` answers a non-NULL **empty** array for a wid CGS has no record of at all (measured
on macOS 26: wid 0, 1, 999999 and UINT32_MAX all answer `[]`). So "this window is on no Space", "there is no
such window" and a read that found nothing arrive as one value, and the strong phantom signal hid the window
on all three, permanently, since nothing re-derives membership afterwards (#5954). `syncSpacesState` now
corroborates the wids it could not place against the WindowServer, which omits a wid it does not know and
reports a non-zero `spaceTypeMask` for one it places, and passes the contradictions to the reducer.

- **testAContradictedEmptyKeepsTheLastKnownMembership** — the WindowServer places a window whose completed
  answer is empty:
  it keeps the last membership CGS itself reported and stays shown. Stale at worst, where the alternatives
  are hiding it with no recovery path or inventing a Space other rules would read as truth.
- **testAPlacedWindowStillTakesItsNewSpace** — a real answer always beats the keep, so a window that genuinely
  changed Space is not frozen at its old one.

### D2. Leaving fullscreen

A window's `isFullscreen` is not a property of the window — it is derived from the **type mask of the Space it
sits on** (`WsWindowState.isFullscreen`, bit `0x20`), and it is refreshed by a WindowServer query, which is a
READ that lands whenever it answers. Leaving fullscreen therefore has a window of time in which the flag is
stale: measured live (2026-09-08, macOS 26, Chrome), the window drops its fullscreen Space, is ordered out,
snaps back to its windowed frame within 50ms, and only rejoins the windowed Space ~516ms later.

For that half second the window is same-app, same-size, Space-less or freshly rejoined, ordered out — and
still flagged fullscreen. Every one of those facts also describes a background TAB of another window of the
app, and the flag is what waives tab grouping's confirmation gate (`TabGroupResolver.geometryGroups` keeps a
cluster with a fullscreen member whole, and folds every member of a single settled Space into one window).
So geometry claims the returning window as a tab of a same-sized neighbour, `isTabbed` drops its tile, and
nothing re-splits an established group: the window is unreachable for the rest of the session.

The Space membership event settles it, because **a fullscreen Space holds exactly one window and its tabs** —
the invariant every Space-based tab decision already rests on. A window joining a Space that another APP's
window genuinely sits on is therefore not on a fullscreen Space, whatever its last snapshot said. Another
app's window is the proof that carries: a same-app neighbour proves nothing (a fullscreen tab switch has the
incoming tab joining the Space its outgoing sibling still holds), and neither does size (a fullscreen window's
background tabs stay frozen at the pre-fullscreen size, so they legitimately differ from their own active).

- **testLeavingFullscreenIsNotFoldedIntoASameSizedSibling** — the live sequence, with a second window of the
  app at the same size and a third window of another app on the windowed Space: the returning window is not
  claimed as a tab and joins no group.

### E. A transition that never commits, and transitions that overlap

Both shapes became reachable when the QA harness learned to synthesize a dock swipe. A commanded
`SLSManagedDisplaySetCurrentSpace` always commits and always finishes before the next one starts, so neither
could be produced before, and neither was pinned.

An **abandoned swipe** — fingers travel below the Dock's commit threshold and lift — fires the transition's
leading edge and then settles on the Space it started from. The WindowServer genuinely begins moving windows
in between, so this is not a no-op at the event layer, only at the answer layer.

- **testATransitionThatNeverCommitsLeavesTheModelWhereItWas** — start, settle, nothing moved: same current
  Space, same visible Spaces, same windows. A model that treated the leading edge as the answer would be
  filtering for a Space the user never reached, and nothing later would correct it.
- **testAnAbandonedTransitionStillRequeries** — the reducer cannot tell an abandoned transition from a
  completed one; only the answer can. So the settled pass asks either way, and the two cases converge on the
  answer rather than on a guess.
- **testOverlappingTransitionsAreIdempotent** — swipes faster than the animation put two leading edges back
  to back with no settle between them. The edge holds no per-transition state, so the second is exactly the
  first.

Both have live counterparts in the QA suite: an abandoned swipe, and three overlapping swipes.

### F. Whole topology snapshots apply in issue order

Space queries run on a concurrent lane. Each receives a `QueryIssueOrder` token before leaving main, and only
the newest issued answer may replace `Spaces` topology. A response cannot become newer merely by reaching
main last. `TrackingTypesTests.testSnapshotAnswersOnlyApplyForTheNewestIssue` pins the fence itself; every
reactive topology read advances it, including the leading edge of a later Space transition.
