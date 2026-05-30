# SidebarList — Specs

## Summary

`SidebarListRow` is the recycled row widget for the shortcut sidebar (ControlsTab) — title, optional
summary, optional **Pro** badge. Because rows are reused across refreshes rather than rebuilt, the
badge mutators must be safe to call repeatedly on the same row.

## Behavior & edge cases

- `setProBadge(true)` is idempotent: calling it again on a row that already shows the badge adds
  nothing. (The badge lives in a wrapper view inside the title row; a non-idempotent implementation
  leaves empty wrappers behind, and their accumulated spacing truncates the title — the bug this
  pins.)
- `setProBadge(false)` removes the whole wrapper, returning the row to its no-badge view count — not
  just the badge while orphaning the wrapper.

## Test scenarios

Mirrors `SidebarListTests.swift` 1:1.

- **testSetProBadgeDoesNotAccumulateWrappers** — repeated `setProBadge(true)` adds no views and leaves exactly one badge.
- **testSetProBadgeAddsThenFullyRemovesBadge** — `setProBadge(true)` then `setProBadge(false)` returns to the original view count with no badge.
