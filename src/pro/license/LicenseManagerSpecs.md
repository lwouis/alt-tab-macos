# LicenseManager — Specs

> **Line coverage:** `LicenseManager.swift` 94.4% (373/395) · `RemoteLicenseClient.swift` 79.4% (189/238), measured 2026-10-21 with the Debug unit-test scheme and code coverage enabled.

## Summary

`LicenseManager` is the single source of truth for whether the user has AltTab **Pro**. It computes a `LicenseState` and notifies observers when it changes. The state drives every Pro gate in the app (search, lock-search, extra shortcuts, App Icons / Titles styles, Auto size, search-on-release) and the Pro-transition prompts.

Its collaborators are injected so the logic is testable without real I/O — the tests pass in mocks (`MockClock`, `MockKeychain`, `MockLicenseAPI`, all defined inline at the bottom of `LicenseManagerTests.swift`):

- **`Clock`** — current time. Lets tests fast-forward the trial without sleeping.
- **`Keychain`** — secure storage for the license key, instance id, and variant id. Tied to the app's code signature (see the License/Keychain invariant in `AGENTS.md`).
- **`LicenseAPI`** — activate / validate / deactivate calls to AltTab's provider-independent licensing backend.
- **`UserDefaults`** — non-secret bookkeeping: `trialStartDate`, `lastValidation` (timestamp), `lastValidationResult` (Bool).

## State model

```
.trialNotStarted       →  .trial(14)      (first usable launch, no existing license)
.trial(daysRemaining)  →  .pro            (user activates a key)
.trial(daysRemaining)  →  .trialExpired   (14 days elapse)
.pro                   →  .trialExpired    (revalidation fails / license invalidated, still in/after trial window)
.pro                   →  .proExpired      (version-limited variant past its cutoff)
```

### Behavior & edge cases (the load-bearing rules)

- **Trial length is 14 days, 0-indexed internally.** Day 0 = first usable launch → `.trial(14)`; day 13 → `.trial(1)`; day 14 → `.trialExpired`. Days remain elapsed 24-hour periods, not calendar boundaries.
- **First usable milestone.** `App.continueAppLaunchAfterPermissionsAreGranted()` calls `onAppBecameUsable` after the switcher panels, keyboard handlers, input observers and preference observers exist, immediately before first-launch onboarding/Settings. Accessibility must still be granted, and Screen Recording must be granted or explicitly waived. The asynchronous window inventory may still be arriving; it does not block switching or this milestone. Merely opening the permission window, granting Accessibility alone, or reading license state cannot start the clock. The first shortcut demonstration and welcome dismissal are not trial-start events.
- **Pre-trial is explicit.** With neither a saved start nor a license, initialization and refresh return `.trialNotStarted`. It grants no runtime Pro actions and is not an expiry: no preference downgrade, free pass, welcome, discovery, badge or purchase prompt. It has no end date or trial day. Settings can still activate an existing key. An unresolved setup can remain pending across arbitrary time and relaunches.
- **Migration never extends a saved trial.** Every stored `trialStartDate` is preserved verbatim, including starts from versions that began at initialization, expired dates and dates in the future after clock rollback. Resumed onboarding shows that same end date while the trial remains active; it never promises “starting now”. Revocation/regrant, skipping/unskipping Recording and relaunch never reset or pause a started trial. Existing elapsed-time and rollback behavior is unchanged.
- **License precedence is unchanged.** A stored valid, version-expired or invalidated license cannot start a fresh trial at readiness. Activation during setup remains valid and suppresses the trial. Deactivation resumes an existing trial on its original dates; without any saved trial it starts one only if this launch has reached usability, otherwise waits for that milestone. QA overlays never persist a trial start.
- **No grace period.** `isProLocked` is true the instant the trial expires — degradable Pro prefs downgrade immediately (this pairs with `ProTransitionManager.onProLockEngaged()`).
- **Keychain writes are all-or-nothing.** Activation writes key + instance + variant; if **any** write fails, every prior write is rolled back, validation timestamps are *not* written, and the state stays `.trial` — never a half-activated `.pro`. This is the most important invariant in the file.
- **A failed keychain write leaves the previous value intact.** `SystemKeychain.setValue` updates in place and never deletes first, so a machine that stops accepting writes (locked or password-drifted login keychain) keeps the license it already had instead of losing it. `MockKeychain` models the same contract, so the rollback above can only ever remove values *this* activation wrote.
- **Defensive expiry.** A license present in the keychain but with `lastValidationResult` missing or `false` resolves to `.trialExpired`, not `.pro`.
- **Revalidation is throttled.** `initialize()` dispatches an async revalidation only if `lastValidation` is older than the interval (~30 days). Within the interval it's skipped (no network call). Network failure preserves state and the old timestamp; a valid result refreshes the timestamp and variant; an invalid result flips to `.trialExpired`.
- **State is computed synchronously on `initialize()`** from defaults+keychain; async revalidation may then update it on the main queue.
- **`onStateChanged`** fires on initialize and on every transition; **`onBeforeProUnlock`** fires *before* the state flips to `.pro` (so observers can snapshot pre-Pro state).
- **QA license states are in-memory overlays.** `mockProUser()` and `mockTrialDay()` are `#if DEBUG` only and never read, clear, or write the user's Keychain and license defaults. Refreshing state keeps the overlay until relaunch; a mocked trial still follows the clock, so it expires like a real one.
- **A running app notices the end of the trial.** `state` follows the clock only on `refreshState()`. `trialEndedSinceLastRefresh` tells the Pro-transition coordinator that a `.trial` state has outlived `trialEndDate`, so it can refresh at a quiet moment (`ProTransitionSpecs.md`).

