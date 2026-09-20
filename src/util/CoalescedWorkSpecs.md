# CoalescedWork

Main-thread scheduling adapters with injectable clocks and queues for deterministic tests.

## RepaintCoalescer

A scheduled repaint owns its pending slot until its block runs, even if its deadline has passed. Requests
before execution merge into that repaint. The slot is released before painting so reentrant requests can
schedule the next repaint. A queued repaint rechecks the quiet period when it runs; rearming preserves
ownership of the slot. Timing constants and cost limits are in `SchedulingPolicySpecs.md`.

Attention requests paint immediately, settling the default selection before modifier release can commit
it. They invalidate any queued structural repaint using a generation token; an obsolete callback cannot
clear a newer repaint's pending slot. Requests during the immediate paint observe its measured quiet period.

`CoalescedWorkTests` covers overdue work, a 34-window burst, reentrant repainting after a slow paint,
attention arriving during a 200ms quiet period, obsolete callbacks running before a newer repaint, and
selection identity surviving a window removal before its scheduled repaint.

## BatchCoalescer

An initial request schedules one asynchronous batch without a clock-based delay. Requests before its
start share the batch. Until the read has completed and its result is applied, further requests merge
into one pending set, including requests for new keys. Completing the read schedules that set once.
An empty answer must still call completion. The read must invoke completion exactly once, on main.

WindowServer geometry/state reads and window discovery use separate instances, allowing the two kinds
of work to progress independently while limiting each to one operation in flight. Geometry answers are
applied before scheduling the next batch; sustained geometry notifications cannot invalidate all completed reads.
Order-in/out, destruction, Space-membership, discovery and committed-attention events invalidate only their
windows in the active state-read batch. A removed window is invalidated even when removal happens outside
the reducer (for example, app termination). Invalidated rows cannot update the physical inventory or the
reducer; other rows still apply. The queued follow-up starts with a fresh eligible set, and completion clears
that set so closed windows do not accumulate in the scheduler.
Discovery batches the initial window query and follows bounded parent chains for those results.

Tests cover 1,000 requests during a slow read, progress across successive saturated batches, empty
requests and answers, and requests arriving during result application. They execute the production
schedulers with a manually drained queue; no sleeps or real OS responses are needed. Visibility regression
tests run the production reducer with an old query completing after a newer order-in/out. They also cover
per-window invalidation, eligibility of the next batch, and continued progress during geometry bursts.
