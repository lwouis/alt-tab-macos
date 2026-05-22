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
}
