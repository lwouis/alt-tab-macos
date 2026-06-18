import Foundation

/// Pure decision kernel for `ATShortcut.modifiersMatch`: given a keyboard event's modifier set and a
/// configured shortcut's modifiers, decide whether they match — accounting for the activation (hold)
/// modifiers and the current context (the holdShortcut / nextWindowShortcut special cases, and the
/// search-editing gate for modifier-only shortcuts). Extracted from `ATShortcut` so the branch *order*
/// is unit-tested (same rationale as `NativeHotkeyResolver`, #5653); `ATShortcut` is the thin adapter
/// that gathers the inputs from `SwitcherSession` / `ControlsTab` / `TilesView`.
///
/// All modifier args are *cleaned* Carbon bitmasks (see `CarbonModifierFlags.cleaned()`). The kernel
/// only compares bits, so unit tests can use opaque bit values rather than real Carbon constants.
enum ShortcutModifierResolver {
    static func matches(eventModifiers: UInt32,
                        shortcutModifiers: UInt32,
                        holdModifiers: UInt32,
                        isHoldShortcut: Bool,
                        isNextWindowShortcut: Bool,
                        sessionActive: Bool,
                        isModifierOnly: Bool,
                        isSearchEditing: Bool,
                        shortcutHasCommandModifier: Bool) -> Bool {
        // holdShortcut: the event must contain *at least* the shortcut's modifiers (e.g. ⌥ held).
        if isHoldShortcut {
            return eventModifiers == (eventModifiers | shortcutModifiers)
        }
        // nextWindowShortcut while the panel is open: also match the base key with the hold modifiers
        // stripped, so a configured ⌥⇥ cycles on bare ⇥ once the switcher is already showing.
        if sessionActive && isNextWindowShortcut {
            let baseModifiers = shortcutModifiers & ~holdModifiers
            if eventModifiers == baseModifiers { return true }
        }
        // While editing the search field, a bare modifier-only shortcut (e.g. previousWindow = ⇧) is
        // uppercasing input, not a command, so it must not fire on its own; require the hold modifiers
        // too (e.g. ⌥⇧), mirroring `editingShortcutMatch` for printable keyDown shortcuts (#5781).
        // Modifier-only shortcuts arrive as `flagsChanged` (no keyDown), so they bypass
        // `TilesView.handleSearchEditingKeyDown` and must be gated here instead.
        if isModifierOnly && isSearchEditing {
            return SearchModeResolver.editingShortcutMatch(
                eventModifiers: eventModifiers,
                shortcutModifiers: shortcutModifiers,
                holdModifiers: holdModifiers,
                isPrintable: true,
                shortcutHasCommandModifier: shortcutHasCommandModifier)
        }
        // Default: the event modifiers are exactly the shortcut's, or exactly the shortcut's + hold.
        return eventModifiers == shortcutModifiers || eventModifiers == (shortcutModifiers | holdModifiers)
    }
}