---

## Test scenarios

Mirrors `LicenseManagerTests.swift` 1:1. Each test uses an isolated `UserDefaults(suiteName:)` (fresh per test, torn down after) so runs don't leak into each other.

### A. Launch / initialize
- **testFirstUsableLaunchStartsTrial** — 30 days spent in setup consume none of the 14 days; readiness persists the current clock.
- **testSetupReadsAndRelaunchNeverStartOrExpireATrial** — reads/refresh/relaunch after 100 days retain pre-trial, without dates, entitlement or downgrade.
- **testFirstUsableMilestoneRequiresAccessibilityAndResolvedRecording** — all permission combinations; only granted Accessibility plus granted/waived Recording start the trial.
- **testExistingTrialDatesSurviveReadinessRevocationExpiryAndClockRollback** — prior active, expired and future starts remain identical.
- **testExistingLicenseNeverStartsATrialEvenWhenInvalidated** — license precedence at readiness.
- **testDeactivationBeforeUsableDoesNotStartTrial** / **testDeactivationAfterUsableStartsOnlyPreviouslyUnstartedTrial** — deactivation respects the usability milestone.
- **testSecondLaunchPreservesTrialStart** — relaunch 3 days later reuses the original `trialStartDate` → `.trial(11)`, not a fresh trial.
- **testTrialMidway** — trial started 7 days ago → `.trial(7)`.
- **testTrialLastDay** — trial started 13 days ago → `.trial(1)`.
- **testTrialExpiresOnDay14** — trial started 14 days ago → `.trialExpired`.
- **testTrialExpiresWellPastDuration** — trial started a year ago → `.trialExpired` (no underflow / negative days).

### B. Keychain-backed licenses
- **testExistingValidLicenseIsPro** — keychain has a key + `lastValidationResult == true` → `.pro`.
- **testPreviouslyInvalidatedLicenseIsTrialExpired** — same, but `lastValidationResult == false` → `.trialExpired`.
- **testLicenseWithoutValidationResultIsTrialExpired** — key present but `lastValidationResult` never set → defensively `.trialExpired`.

### C. Version-limited variants
- **testVersionLimitedPastCutoffIsProExpired** — guards the variant version-cutoff branch; with the default (empty) `versionLimitedVariants` dict, any variant resolves to `.pro`.

### D. Activate
- **testActivateSuccessTransitionsToPro** — successful activation → `.pro`; key/instance/variant written to keychain, `lastValidation*` set, `customerEmail` captured.
- **testActivateFailurePreservesState** — API rejects → state stays `.trial`, nothing written to keychain.
- **testActivateWithoutCustomerEmailLeavesCustomerEmailNil** — success with nil email/variant → `customerEmail` nil, no variant written.
- **testActivateSeatLimitExceededSurfacesInstances** — seat-limit error surfaces the list of active instances (id + machineName) to the caller; state unchanged, nothing written.
- **testActivateFailsAndRollsBackIfKeychainWriteFails** — API success but first keychain write fails → `keychainWriteFailed` surfaced, state stays `.trial`, nothing left in keychain, no validation/email written.
- **testActivateRollsBackPartialKeychainWritesOnLaterFailure** — first write succeeds, second fails → rollback removes the first write too; state stays `.trial`.
- **testActivateFailureKeepsAnAlreadyStoredLicense** — re-activating on a machine that already has a license, with a keychain that refuses writes → the stored key/instance/variant are all still there and state stays `.pro`; the rollback only removes what this activation wrote.
- **testDeactivateInstanceCallsApiWithoutTouchingLocalState** — deactivating *another machine's* instance calls the API but leaves local keychain + `.pro` state intact.

