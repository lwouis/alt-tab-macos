# OnActionExtension — Specs

## Summary

`NSControl.onAction` is a convenience extension (defined in `HelperExtensionsTestable.swift`) that
replaces the classic target/action pair with a stored **closure**: assigning `control.onAction = { … }`
wires the control's `target`/`action` to invoke that closure, and reading the property back returns the
stored closure. It's the backbone of `AppearanceTab`'s Pro-lock **wrap pattern** — a control's existing
action is read, captured as `original`, and re-wrapped so a Pro-gate check can run first and then
optionally fall through to `original?(control)`.

## Behavior & edge cases

- The **getter returns the same closure** that was stored (not nil). This is load-bearing: the wrap
  pattern reads `let original = control.onAction`; a broken getter would leave `original` nil and orphan
  the underlying action (the regression these tests pin).
- Setting a new closure **replaces** the previous one — the old closure must not fire afterward.
- Setting `onAction = nil` clears `target`, `action`, and the stored closure.
- The captured `original` closure must **survive later reassignments** of `onAction` (the closure is held
  by a strong associated object), so a wrapper can still call through after the control's `onAction` is
  overwritten.

## Test scenarios

Mirrors `OnActionExtensionTests.swift` 1:1.

### A. Getter round-trip
- **testGetterReturnsNilWhenUnset** — a fresh control reports `onAction == nil`.
- **testGetterReturnsClosureAfterSet** — after assigning a closure, the getter is non-nil.
- **testGetterReturnsSameClosureThatSetterStored** — invoking the read-back closure runs the stored one (once).

### B. Target/action plumbing
- **testSetterConfiguresTargetAndAction** — assigning a closure populates `target` and `action`.
- **testSetterReplacesPreviousClosure** — a second assignment replaces the first; only the new one fires.
- **testSettingNilClearsTargetAndAction** — assigning nil clears `target`, `action`, and the closure.
- **testActionFiresClosureViaTargetActionPlumbing** — invoking the wired action (the real AppKit call path: `target.perform(action, with: control)`) reaches the stored closure through `SelectorWrapper.callClosure`, with the sender forwarded.

### C. Wrap pattern (the AppearanceTab use case)
- **testWrapPatternInvokesPreviousClosureOnFallthrough** — a wrapper that calls `original?(c)` runs both the wrapper and the captured original.
- **testWrapPatternSkipsPreviousClosureOnEarlyReturn** — a wrapper that returns early (the Pro-locked branch) does NOT fire the original, so the Pro value is never written to `Preferences`.
- **testOriginalClosureSurvivesReassignment** — the captured `original` still fires after `onAction` is reassigned many times (no premature release).
