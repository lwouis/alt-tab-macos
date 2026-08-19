import Carbon.HIToolbox.Events

/// Minimal data record for one configured shortcut, in the form the native-hotkey classifier needs.
/// Primitive types so this file compiles in the unit-tests target (same trick as `WindowState`).
struct ShortcutSnapshot: Equatable {
    let modifiers: UInt32   // shortcut.carbonModifierFlags
    let keyCode: UInt32     // shortcut.carbonKeyCode
}

/// Decides which native macOS symbolic hotkeys (⌘⇥ / ⌘⇧⇥ / ⌘`) AltTab must disable vs (re-)enable
/// to make room for the configured shortcuts. Pure kernel: takes the configured shortcuts plus the
/// set of hold-shortcut modifier flags currently in effect, returns disjoint disable/enable sets.
///
/// Issue #5653: the previous in-place implementation in `ControlsTab.toggleNativeCommandTabIfNeeded`
/// used `nativeHotkeys.first { … }`, which made the classification depend on Swift dictionary
/// iteration order. When a single shortcut matched multiple predicates (e.g. ⌘⇥ matches both
/// `.commandTab` exactly *and* `.commandShiftTab` via `combinedModifiersMatch` when a ⌘⇧
/// hold-shortcut is present), `.first` would pick one and drop the other, intermittently leaving
/// native ⌘⇥ enabled for an entire session. This kernel collects **all** matches per shortcut, so
/// the result is deterministic and independent of map iteration order.
enum NativeHotkeyResolver {
    static func resolve(shortcuts: [ShortcutSnapshot], holdShortcutModifiers: [UInt32])
        -> (disable: Set<CGSSymbolicHotKey>, enable: Set<CGSSymbolicHotKey>) {
        var disable = Set<CGSSymbolicHotKey>()
        for s in shortcuts {
            if matchesCommandTab(s) { disable.insert(.commandTab) }
            if matchesCommandShiftTab(s, holdShortcutModifiers) { disable.insert(.commandShiftTab) }
            if matchesCommandKeyAboveTab(s) { disable.insert(.commandKeyAboveTab) }
        }
        // binding ⌘⇥ should also suppress the native reverse switcher (⌘⇧⇥)
        if disable.contains(.commandTab) { disable.insert(.commandShiftTab) }
        let enable = Set(CGSSymbolicHotKey.allCases).subtracting(disable)
        return (disable, enable)
    }

    // MARK: - Native-hotkey predicates

    private static func matchesCommandTab(_ s: ShortcutSnapshot) -> Bool {
        s.modifiers == UInt32(cmdKey) && s.keyCode == UInt32(kVK_Tab)
    }

    private static func matchesCommandShiftTab(_ s: ShortcutSnapshot, _ holdShortcutModifiers: [UInt32]) -> Bool {
        s.keyCode == UInt32(kVK_Tab) && combinedModifiersMatch(s.modifiers, UInt32(cmdKey | shiftKey), holdShortcutModifiers)
    }

    private static func matchesCommandKeyAboveTab(_ s: ShortcutSnapshot) -> Bool {
        s.modifiers == UInt32(cmdKey) && s.keyCode == UInt32(kVK_ANSI_Grave)
    }

    /// True iff some hold-shortcut modifier set turns `modifiers1` and `modifiers2` into the same
    /// effective combo when OR'd in. Mirrors `CustomRecorderControlTestable.combinedModifiersMatch`
    /// but takes hold-shortcut modifiers as an explicit parameter rather than reading
    /// `ControlsTab.shortcuts` globals — keeps the kernel pure.
    private static func combinedModifiersMatch(_ modifiers1: UInt32, _ modifiers2: UInt32, _ holdShortcutModifiers: [UInt32]) -> Bool {
        holdShortcutModifiers.contains { (($0 | modifiers1) == ($0 | modifiers2)) }
    }
}

/// Remembers which symbolic hotkeys AltTab itself turned off, so it can turn exactly those back on.
///
/// The enabled/disabled state of a symbolic hotkey is global, user-owned (System Settings > Keyboard
/// > Keyboard Shortcuts), and persists after AltTab quits — see `CGSSetSymbolicHotKeyEnabled`. So
/// "AltTab no longer needs ⌘`" must mean "put ⌘` back the way the user had it", never "switch ⌘` on".
/// Without this bookkeeping, a user who had turned a hotkey off got it silently switched back on, and
/// WindowServer then consumed the keystroke before AltTab's Carbon hotkey or its shortcut recorder
/// could ever see it (issue #5455).
///
/// Pure state machine so it is unit-testable: `isEnabled` is injected, and the CGS calls live in
/// `disableNativeHotkeys` / `restoreNativeHotkeys` in `SkyLight.framework.swift`.
struct NativeHotkeyOwnership {
    private(set) var disabledByAltTab = Set<CGSSymbolicHotKey>()

    /// Of `hotkeys`, the ones to actually switch off: not already ours, and currently on. A hotkey
    /// the user had already turned off is left unclaimed, so we won't switch it on later.
    mutating func claim(_ hotkeys: Set<CGSSymbolicHotKey>, _ isEnabled: (CGSSymbolicHotKey) -> Bool) -> [CGSSymbolicHotKey] {
        let claimed = hotkeys.filter { !disabledByAltTab.contains($0) && isEnabled($0) }
        disabledByAltTab.formUnion(claimed)
        return Array(claimed)
    }

    /// Of `hotkeys`, the ones to actually switch back on: only those we previously claimed.
    mutating func release(_ hotkeys: Set<CGSSymbolicHotKey>) -> [CGSSymbolicHotKey] {
        let released = disabledByAltTab.intersection(hotkeys)
        disabledByAltTab.subtract(released)
        return Array(released)
    }
}
