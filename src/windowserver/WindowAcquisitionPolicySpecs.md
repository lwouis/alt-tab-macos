# WindowAcquisitionPolicy — Specs

## Summary

`WindowAcquisitionPolicy` distinguishes an ordinary AX miss from the macOS failure where an application's
`kAXWindows` attribute returns application elements. An ordinary miss keeps the existing reject/retry behavior.
The malformed inventory enables a WindowServer-only window until AX recovers.

## Detection boundary

- A returned element with wid `0` and role `AXApplication` is malformed. `kAXWindows` is required to contain
  window elements, and this exact shape is emitted by the poisoned Tahoe accessibility session.
- A normal `AXWindow`, an empty inventory, an unreadable role, or an ordinary wid mismatch is not enough to
  enable the fallback. These are existing per-app/transient cases and continue through the normal routes.
- Detection is per application. A broken app can degrade without changing discovery for healthy apps.
- The degraded candidate must still have a non-zero wid, application level `0`, width over `100`, and height
  over `50`. This mirrors the cheap identity/geometry gates from full discrimination without pretending that
  WindowServer can supply an AX subrole.

## Test scenarios

- **testApplicationElementWithZeroWidIsMalformed** — the poisoned Tahoe shape enables the fallback.
- **testHealthyWindowIsNotMalformed** — a normal AX window keeps full AX discovery.
- **testOrdinaryMissIsNotMalformed** — an empty inventory does not broaden WindowServer filtering.
- **testZeroWidWithoutApplicationRoleIsNotMalformed** — both poison signals must be present.
- **testApplicationRoleWithRealWidIsNotMalformed** — both poison signals must be present.
- **testNormalWindowServerCandidateIsEligibleForFallback** — a normal top-level window can degrade.
- **testFallbackRejectsMissingIdentityChromeAndSmallSurfaces** — the coarse gates remain enforced.
