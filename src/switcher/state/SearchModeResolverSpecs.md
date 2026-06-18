# SearchModeResolver — Specs

> **Line coverage:** `SearchModeResolver.swift` 100% · _refreshed 2026-05-27 by `/coverage-explore`_

## Summary

The in-switcher **Search** feature lets the user filter the window list by typing. `SearchModeResolver`
is the pure decision kernel for its state machine, extracted from `TilesView` (same pattern as
`SelectionResolver`). It decides *what should happen*; `TilesView` and `ShortcutAction` carry out the
AppKit side effects (make the search field first responder, place the caret, refresh the UI, toggle
the Edit menu, call `App.cycleSelection`).

### The two modes

- **`.off`** — no search field interaction; the switcher behaves normally.
- **`.editing`** — the search field is the first responder and editable; typing filters the list.

### How you enter search (this decides Escape's behavior)

- **Started in search** — the session began in search because the triggering shortcut uses the
  `.searchOnRelease` style. Search *is* the session.
- **Toggled mid-session** — a normal session where the user pressed the search shortcut to turn search on.

## Behavior & edge cases

- **Escape is contextual** (the headline interaction): if search was *toggled mid-session*, Escape
  exits search back to the normal switcher (a second Escape then closes it). If the session *started
  in search*, Escape closes the whole switcher immediately — there's no "normal switcher" to fall back to.
- **Pro gating timing**: `ProFeature.searchInSwitcher.attemptUse()` has side effects (consume the free
  pass, surface the upgrade UI), so the *caller* evaluates it at the real attempt moment and passes a
  `Bool` in. The gate is checked **before** the state branches, so a denied attempt never mutates mode
  (it returns `.proGateBlocked`). `toggle` is gate-free — it just routes to the enter/disable path,
  which applies its own gate (mirrors the original delegation).
- **Entering editing refreshes the UI** (`enterEditing` is only reached from `.off`).
- **Key routing precedence** (while editing): IME-composing or an open context menu wins first (never
  steal composing keystrokes) → arrows drive selection → Tab is swallowed → a matched when-active
  shortcut passes to the shortcut pipeline → everything else (typed text, **cmd+A/C/V/X**) goes to the
  `NSSearchField`, which handles select-all/copy/paste/cut natively. AltTab does not intercept those.
