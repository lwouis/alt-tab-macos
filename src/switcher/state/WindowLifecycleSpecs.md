# Window lifecycle — Specs

WindowServer owns the physical surface; AX owns the app-side element; neither may silently stand in for the
other. The reducer records `unverified`, `alive`, `axElementEnded`, `replacementPending`, `surfaceEnded`, and
`confirmedClosed` so an element generation ending is separate from a user-facing window ending.

## AX element end

`AXUIElementDestroyed` moves the window to `axElementEnded` and requests reconciliation. A fresh element for
the same wid heals it to `alive`. Independent WindowServer absence, a scoped non-tab AX absence with a retained
surface, a positive tab-count shrink, or a tab group no published window hosts any more may confirm closure.
Unknown, other-Space, and incomplete answers remain `replacementPending`. The join is time-bounded and late
results cannot revive a completed verdict.

## WindowServer surface end

An 804 definitively retires that surface and removes its live `Window`, but keeps a two-second semantic
retirement record containing MRU time, creation order, thumbnail, group membership, and whether it represented
the app's focus. A new wid may inherit those facts only when it belongs to the same process and its AX element
is explicitly equal. A focus that happened after retirement prevents the replacement from stealing the front.

Process exit clears pending AX facts and surface retirements immediately.

## Observability ceiling

If a custom app retains both its AX element and WindowServer surface, posts no meaningful transition, and the
user action was not observed, AltTab cannot know that the user considers the window closed. No provider
priority or extra same-subsystem query can manufacture that fact.

## Tests

- **testWindowServerDestroyRetiresTheSurfaceBeforeRemovingIt**
- **testAxElementEndWaitsForCrossSourceReconciliation**
- **testAxReplacementHealsWhileConfirmedCloseRemoves**
- AX reconciliation policy cases live in `AxObserverHealthTests`.

## Device Hub focus

Device Hub (`com.apple.dt.Devices`, macOS 27) can take key focus without raising its window, so an ordinary focus
leaves it hidden behind other windows. Focusing it:

- Requests activation of its running application, then raises the selected AX window, both on the accessibility
  command queue. A minimized window is restored first. Nothing blocks the main thread.
- Dismisses the preview early only when the WindowServer stack confirms the exact window is already frontmost
  (excluding AltTab); otherwise the preview stays until the command completes.
- Reopens Device Hub through LaunchServices only when activation or the raise failed, and only while AltTab or
  Device Hub is still frontmost, so a delayed fallback can't pull it over an app the user switched to.
- A later AltTab focus request cancels queued work, its fallback and its completion. An IPC already sent can't be
  recalled, and activation is advisory, so front-window stacking is a manual verification step.

Local probe (macOS 27.0): activate plus raise moved the existing Device Hub window to the front in four of four
trials, returning in 25 to 42ms; reopening alone took 86ms.
