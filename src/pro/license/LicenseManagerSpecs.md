# LicenseManager — Specs

> **Line coverage:** `LicenseManager.swift` 91% · _refreshed 2026-05-27 by `/coverage-explore`_

## Summary

`LicenseManager` is the single source of truth for whether the user has AltTab **Pro**. It computes a `LicenseState` and notifies observers when it changes. The state drives every Pro gate in the app (search, lock-search, extra shortcuts, App Icons / Titles styles, Auto size, search-on-release) and the Pro-transition prompts.

It is built from three injected collaborators so the logic is testable without real I/O — the tests pass in mocks (`MockClock`, `MockKeychain`, `MockLicenseAPI`, all defined inline at the bottom of `LicenseManagerTests.swift`):

- **`Clock`** — current time. Lets tests fast-forward the trial without sleeping.
- **`Keychain`** — secure storage for the license key, instance id, and variant id. Tied to the app's code signature (see the License/Keychain invariant in `AGENTS.md`).
- **`LicenseAPI`** — the LemonSqueezy-backed activate / validate / deactivate calls.
- **`UserDefaults`** — non-secret bookkeeping: `trialStartDate`, `lastValidation` (timestamp), `lastValidationResult` (Bool).

## State model

```
.trial(daysRemaining)  →  .pro            (user activates a key)
.trial(daysRemaining)  →  .trialExpired   (14 days elapse)
.pro                   →  .trialExpired    (revalidation fails / license invalidated, still in/after trial window)
.pro                   →  .proExpired      (version-limited variant past its cutoff)
```

### Behavior & edge cases (the load-bearing rules)

- **Trial length is 14 days, 0-indexed internally.** Day 0 = first launch → `.trial(14)`; day 13 → `.trial(1)`; day 14 → `.trialExpired`. The trial start is persisted on first launch and **never reset** on relaunch.
- **No grace period.** `isProLocked` is true the instant the trial expires — degradable Pro prefs downgrade immediately (this pairs with `ProTransitionManager.onProLockEngaged()`).
- **Keychain writes are all-or-nothing.** Activation writes key + instance + variant; if **any** write fails, every prior write is rolled back, validation timestamps are *not* written, and the state stays `.trial` — never a half-activated `.pro`. This is the most important invariant in the file.
- **Defensive expiry.** A license present in the keychain but with `lastValidationResult` missing or `false` resolves to `.trialExpired`, not `.pro`.
- **Revalidation is throttled.** `initialize()` dispatches an async revalidation only if `lastValidation` is older than the interval (~30 days). Within the interval it's skipped (no network call). Network failure preserves state and the old timestamp; a valid result refreshes the timestamp and variant; an invalid result flips to `.trialExpired`.
- **State is computed synchronously on `initialize()`** from defaults+keychain; async revalidation may then update it on the main queue.
- **`onStateChanged`** fires on initialize and on every transition; **`onBeforeProUnlock`** fires *before* the state flips to `.pro` (so observers can snapshot pre-Pro state).
- **`mockProUser()` is `#if DEBUG` only** (a QA-menu helper). CI runs `-configuration Release`, which strips DEBUG, so its test is guarded by `#if DEBUG` too.

---

## Test scenarios

Mirrors `LicenseManagerTests.swift` 1:1. Each test uses an isolated `UserDefaults(suiteName:)` (fresh per test, torn down after) so runs don't leak into each other.

### A. Launch / initialize
- **testFirstLaunchStartsTrial** — first launch with no stored data → `.trial(14)`, `trialStartDate` set to now.
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
