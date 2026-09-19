# What may move the window order — Specs

One engine decides which window the user is looking at: `AttentionModel`, fed by `AttentionDriver`, driven by
`AttentionEngine`. There is no second engine, no mode, and no runtime switch.

The order is where the rule is enforced, but it binds every statement AltTab makes about where the user is:
the drawn list, which tile is preselected, what a tile says. Reading it as "the stored order only" is what
lets AltTab's own request back in through some other surface.

## The whole system, in one place

    NSWorkspace activation ─┐
    kAXFocusedWindow reads ─┴─→ TrackedWindowStateBridge.dispatch ─→ AttentionEngine.dispatched ─┐
                                                                                                 │
    the app's AXObserver ─→ AxObserverRegistry ─→ AttentionEngine.axSemanticFocus (60ms settle) ─┤
                                                                                                 │
    the click (type 13) ──→ WindowAttentionEvents ─→ AttentionEngine.directedAttention ──────────┤
                                                                                                 ▼
                                             AttentionDriver.translate ─→ AttentionModel.reduce
                                                                                                 │
                                          .front(target) ─→ ReducerInput.attentionCommitted ──────┘
                                                                     │
                                            WindowEventReducer.applyFocusAndBump ─→ the order

    WindowServer destroy / confirmed-dead ─→ windowInvalidated ─→ erase matching cached fact only

- **`AttentionModel`** is the pure kernel and holds the two levels (`AttentionModelSpecs.md`).
- **`AttentionDriver`** translates the reducer's vocabulary into the model's, and allocates arrival
  sequences (`AttentionDriverSpecs.md`).
- **`AttentionEngine`** is the impure shell: process generations, the per-process settle, the commit.
- **`TrackingTelemetryRecorder`** only observes. Switching it off cannot change what AltTab does.

The model also exposes a read-only current user context for downstream UX: unknown, front application only,
or exact represented window. Active-screen placement, initial selection, fullscreen shortcut protection and
one-window-per-app representation consume this statement. Unknown is never interpreted as “no window”.

## Who may write the order

- **an attention decision** — a click naming its target, or an app answering which of its windows it
  considers focused (including Cmd+`). The only source that may claim the user moved.
- **not AltTab's own switch.** Picking a tile asks the OS to focus a window; the order moves when the OS
  reports that it did (the activation, then the app's answer or the read made after the focus operation).
  A focus that did not take would otherwise leave the order claiming a window the user never reached, and
  nothing corrects that: the app that kept focus emits nothing (#6055,
  `testAFocusThatDidNotTakeLeavesTheFrontAlone`). The activation it provokes is not a way back in either: it
  names an app, and that app's cached answer is about the window being LEFT, so while AltTab is still
  awaiting the read it made after the operation, the activation moves nothing and the read is what moves it.
  An app that never answers that read therefore keeps the last confirmed front, which is the degradation
  boundary below rather than an exception to it.
- **a structural repair** — the front window closed and something has to take its place, or a tab group
  changed which member it draws. Not a claim about the user at all.

Nothing else. `WindowEventReducer.applyFocusAndBump` is the only function that writes `focusedAt`, and it
takes an `AttentionWriteSource` naming which of the two entitled it. In particular the WindowServer's order
and focus family (808/815/816) cannot move the order: measured across twelve scenarios, it never names a
window accessibility had not already named, it always names it later, and on an activation it fires once per
on-Space window, which is a set rather than an answer.

## What physical events keep

Visibility, geometry, Space membership, phantom verdicts, discovery and invalidation remain physical-plane
work. Tab membership is necessarily composite: no observed API publishes a complete membership set, and a
focused/main-window notification only names the selected window. AXTabGroup/title reads provide semantic
membership where apps expose it; WindowServer Space handovers and geometry cover fullscreen, inactive and
unresponsive cases. The AX focused/main signal may select the representative of a group already known by
those mechanisms, but cannot by itself create or dissolve that group.

## Where the decision lands

Inside the same dispatch that produced it (`TrackedWindowStateBridge.dispatch`). A decision deferred to the
next runloop turn would let the switcher draw one frame with the old order first, which is scored
as "right, but late" rather than right.

A decision naming an already-represented window checks its cached process owner before committing; this is
an in-memory comparison, not IPC. One that beat discovery waits for the matching WindowServer row, process
owner and still-live process generation, then creates the same minimal candidate the normal discovery path
would. If the cached owner or row belongs to a different pid, the row is absent, or it fails window
discrimination, the decision is dropped rather than guessed. Concurrent answers for the same unknown wid
share that one row query.

## Degradation boundaries

The engine cannot invent an attention edge it never observed. When an app activation names no window and
accessibility never answers, the order does not move: the last confirmed window keeps the front. That is a
worse-looking but safer answer than guessing from z-order, and it is the central discipline of the design.

A window that never took keys has no attention record at all, so it sorts behind every window with confirmed
focus history.

The type-13 channel makes a cross-app click trackable even when the target app is wedged, including when the
window beat ordinary discovery. There is no equivalent signal for an in-app click inside an already-front,
wedged app: the measurements produced no type-13, AX, WindowServer, or workspace event. That case is
unobservable and cannot be made resilient by another arbitration rule. A programmatic activation of a
wedged app likewise names only its process; the model preserves its last confirmed per-app window.

## Timing bounds

`AttentionSettlePolicy.settle` (60ms) collapses an app's burst of answers to its last one — an app raising
all its windows answers once per window, each answer true, and the run ends where it started (#5974). It is
the only arbitration delay in the attention path. The AX answer's process generation and ingress sequence
are captured before that delay; the timer changes commit time, never evidence order. Thus an exact click
arriving while AX settles remains newer when the timer fires. Widening the settle is not free: it delays
every genuine switch by the same amount, against a measured floor of 219ms for the fastest human action ever captured.
Raises spaced wider than the settle commit separately and #5974's shape returns; the live runs watch that limit
in amber rather than asserting it away.

The factless-activation read has a separate 250ms messaging timeout. It is a blocking-IPC safety bound, not
an arbitration delay: it runs off-main and only when the model has no per-process fact.
