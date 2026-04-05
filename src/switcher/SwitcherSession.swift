import Cocoa

/// Holds all state scoped to a single switcher invocation: from when the user
/// first triggers the shortcut to when the panel is dismissed.
///
/// `current` is non-nil iff the switcher panel is conceptually shown to the
/// user. Lifetime is owned by `App.showUiOrCycleSelection` (creates) and
/// `App.hideUi` (destroys).
final class SwitcherSession {
    static var current: SwitcherSession?
    static var isActive: Bool { current != nil }
    /// The shortcut index of the currently-active session, or 0 when no session is active.
    /// Used by every per-shortcut effective preference read in `Appearance`, `TileView`, etc.
    static var activeShortcutIndex: Int { current?.shortcutIndex ?? 0 }

    var shortcutIndex: Int = 0
    var isFirstSummon: Bool = true
    var forceDoNothingOnRelease: Bool = false

    var selectedIndex: Int = 0
    var hoveredIndex: Int?
    var selectedTarget: String?
    var searchQuery: String = ""

    /// PID of the app that was frontmost when this session started. The `cgEventHandler`
    /// in `KeyboardEvents` redelivers the hold-modifier release event to this PID via
    /// `CGEventPostToPid`, so the initial app sees a release matching the press it saw
    /// when the user invoked the switcher.
    var initialPid: pid_t?
    /// Modifier mask of the active hold shortcut. The trigger event is the `flagsChanged`
    /// where the current modifiers no longer fully satisfy this mask.
    var holdMask: NSEvent.ModifierFlags = []
}
