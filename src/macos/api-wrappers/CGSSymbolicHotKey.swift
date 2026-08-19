import Foundation

/// Identifiers for the native macOS symbolic hotkeys AltTab cares about. Defined in this small
/// both-targets file (rather than `SkyLight.framework.swift`, which is app-only) so kernels like
/// `NativeHotkeyResolver` that surface this enum can compile in the unit-tests target. See
/// `setNativeCommandTabEnabled` / `CGSSetSymbolicHotKeyEnabled` in `SkyLight.framework.swift` for the
/// runtime side of toggling them.
/// IDs verified on macOS 27 by reading each one back with `CGSGetSymbolicHotKeyValue`, and
/// cross-checked against the `AppleSymbolicHotKeys` entries in `com.apple.symbolichotkeys`:
///
///     id  1 → keyCode 48 (⇥), ⌘        "Move focus to next application"
///     id  2 → keyCode 48 (⇥), ⇧⌘       "Move focus to previous application"
///     id  6 → keyCode 53 (⎋), ⌥⇧⌘      "Force Quit the frontmost app"
///     id 27 → keyCode 50 (`), ⌘        "Move focus to next window in the active application"
///
/// 27 is the one bound to the key above Tab. 6 is Force Quit — the same chord AltTab lists as
/// `MacOsShortcuts.forceQuitActiveApp` — so it must never be toggled here.
enum CGSSymbolicHotKey: Int, CaseIterable {
    case commandTab = 1
    case commandShiftTab = 2
    case commandKeyAboveTab = 27 // see keyAboveTabDependingOnInputSource
}
