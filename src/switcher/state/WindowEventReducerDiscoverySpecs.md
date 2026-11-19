# Move-triggered discovery

An untracked surface can be a real window still being prepared, or an auxiliary popup that will never be
switchable. Moving the latter every display frame must not repeatedly enumerate its app's accessibility
windows (#6147). On macOS 27 the reporter's 300×200 nonactivating borderless panel reproduced an
`auxiliarySurface` rejection after almost every frame of a 350ms glide.

The first untracked move reserves discovery immediately. Further moves of that wid within one second
emit nothing, including while discovery is still in flight. Later movement retries with fresh evidence;
there is no timer or permanent rejection cache. Only move-triggered discovery is limited.

`WindowEventReducerDiscoveryTests` pins:

- A rejected popup moving at 60Hz discovers three times in three seconds; in-flight requests have the same cap.
- Creation does not spend the first move, so a 0×0-created window can finish setup. Resize always bypasses
  the cap and re-arms the next move. Ingress preserves a resize even when a later move replaces its payload.
- Focus and order-in bypass the cap, allowing changed semantics to be observed immediately. Later movement
  alone can also discover changed semantics after the second has elapsed.
- Admission clears the entry. Tracked windows always refresh their WindowServer state on geometry events.
- Destroy and create clear the entry before wid reuse. A Space transition clears all entries, ignores
  transient geometry and leaves the first post-transition move eligible.
- Windows have independent entries. Expired entries are removed on the next eligible move, and a hard
  256-entry cap evicts the oldest attempt if destroy events are missing. Eviction only permits an earlier retry.
