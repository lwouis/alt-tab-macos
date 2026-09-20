# ProcessLiveness — Specs

## Summary

`pid_t.isAlive()` (in `HelperExtensionsTestable.swift`) asks the kernel whether a process exists, via
`kill(pid, 0)`. `RunningApplicationsEvents.debounceThenAddRunningApplications` uses it to decide, 250ms
after a launch was announced, whether the process is still worth tracking. `NSRunningApplication.isTerminated`
can't serve there: it stays `false` for 1-3s after the process is gone, while the `runningApplications`
removal is announced immediately. A dead process admitted through that gap has already had its removal
processed, so nothing ever removes it, and its AX observer is retried every 30s for the rest of the
session (#6051).

## Behavior & edge cases

- Our own process is alive.
- A process that exited and was reaped is not alive.
- A process we may not signal (`EPERM`, e.g. `launchd` as pid 1) is alive: it exists, we just don't own it.
- `-1` (what a terminated `NSRunningApplication` reports as its pid) and `0` are not alive, and are never
  passed to `kill`, since `kill(-1, 0)` probes every process the user owns.
- A zombie (exited, not yet reaped) is alive to the kernel. `isZombie()` is the separate question and is
  what `ApplicationDiscriminator` asks next.

## Test scenarios

Mirrors `ProcessLivenessTests.swift` 1:1.

- **testOwnPidIsAlive** — the test process's pid is alive.
- **testReapedPidIsNotAlive** — a child that ran to completion and was waited on is not alive.
- **testUnsignalableProcessIsAlive** — pid 1 (root-owned, `EPERM`) is alive.
- **testNonPositivePidIsNotAlive** — `-1` and `0` are not alive.
- **testZombieIsAliveButZombie** — a child that exited but wasn't reaped is both alive and a zombie.
