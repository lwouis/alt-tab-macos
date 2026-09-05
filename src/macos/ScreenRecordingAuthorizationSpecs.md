# ScreenRecordingAuthorization — Specs

## Summary

The model keeps a valid Screen Recording grant trusted during a short macOS capture-service failure.
It separates a first-use denial from a timeout or a later failure.

## Behavior

- A successful probe changes the state to `granted` and cancels confirmation checks.
- A timeout after a known grant changes the state to `temporarilyUnavailable`.
- The failed check at time 0 schedules non-prompting checks at 10 and 30 seconds.
- A successful confirmation restores `granted` and cancels remaining checks.
- Three failed checks across 30 seconds change the state to `needsUserReview`.
- Only a first-use denial requests the normal onboarding permission window.
- A confirmed failure after a known grant requests only passive review UI.
- ScreenCaptureKit error domain and code data stay in the probe result.

## Test scenarios

- `testPermissionTimeoutAfterKnownGrantIsTemporary`
- `testFirstUseDenialOpensOnboarding`
- `testConfirmedLaterFailureUsesPassiveReview`
- `testRecoveryCancelsConfirmationPeriod`
