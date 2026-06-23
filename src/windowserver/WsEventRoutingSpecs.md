# WsEventRouting — Specs

## Summary

`WsEventRouting` is the pure decision layer for incoming WindowServer notifications: it decodes a raw
notification id into a known `Notification`, maps each to the model `Action` it implies, and exposes one
fact the dispatcher needs (whether the payload carries a Space id). It
holds no state and does no IPC — `WindowServerEvents` turns these decisions into model mutations. Same
pure-decision-kernel pattern as `SelectionResolver`; it superseded the AX event-routing layer that mapped
AX notifications to these same actions before WindowServer became the source of window state.

## Reverse-engineered id map (the evidence)

Established live on macOS 26 by registering `SLSRegisterConnectionNotifyProc` across a wide id range and
driving each change: 806 moved, 807 resized, 811 created, 804 destroyed, 815/816 ordered-in/out, **808 the
focused/front window changed (confirmed cross-app and intra-app)**, 1325/1326 added/removed-from-Space,
1329 current-Space, 1401 active-Space. Notes that shape the actions:
- **Minimize is not its own event** — minimizing emits 816 (ordered-out), same as hiding; the action is
  `refreshVisibility`, after which `WsWindowState` reads the minimized bit.
- **Space notifications (1325/1326) carry `(spaceId, wid)` in the payload** — membership is free, no query.
- **Created (811) ⇒ `acquireAndDiscriminate`** — the wid may be untracked; we must obtain its AX element
  and run `WindowDiscriminator` before showing it.

## Test scenarios

Mirrors `WsEventRoutingTests.swift` 1:1.

### A. Notification decoding
- **testKnownIdsDecode** — each confirmed id decodes to its `Notification` case.
- **testUnknownIdsAreNil** — heartbeat/other ids (1502, 1503, 1322, 0, 999) decode to nil.

### B. Action mapping
- **testActionForEachNotification** — created→acquireAndDiscriminate, destroyed→remove, moved/resized→updateGeometry, focused→bumpFocusOrder, orderedIn/orderedOut→refreshVisibility, added/removed-Space→updateSpaceMembership, current/active-Space→spaceTransition.

### C. Payload
- **testOnlySpaceMembershipNotificationsCarrySpaceId** — added/removed-from-Space carry a Space id; all others do not.
