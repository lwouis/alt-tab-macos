# Tracking telemetry

What the tracking pipeline reports about itself: provider health, the click channel's own lifecycle, and the
attention decisions that were committed and refused. It is written after decisions, never before, by a
recorder that owns nothing — the deciding is `AttentionEngine`'s (`AttentionOrderSpecs.md`). Switching
telemetry off cannot change what AltTab does.

Both consumers are CLI: `--qa-state` reads `summary`, `--qa-telemetry` drains the ring.

## Record schema

- every record carries `v`, `seq`, `at` and `kind`; every other field is optional and omitted when unset
- sequence numbers are monotonic and never reused, so a drained batch stitches onto the previous one
- the field set is closed and carries no window title, keystroke or document name

## Ring buffer

- records accumulate until drained
- the ring is bounded; the oldest records are dropped first and `droppedCount` reports the gap
- draining returns the buffered records and empties the ring

## Attention

- a committed decision records the pid, wid, process generation, source, reason code and status
- `source` is the CHANNEL that named the window (`workspace`, `accessibility`, `annotatedSession`),
  so a disagreement is attributable to one of them rather than to "focus" in general
- `lastAttention` always reflects the most recent COMMITTED decision — a refusal is recorded as its own event
  rather than overwriting it, because a reader asking "where does the model think the user is" is not helped
  by the answer it just declined

## AX provider health

- health is tracked per pid, with lifecycle state, observer generation, attempts, capabilities and last error
- an observer generation change is a rebuild: attempts and last error start again
- a process exit drops its entry

## Session tap

- installed/enabled are lifecycle facts; decoded and invalid counts are per event
- an event that failed to decode is counted, never guessed at
