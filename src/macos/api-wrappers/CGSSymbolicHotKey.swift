import Foundation

/// Identifiers for the native macOS symbolic hotkeys AltTab cares about. Defined in this small
/// both-targets file (rather than `SkyLight.framework.swift`, which is app-only) so kernels like
/// `NativeHotkeyResolver` that surface this enum can compile in the unit-tests target. See
/// `setNativeCommandTabEnabled` / `CGSSetSymbolicHotKeyEnabled` in `SkyLight.framework.swift` for the
/// runtime side of toggling them.
///
/// Only the two the Dock consumes are here. The Dock matches ⌘⇥ / ⌘⇧⇥ inside the WindowServer's
/// symbolic-hotkey layer, ahead of any app's Carbon hotkey, so AltTab must switch them off to be heard.
/// ⌘` ("Move focus to next window", id 27) is not consumed by any system process: the keystroke is delivered
/// to the frontmost app and AppKit cycles there. AltTab's Carbon hotkey is matched before that delivery, so
/// the app never sees the key and there is nothing to disable. Disabling it would only remove the OS fallback
/// while AltTab's shortcuts are off (an app in Exceptions, a crash). Pinned by
/// `testCommandKeyAboveTabAloneDisablesNothing`. Ids read live from `CGSGetSymbolicHotKeyValue`; id 6, which
/// looked like a candidate, is ⌘⌥⇧⎋ (force quit the front app).
enum CGSSymbolicHotKey: Int, CaseIterable {
    case commandTab = 1
    case commandShiftTab = 2
}
