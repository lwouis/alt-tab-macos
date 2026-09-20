# WindowSurfaceInventory — Specs

The inventory is the physical WindowServer plane. It retains surfaces which are not switch destinations so
AX tab adoption and parent-surface resolution can still reason about the complete app layout.

## Snapshot ordering

A whole all-Space scan receives its sequence before leaving main. Targeted event/discovery mutations receive
later sequences as they happen. When the full answer lands:

- a newer full snapshot makes the entire older answer stale;
- a row upserted after issue survives even when absent from the older answer;
- a row removed after issue cannot be resurrected by the older answer;
- a process exit fences every row of that pid, including surfaces not yet present in the inventory;
- rows untouched since issue are replaced normally.

Downstream discovery and physical reevaluation consume the rows accepted by this inventory, not the original
snapshot payload. Otherwise a rejected old row could still overwrite the live model after missing the cache.

Window numbers are unique for the login session. Removal tombstones exist to protect against outstanding old
queries, not because numeric reuse is expected.

## Tests

- **testLateFullSnapshotDoesNotEraseANewerTargetedUpsert**
- **testLateFullSnapshotDoesNotResurrectANewerRemoval**
- **testLateFullSnapshotDoesNotRestoreAnExitedProcessMissingFromTheInventory**
- **testOlderFullSnapshotCannotOverwriteANewerFullSnapshot**
- parent traversal stops at missing, cross-process, and cyclic relationships.
- targeted discovery follows at most 32 same-process, acyclic parent rows and keeps the last trustworthy row
  when the next edge is missing, cyclic, or cross-process.
- the private WindowServer iterator accepts only requested, unique rows and cannot advance more times than
  the number of unique requested windows.
