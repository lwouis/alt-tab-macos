# Window focus events

`makeKeyWindow` posts a synthetic left-mouse-down followed by the matching
left-mouse-up to the target process and window. The pair is sent for every app,
including the repair of a superseded focus request. There are no executable-name,
bundle-ID, title, or version checks.

An unmatched down outside a window's content leaves SDL Cocoa's
`focusClickPending` set. SDL then postpones native relative mouse mode and disables
cursor confinement, although the game can still receive mouse movement. The up
clears that pending state. Once a down is posted, its up must not be skipped when
the user switches again.

Both coordinate fields are kept at a finite off-content point: the global
location at offset `0x10` and window-relative location at `0x20`. Leaving the global
field zeroed makes the record describe a click at the screen origin to clients
that use that field. A NaN location can be sanitized into content by applications
(#5381); points near the frame can hit resize regions (#5900).

The event's window ID is at `0x3c`, the event type at `0x08`, and the required flag
at `0x3a`. The declared length remains `0xf8`; a zero-filled `0x100`-byte allocation
keeps the WindowServer read padding safe. The callback must consume the pointer
synchronously.

`WindowFocusEventTests` checks the down/up sequence, both coordinate fields,
target window, flags, declared length, padding, and byte-for-byte consistency
between the two edges.