- **Any when-active shortcut works in editing via hold+key** (`editingShortcutMatch`, #5781 generalized):
  in search you release the activation modifiers to type, so a when-active shortcut bound to a bare
  printable key (e.g. the default `closeWindow = W`, `quitApp = Q`) must not steal the keystroke — you
  type the letter, and trigger the shortcut by re-pressing the hold modifiers (`Cmd+Option+W`), exactly
  as you would outside search. The whole when-active set (close / minimize / fullscreen / quit / hide /
  focus / cancel / search) routes this way; `TilesView` ORs the per-shortcut match over
  `Preferences.staticShortcutKeys`. The "bare" arm (`event == shortcut`) is dropped for printable keys,
  but only when there are hold modifiers to fall back on (else the shortcut would be untriggerable), and
  never for non-printable keys (Escape/Return/arrows) nor bindings that already carry Cmd/Ctrl. The
  "with hold modifiers" arm always stands. A Cmd-inclusive hold modifier thus keeps the whole
  Option+letter special-character layer (`œ`, accents) free for typing. The printable/non-printable test
  itself (`eventProducesText`) lives in `TilesView`, since it reads the `NSEvent`.
- **Modifier-only shortcuts are gated the same way** (e.g. the default `previousWindow = ⇧`): a bare
  modifier is uppercasing/typing input, not a command, so it must not fire while editing; only `⌥⇧`
  (hold + the modifier) navigates. These arrive as `flagsChanged` (no keyDown), so they never reach
  `routeKey`; `ATShortcut.modifiersMatch` feeds them through `editingShortcutMatch` (with `isPrintable:
  true`) while editing instead. Without this they would fire on the bare modifier and you couldn't type
  capitals in the search field.
- **Field editability** tracks mode exactly: editable iff `.editing`.
- **Not modeled here** (stays in `TilesView` as side effects): caret placement, first-responder
  changes, `forceDoNothingOnRelease`, hover clearing, key-repeat-timer stops, the Edit-menu toggle, and
  `endSearchSession` teardown (which unconditionally resets to `.off` and is distinct from `disable`).

---

## Test scenarios

Mirrors `SearchModeResolverTests.swift` 1:1.

### A. Session entry
- **testEntryStartedInSearchBeginsEditing** — `startMode(startInSearch: true)` → `.editing`.
- **testEntryNormalSessionStartsOff** — `startMode(startInSearch: false)` → `.off`.

### B. Toggle route (search shortcut)
- **testToggleFromOffEntersEditing** — `.off` → `.enterEditing`.
- **testToggleFromEditingDisables** — `.editing` → `.disable`.

### C. Enter editing (Pro-gated)
- **testEnterFromOffEntersEditing** — `.off` + entitled → `.enterEditing`.
- **testEnterWhenAlreadyEditingJustPlacesCaret** — `.editing` + entitled → `placeCaretOnly`.
- **testEnterBlockedWhenSearchNotEntitled** — not entitled (gate checked before state branch) → `.proGateBlocked`.

### D. Disable
- **testDisableFromEditingExitsToOff** — `.editing` → `.exitToOff`.
- **testDisableWhenAlreadyOffIsNoOp** — `.off` → `.noOp`.

### E. Escape depends on how search was entered
- **testEscapeEditingToggledMidSessionExitsSearch** — editing + mid-session → `.exitSearch`.
- **testEscapeEditingStartedInSearchClosesSwitcher** — editing + started-in-search → `.closeSwitcher`.
- **testEscapeOffToggledMidSessionClosesSwitcher** — off → `.closeSwitcher`.
- **testEscapeOffStartedInSearchClosesSwitcher** — off → `.closeSwitcher`.

### F. Key routing: navigation & tab
- **testKeyLeftArrowCyclesLeft** / **testKeyRightArrowCyclesRight** / **testKeyUpArrowCyclesUp** / **testKeyDownArrowCyclesDown** — arrows → `cycleSelection(dir)`.
- **testKeyTabIsSwallowed** — Tab → `.handled`.

### G. Key routing: shortcut pass-through
- **testKeyMatchedShortcutPassesToShortcuts** — a matched when-active shortcut → `.passToShortcuts`.
- **testKeyArrowWinsOverMatchingShortcut** — an arrow also bound as a shortcut still cycles (arrow precedence).

### H. Key routing: text editing passes to the field
- **testKeyPlainTextPassesToField** — typed characters and cmd+A/C/V/X (none of arrow/tab/shortcut) → `.passToField` (NSSearchField handles editing natively).

### I. IME composing / open context menu beat everything
- **testKeyMarkedTextBeatsArrow** — composing → `.passToField` even for an arrow.
- **testKeyOpenMenuBeatsTab** — open menu → `.passToField` even for Tab.
- **testKeyMarkedTextBeatsShortcut** — composing → `.passToField` even for a matching shortcut.

### J. Search-field editability
- **testFieldEditableOnlyWhenEditing** — editable iff `.editing` (off is read-only).

### K. editingShortcutMatch: a bare printable key is typed text, not a shortcut
- **testEditingNonPrintableBareMatches** — non-printable binding (default `cancel = Escape`) → bare tap still matches.
- **testEditingPrintableBareIsTypedTextNotShortcut** — `cancel = Q`, bare `q` with hold released → does NOT match (types). (#5781)
- **testEditingPrintableWithHoldModifiersMatches** — same key with the hold modifiers re-pressed (`Cmd+Option+Q`) → matches.
- **testEditingPrintableSpecialCharTypesWhenEventLacksFullHold** — Option-only `Q` (typing `œ`) under a Cmd+Option hold → does NOT match (types).
- **testEditingPrintableBareKeptWhenNoHoldModifier** — no hold modifier to fall back on → bare arm kept (status quo, never untriggerable).
- **testEditingPrintableBindingWithCommandModifierMatchesBare** — a Cmd/Ctrl binding (`cancel = Cmd+Q`) is a command, not text → bare arm honored.
- **testEditingWindowActionTypesBareButTriggersWithHold** — default `closeWindow = W`: bare `w` types; hold+W closes (the generalization of #5781 to the whole when-active set).
- **testEditingModifierOnlyShortcutTypesBareButTriggersWithHold** — default `previousWindow = ⇧`: bare Shift uppercases (does not navigate); `⌥⇧` navigates. Modifier-only shortcuts are routed through this kernel from `ATShortcut.modifiersMatch` because they arrive as `flagsChanged`, not keyDown.
