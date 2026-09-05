import Cocoa

final class SwitcherSessionActivity {
    private let lock = NSLock()
    private var active = false

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func setActive(_ active: Bool) {
        lock.lock()
        self.active = active
        lock.unlock()
    }
}

/// Holds all state scoped to a single switcher invocation: from when the user
/// first triggers the shortcut to when the panel is dismissed.
///
/// `current` is non-nil iff the switcher panel is conceptually shown to the
/// user. Lifetime is owned by `App.showUiOrCycleSelection` (creates) and
/// `App.hideUi` (destroys).
final class SwitcherSession {
    private static let activity = SwitcherSessionActivity()
    static var current: SwitcherSession? {
        didSet { activity.setActive(current != nil) }
    }
    static var isActive: Bool { activity.isActive }
    /// The shortcut index of the currently-active session, or 0 when no session is active.
    /// Used by every per-shortcut effective preference read in `Appearance`, `TileView`, etc.
    static var activeShortcutIndex: Int { current?.shortcutIndex ?? 0 }

    var shortcutIndex: Int = 0
    var isFirstSummon: Bool = true
    var forceDoNothingOnRelease: Bool = false

    /// `systemUptime` at which the panel's pixels actually reached the screen this summon — set when our own
    /// panel's WindowServer `orderedIn` arrives (WindowServerEvents), which can lag the show's main-thread work
    /// by ~500ms when the WindowServer is busy settling a Space transition. The artificial key-repeat
    /// (`KeyRepeatTimer`) measures its initial-delay grace from here, not from arm time, so a slow show can't
    /// consume the grace and auto-advance the selection before the user has even seen the switcher.
    ///
    /// **Not set today**, and `panelShownAt` exists because of it: order-in is only delivered for wids in the
    /// per-window opt-in set (`WindowServerEvents.wsWindows`), which the panel is not in, and putting it there
    /// would feed our own panel's events into the reducer. Kept as the accurate correction should that change.
    var panelBecameVisibleAt: TimeInterval?
    /// `systemUptime` at which `TilesPanel.show()` ordered the panel front this summon. The anchor for the
    /// key-repeat grace that cannot go missing, where `panelBecameVisibleAt` can and does — without it every
    /// tick fell through to the 1s `missedVisibleSignalBudget` and hold-to-cycle started 1377ms in instead of
    /// the system's 417ms.
    var panelShownAt: TimeInterval?

    var selectedIndex: Int = 0
    var hoveredIndex: Int?
    var selectedTarget: String?
    /// The window `hoveredIndex` MEANS, so the highlight can be re-anchored when the list changes under it.
    /// An index alone survives a structural change as a valid number pointing at a different window: insert
    /// or remove a tile before the hovered one and the hover silently moves to its neighbour, which the
    /// bounds check cannot catch because the index is still in range.
    var hoveredTarget: String?
    /// True once the USER moved the selection themselves (cycled with the shortcut/arrows, or hovered) or
    /// acted on it (`ShortcutActions`), as opposed to it sitting on the default pick untouched. It decides
    /// whether `selectedTarget` is a commitment to
    /// follow or just where the default landed: a user's pick must stay on ITS window however the list
    /// reorders (#5665), while the default must keep tracking the model — the window set is still settling
    /// when the switcher opens, and locking the default onto whatever occupied the slot mid-churn made the
    /// selection trail that window to a nonsense position as the list reordered.
    var userPickedSelection = false
    /// Every window id the model held when the shortcut was pressed. A window in here is one the user was
    /// already choosing among, so it can never be a "newcomer" the default pick steps over, however its
    /// focus moves afterwards.
    ///
    /// Gaining focus is NOT enough on its own, which cost a live bug: a tab group re-elected its
    /// representative mid-session (one tab of a window handing off to another tab of the SAME window), the
    /// incoming tab was focused and therefore stepped over, and the pick slid one tile further — repeatedly,
    /// so the selection walked away from where the user was aiming. No tile appeared; only which member of
    /// an existing group was drawn changed. Presence at the summon is what tells a genuine newcomer from a
    /// reshuffle of what was already on screen.
    var windowIdsAtSummon = Set<String>()
    /// How many windows were DRAWN when the shortcut was pressed, measured on the first selection pass of the
    /// summon (see `Windows.selectionInputs`). Newcomers only push the default pick along while the list is
    /// longer than this — one that merely took the tile of a window that left it moved nothing.
    var visibleWindowCountAtSummon: Int?
    /// Keeps one-per-app tiles from changing identity while discovery, grouping and search settle.
    var representativeByPid = [pid_t: String]()
    var searchQuery: String = ""

    /// Full-resolution frames for the Preview panel, fetched just-in-time for the selected window and
    /// its cycling neighbors (`WindowThumbnails.fetchPreviewFrames`, #5861). Living on the session, they
    /// are released wholesale when it ends, so idle RAM only holds thumbnail-scale images. Capped +
    /// least-recently-used-evicted so a long session arrow-keying through many windows stays bounded.
    private static let maxPreviewFrames = 10
    private var previewFrames = [CGWindowID: CALayerContents]()
    private var previewFramesLru = [CGWindowID]() // most recently used last

    func hasPreviewFrame(_ wid: CGWindowID) -> Bool { previewFrames[wid] != nil }

    func previewFrame(_ wid: CGWindowID) -> CALayerContents? {
        guard let frame = previewFrames[wid] else { return nil }
        previewFramesLru.removeAll { $0 == wid }
        previewFramesLru.append(wid)
        return frame
    }

    func storePreviewFrame(_ wid: CGWindowID, _ frame: CALayerContents) {
        previewFrames[wid] = frame
        previewFramesLru.removeAll { $0 == wid }
        previewFramesLru.append(wid)
        if previewFramesLru.count > Self.maxPreviewFrames {
            previewFrames.removeValue(forKey: previewFramesLru.removeFirst())
        }
    }
}
