# PermissionFlow — Specs

> **Line coverage:** _pending — run `/coverage-explore` to populate_

## Summary

The first-run permissions window used to show both permissions at once, each as a fully expanded
card with its own button, and it closed itself the moment both were granted. Users had no ordering
cue, and the window's only exit was the red close button — which quit the app without saying so.

`PermissionFlow` is the pure kernel that turns the two `PermissionStatus` values into a sequence:

- `liveStep(accessibility:screenRecording:)` — which step the user is on, or `nil` when the window
  is done and should close.
- `state(of:accessibility:screenRecording:)` — how one step's card renders: `.live` (expanded, with
  justification and illustration), `.done` or `.upcoming` (collapsed to a title row).
- `showsWaiveOption(accessibility:screenRecording:)` — whether the bottom bar offers "Continue
  without thumbnails".
- `isComplete(accessibility:screenRecording:)` — nothing left to resolve.
- `offersGrantAfterSkip(_:accessibility:screenRecording:)` — whether a card offers "Grant permission"
  next to its "Skipped" label.
- `primaryAction(accessibility:screenRecording:)` — whether the bar's main button grants or closes.

## Behavior & edge cases

- **Accessibility is step 1, always.** Nothing about AltTab works without it, so it leads and the
  only alternative offered next to it is `Quit AltTab`.
- **Screen Recording is waivable.** `PermissionStatus.skipped` (the user chose "Continue without
  thumbnails", persisted as `screenRecordingPermissionSkipped`) resolves the step exactly like
  `.granted` does — so `liveStep` moves past it and the window closes. The two differ only in the
  status label the card shows, which is the view's business, not the kernel's.
- **`.skipped` never resolves Accessibility**, because nothing sets it: `AccessibilityPermission`
  only ever reports `.granted` or `.notGranted`. A `.skipped` value there would be treated as "not
  granted" (`accessibility != .granted`), which is the safe reading.
- **A step that is neither live nor granted is `.upcoming`, not `.done`.** On first launch with
  nothing granted, Screen Recording renders as a greyed title row even though its own status is the
  same `.notGranted` it would have while live. The difference is entirely positional.
- **Waiving is offered only while Screen Recording is live.** On step 1 the bar has no waive option
  (there is nothing to waive yet), and once the flow completes there is nothing left to waive.
- **The window outlives launch.** At launch it closes by itself once complete. The user can reopen it
  from "Check permissions…", where everything is already resolved, so the main button reads "Close"
  whenever nothing is live, and "Grant permission" otherwise.
- **A skip can be undone.** A skipped Screen Recording card offers "Grant permission" next to its
  "Skipped" label. Using it clears the skip, so the step turns live again and the bar offers to grant
  or to skip once more. Not offered while Accessibility is missing, since that step comes first.
- **Revocation walks the sequence backwards.** If Accessibility is revoked while the window is on
  step 2, `liveStep` returns `.accessibility` again and Screen Recording collapses back to
  `.upcoming`. The window is re-driven from status, never from a stored cursor, so it cannot get
  stuck on a step the user already resolved.

## Scenarios

- `testFreshLaunchStartsOnAccessibility` — nothing granted → live step is Accessibility.
- `testFreshLaunchCollapsesScreenRecordingAsUpcoming` — nothing granted → Screen Recording is `.upcoming`.
- `testFreshLaunchExpandsAccessibilityAsLive` — nothing granted → Accessibility is `.live`.
- `testAccessibilityGrantedMovesToScreenRecording` — Accessibility granted, Screen Recording not → live step is Screen Recording.
- `testGrantedAccessibilityCollapsesAsDone` — Accessibility granted → its card is `.done`.
- `testBothGrantedHasNoLiveStep` — both granted → `liveStep` is nil.
- `testSkippedScreenRecordingHasNoLiveStep` — Accessibility granted, Screen Recording skipped → `liveStep` is nil.
- `testSkippedScreenRecordingIsDone` — skipped resolves the step's card to `.done`.
- `testRevokedAccessibilityReturnsToStepOne` — Accessibility revoked with Screen Recording granted → live step is Accessibility again.
- `testRevokedAccessibilityCollapsesGrantedScreenRecordingAsDone` — that granted second step stays `.done`, not `.upcoming`.
- `testWaiveOfferedOnlyOnScreenRecordingStep` — the waive option shows on step 2 and nowhere else.
- `testWaiveNotOfferedWhenComplete` — both resolved → no waive option.
- `testCompleteOnlyWhenNoLiveStep` — `isComplete` agrees with `liveStep == nil` across the grid.
- `testSkippedScreenRecordingOffersGrant` — Accessibility granted, Screen Recording skipped → its card offers to grant.
- `testOnlySkippedScreenRecordingOffersGrant` — a granted or pending Screen Recording, or the Accessibility card, never offers it.
- `testSkippedScreenRecordingWaitsForAccessibility` — Accessibility missing → the skipped card offers nothing.
- `testPrimaryActionGrantsUntilCompleteThenCloses` — the main button grants while a step is live and closes once complete.

The completed Screen Recording badge uses the same orange as “Skipped” when waived;
allowed permissions retain green checkmarks.

## Deferred permission window

An automatically queued permissions window rechecks current permissions and startup completion
when its main-thread callback executes. It must not appear after permissions are resolved (including
waived Screen Recording), or after startup has completed. Explicitly opening Check permissions
from the menu remains available after startup.

`PermissionStartup` runs this decision in both the app and the regular unit-test target. Tests
control its main-queue actions and permission-check retries without sleeps or macOS prompts.
The start action sets the startup latch before closing the window and continuing launch.

`PermissionStartupTests` covers:

- Missing mandatory or optional permissions still produce a window.
- A grant or waiver before presentation suppresses the old window and eventually starts.
- Grant → revoke → grant with several queued checks starts exactly once.
- Either permission revoked before queued startup requests a fresh check and leaves a window;
  a later grant closes it and starts once.
- Regrant before a pending retry, and a retry after a different check already completed startup.
- Separate permission updates and undoing a Screen Recording waiver before startup.
- An old presentation cannot reopen the startup window after startup, including after revocation;
  post-startup recovery remains a separate path.
- All 216 sequences of three results from the six supported permission combinations. For each,
  explore every runnable next action: the next result, the oldest main-queue callback, or a
  coalesced permission-check retry. This covers 1,616 complete schedules without timers. Once
  queues settle, startup has occurred at most once; otherwise a required permission window is
  visible. Longer grant/revoke bursts and result changes before a notification have focused tests.

These tests enumerate logical callback orderings, not simultaneous memory reads/writes, actual
macOS notification delivery, or every possible length of event sequence. The live permissions
journey covers the app wiring, manual reopening, post-startup revocation, and onboarding.
