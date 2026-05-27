import Foundation

/// The search-mode state machine, extracted from `TilesView` as a pure decision kernel (same
/// pattern as `SelectionResolver`). It owns the transition + key-routing *decisions*; `TilesView`
/// and `ShortcutAction` translate the returned decisions into AppKit side effects (first responder,
/// caret, refresh, edit menu, `App.cycleSelection`). No globals, no AppKit, no async — so every
/// interaction is unit-testable. Behavior mirrors the original branch order exactly.
///
/// Pro gating note: `ProFeature.*.attemptUse()` has side effects (it can consume the free pass and
/// surface the upgrade UI), so the caller evaluates it at the real attempt moment and passes the
/// resulting `Bool` in — the kernel never calls it. `toggle` is gate-free because the original
/// `toggleSearchModeFromShortcut` delegated gating to `enableSearchEditing` / `disableSearchMode`.

enum SearchMode {
    case off
    case editing
    case locked
}

/// How search was entered this session — decides what Escape does.
enum SearchEntryStyle {
    case startedInSearch    // session began in search (the `.searchOnRelease` shortcut style)
    case toggledMidSession  // search turned on via the search shortcut during a normal session
}

/// Kernel-local direction (decoupled from the app-only `Direction` enum, which `TilesView` maps to).
enum CycleDirection: Equatable {
    case left, right, up, down
}

enum ProGate: Equatable { case search, lockSearch }

/// Which production path the search shortcut should take. The Pro gate is applied by the caller
/// inside the chosen path (matching the original delegation).
enum SearchToggleRoute: Equatable { case enterEditing, disable }

enum SearchModeDecision: Equatable {
    case noOp                          // nothing to do (e.g. disabling when already off)
    case enterEditing(refreshUi: Bool) // refresh only when coming from `.off` (the original `wasOff`)
    case exitToOff
    case lockResults                   // editing -> locked
    case unlockToEditing               // locked -> editing
    case proGateBlocked(ProGate)       // the Pro attempt was denied
    case placeCaretOnly                // already editing: just re-place the caret
}

enum SearchEscapeDecision: Equatable { case exitSearch, closeSwitcher }

enum SearchKeyDecision: Equatable {
    case cycleSelection(CycleDirection)
    case handled          // swallow (Tab)
    case passToShortcuts  // hand to the shortcut pipeline (cancel / lockSearch / focus)
    case passToField      // hand to the NSSearchField (text, cmd+A/C/V/X, IME, while a menu is open)
}

enum SearchModeResolver {
    static func startMode(startInSearch: Bool) -> SearchMode {
        startInSearch ? .editing : .off
    }

    /// Search shortcut: editing → turn off; off/locked → (re)enter editing. Gate applied by caller.
    static func toggle(mode: SearchMode) -> SearchToggleRoute {
        mode == .editing ? .disable : .enterEditing
    }

    /// Gate FIRST (mirrors `attemptUse()` on entry), then the already-editing short-circuit,
    /// else enter — refreshing the UI only when coming from `.off`.
    static func enableEditing(mode: SearchMode, canSearch: Bool) -> SearchModeDecision {
        if !canSearch { return .proGateBlocked(.search) }
        if mode == .editing { return .placeCaretOnly }
        return .enterEditing(refreshUi: mode == .off)
    }

    static func disable(mode: SearchMode) -> SearchModeDecision {
        mode == .off ? .noOp : .exitToOff
    }

    /// Gate FIRST, then the editing↔locked toggle; no-op when off.
    static func lock(mode: SearchMode, canLockSearch: Bool) -> SearchModeDecision {
        if !canLockSearch { return .proGateBlocked(.lockSearch) }
        switch mode {
            case .editing: return .lockResults
            case .locked: return .unlockToEditing
            case .off: return .noOp
        }
    }

    /// Escape exits search only when it was toggled on mid-session. If the session *started* in
    /// search (`.searchOnRelease`), or search is off, Escape closes the whole switcher.
    static func escape(mode: SearchMode, entry: SearchEntryStyle) -> SearchEscapeDecision {
        (mode != .off && entry == .toggledMidSession) ? .exitSearch : .closeSwitcher
    }

    /// Key routing while the search field is being edited. IME/menu come first so composing
    /// keystrokes are never stolen; then arrows drive selection, Tab is swallowed, the three
    /// pass-through shortcuts go to the shortcut pipeline, and everything else (typed text,
    /// cmd+A/C/V/X) goes to the field. Defaults express "no signal" so callers only spell out
    /// the facts that are true for this key-down.
    static func routeKey(hasMarkedText: Bool = false,    // IME composing
                         isMenuOpen: Bool = false,       // a context menu is open
                         arrow: CycleDirection? = nil,   // non-nil iff the key is an arrow
                         isTab: Bool = false,
                         matchesCancel: Bool = false,
                         matchesLockSearch: Bool = false,
                         matchesFocus: Bool = false) -> SearchKeyDecision {
        if hasMarkedText || isMenuOpen { return .passToField }
        if let arrow { return .cycleSelection(arrow) }
        if isTab { return .handled }
        if matchesCancel || matchesLockSearch || matchesFocus { return .passToShortcuts }
        return .passToField
    }

    static func isFieldEditable(_ mode: SearchMode) -> Bool {
        mode == .editing
    }
}
