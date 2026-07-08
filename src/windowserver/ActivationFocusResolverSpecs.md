# ActivationFocusResolver — Specs

## Summary

Pure decisions for MRU focus around an app activation, extracted from `WindowServerEvents` after two
regressions in a row (#5596). The recorded ground truth (TextEdit and iTerm, via Cmd+Tab, clicks, and
AltTab-initiated focus): on activation macOS emits 808s for the app's on-Space windows — the **first** is the
genuinely focused window; the rest, when there is a storm at all, are raises front-to-back; sometimes there is
**no** storm, just the single focus 808 (iTerm). Three rules follow:

- The **first 808** of a live activation bumps the MRU. It is the truth, and it bypasses the `isActive` guard
  (`NSRunningApplication.isActive` is a separate clock and can still read false at that instant).
- The **raise tail** (subsequent 808s for wids still in the activation snapshot) is swallowed — re-fronting
  each would reverse the app's MRU (the original #5596 inversion).
- The **AX focused-window backstop** (`bumpFocusOnActivation`, for activations that emit no 808) is the weak
  signal: it races the app's internal focus update and can return the *previous* window (iTerm with panes).
  It yields once the activation's focus 808 has spoken (`focusBumped`), checked at apply time since the read
  is async and can land after the 808.

`ActivationEntry` is the per-pid state: the snapshot `wids` (only windows the storm can raise — the adapter
excludes minimized and inactive tabs), the `until` expiry (0.5s; generous because the 808s queue behind
AltTab's own activation work), and `focusBumped`.

## Functions

- **`onFocusEvent(entry, wid, now, wasJustCreated, appIsActive) -> FocusDecision`** — decide one 808:
  `bump` + the entry state to store back. Expired entry ⇒ pruned (nil) and plain rules apply. Brand-new
  window ⇒ always bump. First 808 of a live activation ⇒ bump, mark `focusBumped`, consume the wid.
  In-snapshot 808 after that ⇒ raise, swallow, consume. Otherwise ⇒ bump iff `appIsActive`.
- **`onActivation(snapshotWids, until, altTabTarget) -> (entry, bumpWid)`** — build the activation entry.
  A known AltTab-initiated target (switcher selection / CLI focus) is bumped directly with `focusBumped` set
  (raise tail swallowed, AX backstop yields) — with no 808 and a stale AX read, the freshly-focused window's
  bump was otherwise lost. No target ⇒ plain entry; the first 808 or the AX backstop decides.
- **`axBackstopShouldApply(entry) -> Bool`** — false only when a live entry has `focusBumped` (the real
  808 already spoke); nil/expired/pre-focus ⇒ true.

## Test scenarios

Mirrors `ActivationFocusResolverTests.swift` 1:1.

### onFocusEvent

- **testFirstFocusOfActivationBumpsEvenWhileInactive** — single 808 right after activation, `isActive` still
  false (the iTerm #5596 case) → bump; `focusBumped` set; wid consumed.
- **testRaiseTailSwallowed** — post-focus 808 for a wid still in the snapshot (the TextEdit storm) → no bump;
  wid consumed.
- **testSecondFocusOfSameWidBumps** — a wid's second 808 (entry already consumed) while active → bump.
- **testExpiredEntryPrunedAndNormalRulesApply** — entry past `until` → pruned to nil; plain isActive rule.
- **testNoActivationActiveAppBumps** — no entry, app active → bump.
- **testNoActivationInactiveAppDropped** — no entry, app inactive (background app re-focusing itself) → drop.
- **testJustCreatedAlwaysBumps** — brand-new window's first focus bumps even inactive, even mid-raise-tail.

### onActivation

- **testAltTabInitiatedActivationBumpsKnownTarget** — known target → bumped directly; entry starts
  `focusBumped` so the raise tail is swallowed and the AX backstop yields.
- **testExternalActivationWaitsForFocusSignal** — no target (Cmd+Tab, click) → plain entry; the first 808
  (or the AX backstop when none arrives) decides.

### axBackstopShouldApply

- **testBackstopAppliesBeforeFocus808** — pre-focus entry or no entry → apply (zero-808 activations need it).
- **testBackstopYieldsAfterFocus808** — `focusBumped` → yield (the stale-AX race, #5596).