### E. Deactivate
- **testDeactivateSuccessReturnsToTrialWhenStillInTrialWindow** — deactivate while 3 days into trial → back to `.trial(11)`, keychain cleared.
- **testDeactivateSuccessReturnsToTrialExpiredAfterTrialWindow** — deactivate 100 days in → `.trialExpired`.
- **testDeactivateFailurePreservesState** — API rejects deactivation → stays `.pro`, keychain intact.
- **testDeactivateWithoutLicenseErrors** — deactivate with no license → errors, API never called.

### F. Async revalidation
- **testRevalidationWithinIntervalIsSkipped** — `lastValidation` recent → no API validate call.
- **testRevalidationAfterIntervalValidKeepsPro** — `lastValidation` 31 days old, valid result → one validate call, stays `.pro`, timestamp refreshed.
- **testRevalidationAfterIntervalInvalidFlipsToTrialExpired** — stale + invalid result → flips to `.trialExpired`, `lastValidationResult` set false.
- **testRevalidationNetworkFailurePreservesState** — stale + network error → stays `.pro`, timestamp untouched.
- **testRevalidationUpdatesVariantIdWhenReturned** — valid result with a new variant id → variant written to keychain.

### G. State change callback
- **testOnStateChangedFiresOnInitialize** — `onStateChanged` fires once on initialize with the computed `.trial` state.
- **testOnStateChangedFiresOnActivateSuccess** — fires again on activation, last value `.pro`, ≥2 total.

### H. isProLocked + onBeforeProUnlock
- **testIsProLockedFalseDuringTrial** — `.trial` → not locked.
- **testIsProLockedTrueAfterTrialExpiry** — `.trialExpired` → locked immediately (no grace period).
- **testIsProLockedTrueWhenKeychainInvalidated** — keychain license invalidated → `.trialExpired` and locked.
- **testOnBeforeProUnlockFiresBeforeStateFlipsToPro** — the hook observes a non-`.pro` state, confirming it runs before the flip.
- **testOnBeforeProUnlockFiresOnMockProUser** *(DEBUG only)* — `mockProUser()` fires the hook and flips to `.pro`.
- **testMockProUserDoesNotAlterPersistedLicense** *(DEBUG only)* — Pro QA state supplies deterministic email/variant values in memory, survives refresh, and leaves a preloaded real license untouched.
- **testMockTrialDayDoesNotAlterPersistedLicense** *(DEBUG only)* — trial QA state supplies its synthetic day in memory, survives refresh, and leaves a preloaded real license untouched.
- **testMockedTrialExpiresWhenTheClockPassesItsEnd** *(DEBUG only)* — a mocked day-14 trial becomes `.trialExpired` on refresh once the clock reaches day 15.
- **testRunningAppKnowsWhenTheTrialHasOutlivedItsState** — `trialEndedSinceLastRefresh` turns true exactly at `trialEndDate` while `state` is still `.trial`, and false again after `refreshState()` expires it.
- **testLicensedStateNeverReportsAnOutlivedTrial** — a `.pro` license is never reported as an outlived trial, however old its trial start.

### I. Trial day
- **testTrialDay_isNilWithoutTrial** — no `trialStartDate` → `trialDay` is nil, never a guessed day.
- **testTrialDay_isOneIndexed** — the start day is day 1, 34 days later is day 35, 99 days later is day 100.
- **testTrialDay_isNilWhenClockIsBeforeTrialStart** — a clock set before the trial start → nil.

## Team licenses

- A team key reports the existing `pro_lifetime` tier. Its purchased Mac count is enforced by the server, without changing personal licenses' three-Mac limit.
- A seat-limit response carrying `seats` becomes `teamSeatLimitExceeded`, even if it also includes a roster. The app asks the user to contact their license manager; only the buyer manages the team's other Macs through My Account. A personal response still opens the existing remote-deactivation flow.
- Activation and validation send the computer name from System Configuration, without network hostname resolution. Control characters and surrounding whitespace are removed, and the name is capped at 64 Unicode scalars. Missing or empty names are omitted. Deactivation sends no name.
- `RemoteLicenseClientTests` covers both limit responses, the request bodies for all three operations, and an unavailable name. The tests use a private URL session and never contact the licensing service.

### Teams verification

- `RemoteLicenseClientTests` sends actual requests through an isolated URL session and checks the Lifetime response, team/personal seat-limit distinction, machine-name normalization, and trial attribution. The trial-start source is injected so tests do not initialize the production singleton or read its Keychain.
- `testLifetimeActivationPersistsAcrossManagerReplacement` checks the stored entitlement remains Lifetime after manager initialization.
- AltTab QA `LIVE-PRO-05` and `LIVE-PRO-06` exercise Lifetime unlock, prompt cancellation and relaunch using the real isolated Keychain. They do not make a purchase or contact the licensing server.
