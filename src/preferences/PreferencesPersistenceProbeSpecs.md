# PreferencesPersistenceProbe — Specs

## Summary

`PreferencesPersistenceProbe` is the pure decision layer behind the launch-time warning that fires when
macOS isn't persisting AltTab's preferences to disk (issue #5790). It takes a list of `SuiteFacts` (the
filesystem state of each `UserDefaults` suite's backing plist, gathered by the `PreferencesPersistenceCheck`
shell) and returns a `Verdict`: `.ok`, or `.broken` naming the offending plist paths. It holds no state and
touches no filesystem — same split as `WsEventRouting` / `DragAndDropResolver`.

## Why a filesystem check, not a write-and-read-back canary

AltTab writes prefs through `cfprefsd`, which caches in memory and defers the disk flush. That makes an
in-process "write a value, read it back" probe useless: the read hits the cache and looks fine even when the
value never reaches disk. `CFPreferencesAppSynchronize`'s success return is documented-unreliable, and a
cross-launch canary can't distinguish a genuine first launch from a broken store without an external marker.
So the only signals that are both observable in one launch AND unambiguous are filesystem conditions on the
plist itself.

## Behavior & edge cases

- **Two definitive break conditions.** A suite is broken when its plist (a) is a symlink, or (b) exists and
  is not writable by us. (a) is the dotfile-sync case (Mackup et al.): cfprefsd won't persist through a
  symlinked preferences file. (b) is the classic `root`-owned plist after a `sudo` launch. Both are directly
  observable, hold across every supported macOS, and are what the user actually hit in #5790.
- **Fail-safe by construction.** The kernel only ever flags those two conditions. An absent plist (normal on
  a fresh install, or transient before cfprefsd first writes), a writable regular file, or any stat failure
  the shell couldn't resolve all map to `.ok`. The bias is deliberately toward NOT warning: a false negative
  is a missed nag; a false positive is a maddening dialog on a healthy machine, so we never risk the latter.
- **Symlink wins over writability.** A symlinked plist is flagged as symlinked and not also probed for
  writability — the link's own permissions are irrelevant, and the fix (stop syncing it) is different from
  the ownership fix. The kernel `continue`s after recording the symlink.
- **Absent is never broken.** `exists == false` short-circuits before either check, regardless of the
  `isWritable` value the shell happened to pass. This is what keeps first-launch users (no plist yet) quiet.
- **All suites in scope, reported separately.** The probe runs over every suite AltTab persists to
  (`standard`/preferences, `.license`, `.usage`). `.broken` carries two path lists so the shell can tailor
  the explanation: symlinked paths get the "un-sync it" advice, unwritable paths get the "fix ownership"
  advice. Either list may be empty, but not both (that would be `.ok`).
