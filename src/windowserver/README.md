# windowserver — the WindowServer-native window model

This layer tracks window state from the **WindowServer (SkyLight/CGS)** instead of the Accessibility
(AX) APIs. It exists because AX is unreliable for busy or AX-lying apps (Electron throwing away its tree,
beach-balling apps) and its per-window observers leak; the WindowServer is authoritative and cheap to
query. See [`project_window_focus_skylight`] and the AX pipeline in `../events/`.

## The boundary (what comes from where)

- **Skeleton + most flesh → WindowServer.** Existence, geometry, z-order/level, Space membership, focus
  order (MRU), minimize, fullscreen, and a CG-grade title all come from SLS events + one batched query.
- **AX, on-demand only (no observers).** Three things have no WindowServer equivalent and stay on AX as
  *reads* at discovery (never subscriptions): **subrole** (discrimination — `WindowDiscriminator` needs the
  precise `AXStandardWindow`/`AXDialog`/… distinctions), **best-effort title** (AX is the user-visible
  source; the WS title can be empty or differ — see `Window.bestEffortTitle`), and **tab detection**
  (`kAXChildren → AXTabGroup`). The AX *actions* (raise/minimize/close/fullscreen) also stay.
- **Accessibility permission is still required** — focusing another app's window is permission-gated
  regardless of AX-vs-SLS. The win here is reliability and no observer churn, not fewer permissions.

## The pieces

| file | kind | role |
|---|---|---|
| `../events/WindowServerEvents.swift` | impure | installs the SLS notify-proc tap; the app's source of window state |
| `WsEventRouting` (triad) | pure | WindowServer notification id → the model action it implies |
| `WsWindowState` (triad) | pure | decode raw SLS fields (attrs/level/spaceMask) → on-screen/fullscreen/app-level |
| `WindowAcquisitionPolicy.swift` | pure | names the two AX-element acquisition routes (current-Space vs other-Space) |
| `WindowServerQuery.swift` | impure | the "one big SLS call": batch-query the WindowServer → `[WsRawWindow]` |

## Why there is no wid → AXUIElement shortcut (and what we do instead)

The AX↔wid bridge is strictly one-directional (`_AXUIElementGetWindow` is element→wid, a Mach MIG call
resolved by the target app; there is no reverse routine, no window-by-id parameterized attribute, and the
remote token carries an opaque app-internal id, not a wid — all RE-confirmed). So an AX element for an
other-Space window can only be obtained by enumerate-and-match (the `_AXUIElementCreateWithRemoteToken`
brute-force). Elements are therefore acquired (by `WindowElementAcquisition`) **lazily, per newly-discovered
wid, and cached** — current-Space via `kAXWindows`, other-Space via a targeted brute-force — instead of the
old every-show exhaustive scan. A window we can't get an element for still shows and is focusable (focus is
wid/psn-based); only minimize/close/fullscreen no-op until it reaches the current Space and self-heals.

## Pure vs impure

Pure kernels are co-located triads (`Foo.swift` + `FooSpecs.md` + `FooTests.swift`), compiled into both the
app and `unit-tests` targets, holding no state and doing no IPC. Impure executors (the tap, the query, the
acquisition) do the IPC and are verified at runtime. Document design in the `Specs.md`, not code comments.
