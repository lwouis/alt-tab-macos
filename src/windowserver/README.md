# windowserver — the physical window plane

This layer tracks the facts the **WindowServer (SkyLight/CGS)** owns. It does not track attention. The split
is deliberate: the WindowServer remains available when an app is wedged and is authoritative for physical
window state, while AppKit is the only component that knows which window inside a process is key. The
attention plane is documented in [`../window-tracking/AttentionOrderSpecs.md`](../window-tracking/AttentionOrderSpecs.md).

## The boundary (what comes from where)

- **Physical plane → WindowServer.** Existence, geometry, z-order/level, Space membership, ordered-in,
  minimize, fullscreen, and a fallback title come from SLS events plus batched queries. Notification 808 is
  an order change, not focus, and cannot move MRU.
- **Semantic plane → one app-level AX observer per process.** Focused/main-window notifications and title
  changes are push signals. There is no observer per window. AX reads remain for discovery-time subrole,
  user-visible title, tab detection, the initial per-app focus seed, and the one factless activation. AX
  actions (raise/minimize/close/fullscreen) also remain. Focused/main selects a known group's representative;
  it does not prove full tab membership, which remains a composite of AXTabGroup reads and physical fallback.
- **Window order → the attention model.** `NSWorkspace` names the front process; AX, the type-13 cross-app
  click, and AltTab's own intent name a window inside a process. Only a committed attention decision or a
  structural repair may write MRU.
- **Accessibility permission is still required** — focusing another app's window is permission-gated
  regardless of AX-vs-SLS. The win here is reliability and no observer churn, not fewer permissions.

## The pieces

| file | kind | role |
|---|---|---|
| `../events/WindowServerEvents.swift` | impure | installs the SLS notify-proc tap; the physical-state source |
| `WsEventRouting` (triad) | pure | WindowServer notification id → the model action it implies |
| `WsWindowState` (triad) | pure | decode raw SLS fields (attrs/level/spaceMask) → on-screen/fullscreen/app-level |
| `WindowAcquisitionPolicy.swift` | pure | names the two AX-element acquisition routes (current-Space vs other-Space) |
| `WindowServerQuery.swift` | impure | the "one big SLS call": batch-query the WindowServer → `[WsRawWindow]` |

## Why there is no wid → AXUIElement shortcut (and what we do instead)

The AX↔wid bridge is strictly one-directional (`_AXUIElementGetWindow` is element→wid, a Mach MIG call
resolved by the target app; there is no reverse routine, no window-by-id parameterized attribute, and the
remote token carries an opaque app-internal id, not a wid — all RE-confirmed). So an AX element for an
other-Space window can generally only be obtained by enumerate-and-match (the
`_AXUIElementCreateWithRemoteToken` brute-force). Elements are therefore acquired lazily and cached. The
periodic inventory groups every missing wid by process: one batched attribute read resolves its current-Space
subset plus the app's key/main window — `kAXFocusedWindow` and `kAXMainWindow` are the two window attributes
AppKit does NOT put behind the Space filter, so they name an other-Space root for free — then one targeted
brute-force shares a 250ms budget across whatever is left. Exact event-driven discovery still asks for one
wid. A window backed only by an exact attention signal plus its WindowServer row can still be shown and
focused; actions needing an AX element self-heal after acquisition succeeds.

There is one route that is not a lookup at all. Every AX notification arrives holding the element of the
window it is about, and nothing in AppKit's posting path consults a Space, so a window `kAXWindows` hides
still hands its element over when the app announces it (measured cross-process).
`Applications.applyObservedElement` adopts that element for a window
that has none, after a role check — a notification may name a descendant, whose wid is its window's. It is a
push, so it only reaches windows that speak: it shrinks the brute-force population rather than replacing it.

## Pure vs impure

Pure kernels are co-located triads (`Foo.swift` + `FooSpecs.md` + `FooTests.swift`), compiled into both the
app and `unit-tests` targets, holding no state and doing no IPC. Impure executors (the tap, the query, the
acquisition) do the IPC and are verified at runtime. Document design in the `Specs.md`, not code comments.
