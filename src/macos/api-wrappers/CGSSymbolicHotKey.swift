import Foundation

/// Identifiers for the native macOS symbolic hotkeys AltTab cares about. Defined in this small
/// both-targets file (rather than `SkyLight.framework.swift`, which is app-only) so kernels like
/// `NativeHotkeyResolver` that surface this enum can compile in the unit-tests target. See
/// `setNativeCommandTabEnabled` / `CGSSetSymbolicHotKeyEnabled` in `SkyLight.framework.swift` for the
/// runtime side of toggling them.
enum CGSSymbolicHotKey: Int, CaseIterable {
    case commandTab = 1
    case commandShiftTab = 2
    case commandKeyAboveTab = 6 // see keyAboveTabDependingOnInputSource
}
