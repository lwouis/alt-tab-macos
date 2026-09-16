# AxObserverHealth — Specs

## Ownership

`AxObserverHealth` is a pure registry and reducer. It models one observer entry for each live PID generation,
classifies subscription outcomes, and emits lifecycle decisions. It neither imports Accessibility APIs nor
infers window focus. The impure registry is responsible for creating one observer/runloop source, applying
decisions, and cancelling the generation synchronously on teardown.

## Capabilities and lifecycle

- The enabled capability set is exactly focused-window changed, main-window changed, title-changed,
  window-created, and element-destroyed. Focused-UI-element changed is deliberately not representable.
- Three capabilities have been added to that set, each because it REPLACES work the app was already doing
  rather than widening the surface:
  - Title-changed replaces AX reads made against every app on every order event, it is a window-level
    notification rather than an element-level stream, and it registered on every app owning user-facing
    windows in the 52-app probe.
  - Element-destroyed is the only prompt signal for the four close shapes the WindowServer cannot report
    (closed while minimized, while the app is hidden, while on another Space, and as a background tab).
    Measured at ~175 ms across 11 real closes in 6 apps, where the WindowServer's order-out covers only the
    on-screen case and its destroy notification arrives 57-231 s later. A delivered destroy suppresses only
    the matching wid's next order-out probe, once and for two seconds; one native window cannot establish a
    permanent capability for an app's unrelated custom windows.
  - Window-created carries what the WindowServer's create cannot: a live element for the window, and that
    element's tab group, read inside the delivery. The payload is retained for a bounded join when ordinary
    discovery has not admitted the surface yet, instead of being discarded and re-read through weaker
    current-Space routes.
- Registering more notifications is close to free: the accessibility handshake with a process is paid by
  whichever notification is registered FIRST (~25 ms), and every further registration on the same observer
  and element costs ~0.1 ms.
- Each notification moves independently through unattempted, subscribing, subscribed, unsupported, or a
  timestamped cooldown. An unsupported or not-implemented notification never removes another capability or
  makes a responsive provider unresponsive.
- Provider lifecycle is distinct from notification capability: unregistered, registering, healthy, degraded,
  unresponsive, recovering, or global permission failure.
- Observer creation is itself modeled as absent, creating, ready, or timestamped cooldown. A transient
  `AXObserverCreate` failure is retried with bounded exponential delay; success resets the consecutive
  creation-failure tier without erasing lifetime diagnostics.
- Diagnostics retain the total and per-capability attempt counts, independent per-capability cannot-complete
  tiers, observer generation, last error, last success/callback, and next retry. A process-wide refusal count is
  the maximum outstanding capability tier. The capability set is derived only from subscribed notifications.

## Error and retry policy

- Success and already-registered subscribe only the attempted notification. Unsupported and not-implemented
  mark only that notification unsupported.
- Cannot-complete marks the PID unresponsive. Each notification has its own bounded exponential short budget;
  subsequent failures enter the sparse tier, which itself doubles from the initial sparse delay up to the
  cooldown and stays there — an app that starts answering again is asked within seconds rather than waiting
  out a flat cooldown. Success or callback for one notification cannot reset another's tier. Expiry makes
  recovery eligible but never declares the provider healthy.
- Invalid UI element and invalid observer invalidate outstanding completion tokens, advance the observer
  generation, preserve known unsupported capabilities, and require a rebuild.
- Invalid argument and generic failure degrade the PID and enter sparse cooldown.
- API-disabled is global. Every existing, newly started, or replacement PID immediately reflects the global
  failure and stops attempting independently until one global permission-restored input starts recovery.
  Live permission restoration recreates every observer; each recreation advances its generation when it
  begins, so stale sources remain invalid.
- Frontmost, new-window, dirty-semantics, wake, unlock, successful AX call, and low-frequency tick are bounded
  recovery triggers. They respect the next retry time except that a real successful AX call proves liveness and
  may recover immediately.

## Window-node end reconciliation

`AXUIElementDestroyed` ends one app-side element generation; it does not by itself end the user-facing
window. The reducer moves the window through `axElementEnded` and joins two separately issued reads:

- a fresh AX lookup can heal the cached element in place;
- WindowServer absence confirms that the physical surface ended;
- a retained surface plus a completed current-Space AX absence confirms a non-tab semantic close;
- tabs require positive evidence: a still-published sibling whose tab bar lost a tab, or no published window
  on a Space the group was on carrying the group's `AXTabGroup` identity any more (a whole-group close, where
  Finder retains the last surface and never destroys it). Other-Space or unknown-Space windows remain
  `replacementPending` because the AX query did not cover them.

The join has a timeout. A found replacement or physical absence can still decide from partial evidence;
every other partial result stays inconclusive rather than turning silence into closure.

## Generation and teardown

- The registry is keyed by PID and therefore cannot hold two observer states for the same process. Starting a
  replacement `ProcessGeneration` synchronously replaces the old entry and reports its cancelled observer
  generation.
- Subscription results and callbacks carry both process and observer generations. Late work from a replaced,
  rebuilt, or torn-down observer is ignored.
- Teardown removes the entry and reports the observer generation to cancel. Reusing the PID begins with fresh
  notification, attempt, retry, and observer-generation state.

## Tests

Tests pin every result classification, independent capability refusal budgets, exponential and sparse retry
boundaries, cooldown/recovery triggers, callback diagnostics, global permission gating including processes
started or replaced during failure, rebuild generation rejection, teardown/PID reuse, and the one-entry-per-PID
invariant. They also pin recoverable observer creation, reset of consecutive creation backoff, per-wid
single-use destroy correlation, and AX-node-end reconciliation against WindowServer scope.
