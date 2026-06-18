import Foundation

/// The search-mode state machine, extracted from `TilesView` as a pure decision kernel (same
/// pattern as `SelectionResolver`). It owns the transition + key-routing *decisions*; `TilesView`
/// and `ShortcutAction` translate the returned decisions into AppKit side effects (first responder,
/// caret, refresh, edit menu, `App.cycleSelection`). No globals, no AppKit, no async — so every
/// interaction is unit-testable. Behavior mirrors the original branch order exactly.
///
/// Pro gating note: `ProFeature.searchInSwitcher.attemptUse()` has side effects (it can consume the
/// free pass and surface the upgrade UI), so the caller evaluates it at the real attempt moment and
/// passes the resulting `Bool` in — the kernel never calls it. `toggle` is gate-free because the
/// original `toggleSearchModeFromShortcut` delegated gating to `enableSearchEditing` / `disableSearchMode`.

enum SearchMode {
    case off
    case editing
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

/// Which production path the search shortcut should take. The Pro gate is applied by the caller
/// inside the chosen path (matching the original delegation).
enum SearchToggleRoute: Equatable { case enterEditing, disable }

enum SearchModeDecision: Equatable {
    case noOp              // nothing to do (e.g. disabling when already off)
    case enterEditing      // off -> editing (always refreshes the UI)
    case exitToOff
    case proGateBlocked    // the Pro attempt was denied
    case placeCaretOnly    // already editing: just re-place the caret
}

enum SearchEscapeDecision: Equatable { case exitSearch, closeSwitcher }

enum SearchKeyDecision: Equatable {
    case cycleSelection(CycleDirection)
    case handled          // swallow (Tab)
    case passToShortcuts  // hand to the shortcut pipeline (any matched when-active shortcut)
    case passToField      // hand to the NSSearchField (text, cmd+A/C/V/X, IME, while a menu is open)
}

enum SearchModeResolver {
    static func startMode(startInSearch: Bool) -> SearchMode {
        startInSearch ? .editing : .off
    }

    /// Search shortcut: editing → turn off; off → enter editing. Gate applied by caller.
    static func toggle(mode: SearchMode) -> SearchToggleRoute {
        mode == .editing ? .disable : .enterEditing
    }

    /// Gate FIRST (mirrors `attemptUse()` on entry), then the already-editing short-circuit, else enter.
    static func enableEditing(mode: SearchMode, canSearch: Bool) -> SearchModeDecision {
        if !canSearch { return .proGateBlocked }
        if mode == .editing { return .placeCaretOnly }
        return .enterEditing
    }

    static func disable(mode: SearchMode) -> SearchModeDecision {
        mode == .off ? .noOp : .exitToOff
    }

    /// Escape exits search only when it was toggled on mid-session. If the session *started* in
    /// search (`.searchOnRelease`), or search is off, Escape closes the whole switcher.
    static func escape(mode: SearchMode, entry: SearchEntryStyle) -> SearchEscapeDecision {
        (mode != .off && entry == .toggledMidSession) ? .exitSearch : .closeSwitcher
    }

    /// Key routing while the search field is being edited. IME/menu come first so composing
    /// keystrokes are never stolen; then arrows drive selection, Tab is swallowed, a matched
    /// when-active shortcut goes to the shortcut pipeline, and everything else (typed text,
    /// cmd+A/C/V/X) goes to the NSSearchField. Defaults express "no signal" so callers only spell
    /// out the facts that are true for this key-down.
    static func routeKey(hasMarkedText: Bool = false,    // IME composing
                         isMenuOpen: Bool = false,       // a context menu is open
                         arrow: CycleDirection? = nil,   // non-nil iff the key is an arrow
                         isTab: Bool = false,
                         matchesShortcut: Bool = false) -> SearchKeyDecision {
        if hasMarkedText || isMenuOpen { return .passToField }
        if let arrow { return .cycleSelection(arrow) }
        if isTab { return .handled }
        if matchesShortcut { return .passToShortcuts }
        return .passToField
    }

    static func isFieldEditable(_ mode: SearchMode) -> Bool {
        mode == .editing
    }

    /// Whether a key-down should count as a when-active shortcut (close / minimize / quit / focus /
    /// cancel / …) *while the search field is being edited*, as opposed to plain typed text.
    ///
    /// The conflict this resolves: in search you release the activation modifiers to type, so a
    /// shortcut bound to a bare printable key (e.g. `closeWindow = W`) would otherwise steal the
    /// keystroke and you could never type that letter (#5781). The rule mirrors how every macOS text
    /// field behaves: a bare printable keystroke is text. To trigger the shortcut you re-press the
    /// activation (hold) modifiers and the key, exactly as you would outside search.
    ///
    /// So the "bare" arm (`event == shortcut`) is dropped for printable keys — but only when there
    /// ARE hold modifiers to fall back on (otherwise the shortcut would be untriggerable), and
    /// never for non-printable keys (Escape / Return / arrows, which can't be typed text) nor for
    /// bindings that already carry Cmd/Ctrl (clearly a command, not text). The "with hold modifiers"
    /// arm (`event == shortcut | hold`) always stands. A Cmd-inclusive hold modifier thus keeps the
    /// whole Option+letter special-character layer (`œ`, accents) free for typing.
    static func editingShortcutMatch(eventModifiers: UInt32,
                                     shortcutModifiers: UInt32,
                                     holdModifiers: UInt32,
                                     isPrintable: Bool,
                                     shortcutHasCommandModifier: Bool) -> Bool {
        let matchesBare = eventModifiers == shortcutModifiers
        let matchesWithHold = eventModifiers == (shortcutModifiers | holdModifiers)
        let bareWouldStealTypedText = isPrintable && !shortcutHasCommandModifier && holdModifiers != 0
        return (bareWouldStealTypedText ? false : matchesBare) || matchesWithHold
    }
}
