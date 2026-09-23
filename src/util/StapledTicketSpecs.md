# StapledTicket — Specs

## Summary

AltTab parks its stapled notarization ticket while it runs and puts it back when it quits. At rest the bundle
is exactly what was downloaded; while it runs, macOS's permission checks skip the ticket.

## Why this exists (#6067)

Each window screenshot makes macOS check three times that AltTab may record the screen. Each check rebuilds
AltTab's code identity from the bundle on disk, and when a ticket is stapled it also extracts that ticket and
registers it with the system again. Measured on macOS 27 (M5): ~10ms of a 30ms check at rest; 45ms vs 19ms
per check during a 43-window refresh, which took 5.5s stapled and 2.9s with the ticket parked. The checks are
serialized in the OS, so this sets how fast all thumbnails can refresh.

The ticket itself only serves Gatekeeper's first look at a downloaded copy, and Gatekeeper has already let
AltTab run by the time this code executes. The ticket lives at `Contents/CodeResources`, outside the
signature's seal, so moving it changes no code signature: the Screen Recording grant, the Keychain license
items and Gatekeeper's record of the app are all untouched.

## Where it is parked

`Contents/Resources/en.lproj/locversion.plist`. The signature's resource rules omit that path, so the bundle
stays valid with the ticket there (checked with `codesign --verify --deep --strict` and `spctl`). Any other new
name in the bundle breaks the seal, after which macOS no longer matches AltTab to its Screen Recording grant
and asks again. `.DS_Store` is omitted too, but Finder writes that name. A new `.lproj` folder would read as a
new language.

## When

- **Park**: at launch, right after the "Move to Applications" prompt, which may copy the bundle and relaunch.
  Off the main thread.
- **Restore**: at quit, after in-flight captures are drained, on the normal quit path and on the emergency
  exit that follows a signal.

## Scenarios

- **testParkMovesTheTicketToTheUnsealedPath** — the release shape: the ticket moves, bytes intact.
- **testRestorePutsTheTicketBackWhereStaplerPutIt** — the round trip leaves the bundle as downloaded.
- **testABundleWithoutTicketHasNothingToDo** — debug and QA builds are not notarized; nothing moves and
  nothing is reported as a failure.
- **testParkNeverCreatesTheLanguageFolder** — without `en.lproj` the ticket stays stapled.
- **testParkNeverOverwritesAFileAlreadyAtTheParkingPath** — a real `locversion.plist` is never replaced.
- **testRestoreIgnoresAFileThatIsNotATicket** — only a file starting with the ticket magic `s8ch` moves.
- **testRestoreNeverOverwritesAStapledTicket** — with both present, nothing moves.
- **testATicketLeftParkedByACrashIsRestoredAtTheNextQuit** — a crash skips the restore; the next launch has
  nothing to park and the next quit restores it.
- **testAReadOnlyBundleKeepsItsTicketStapled** — an install AltTab cannot write to keeps its ticket.

## Edge cases

- **The app copied while it runs**, e.g. to another Mac: the copy carries the ticket parked. If it arrives
  quarantined, Gatekeeper fetches the ticket online at first launch, so an offline first launch there is
  refused. Re-downloading AltTab fixes it.
- **Updates** (Sparkle, Homebrew) replace the whole bundle, parked ticket included, and the new version brings
  its own ticket.
- **App Management**: macOS lets code signed by the same team modify an app bundle, so AltTab may rename files
  in its own bundle.
