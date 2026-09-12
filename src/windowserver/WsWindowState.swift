import Cocoa

/// One window's raw fields, read from the WindowServer in a single `SLSWindowQueryWindows` batch
/// (see `WindowServerQuery`). Plain data so `WsWindowState` decoding stays pure and testable.
struct WsRawWindow: Equatable {
    let wid: CGWindowID
    let pid: pid_t
    let attributes: UInt64
    let level: Int32
    let spaceTypeMask: UInt64
    let title: String
    /// Exact WindowServer attachment relationship. Native tab members remain independent roots (`0`), while
    /// AppKit sheets and `addChildWindow` surfaces name their document window here.
    var parentWid: CGWindowID = 0
    /// WindowServer compositing alpha. `0` is a visibility/phantom fact, not semantic rejection.
    var alpha: Float = 1
    /// window frame in top-left-origin global coordinates (origin = AX position, size = AX size). Defaulted
    /// so the pure-decode tests can build a `WsRawWindow` without it; `WindowServerQuery` fills it in live.
    var bounds: CGRect = .zero
    /// `SLSWindowIteratorGetTags` — a SECOND bitfield alongside `attributes`, and the one that carries
    /// minimized/hidden/fullscreen. Defaulted for the same reason as `bounds`; 0 decodes to "none of them",
    /// which is the safe reading for a fixture that doesn't care.
    var tags: UInt64 = 0
}

/// Pure decode of a `WsRawWindow` into the booleans AltTab's model needs. The bit/mask constants were
/// reverse-engineered live (diffing windows across states) — see `WsWindowStateSpecs.md` for the evidence.
enum WsWindowState {
    /// `attributes` bit set while the window is on-screen / ordered-in; cleared when the window is ordered
    /// OUT — which happens for minimize, app-hide, moving to another Space, AND a closing window mid-teardown.
    /// So this is an ordered-in / on-screen signal (used for capture decisions), NOT a minimized signal.
    static let visibleAttribute: UInt64 = 0x2
    /// `tags` bit set exactly while the window is MINIMIZED, and cleared the moment it is restored.
    ///
    /// This replaced the AX `kAXMinimized` read, which was the only source until 2026-08-04 — not because AX
    /// was wrong but because it is a call INTO the window's own app, so it stalls for as long as that app is
    /// busy (~500ms measured mid-animation, and unboundedly for a beach-balling one). This is a field of the
    /// batched WindowServer query we already issue, so it costs nothing extra and cannot be blocked by an app.
    ///
    /// Proven SPECIFIC, not merely correlated (see `WsWindowStateSpecs.md` for the full state matrix): it
    /// stays clear for an `orderOut:` window, an alpha=0 window, an app-hidden window, a fullscreen window
    /// and a background tab — the five states that otherwise look alike from CGS — and it composes
    /// independently with `hiddenTag`. Minimizing a TAB GROUP sets it on every member, active and background
    /// tabs alike, which is the same thing `mirrorActiveTabStateToInactiveTabs` derives.
    static let minimizedTag: UInt64 = 1 << 60
    /// `tags` bit set while the window's APP is hidden (Cmd+H). Not read today — `ApplicationState.isHidden`
    /// comes from AppKit — but recorded here because it is the bit that would otherwise be confused with
    /// `minimizedTag`, and because it proved MORE accurate than AppKit's own flag in the mapping run
    /// (`NSRunningApplication.isHidden` read false while the app was hidden and this bit was set).
    // periphery:ignore - deliberately recorded though unread; see the note above
    static let hiddenTag: UInt64 = 1 << 39
    /// `spaceTypeMask` bit set when the window lives on a fullscreen-type Space.
    static let fullscreenSpaceMask: UInt64 = 0x20
    /// On screen / ordered-in. This is NOT "not minimized": an ordered-out window may be minimized, app-hidden,
    /// on another Space, or closing — `isMinimized` separates the first of those.
    static func isVisible(_ w: WsRawWindow) -> Bool {
        w.attributes & visibleAttribute != 0
    }

    /// Minimized, straight from the WindowServer. Prompt on the way IN (~35ms after the minimize, measured on
    /// TextEdit / Chrome / Finder) but LATE on the way OUT: on a Dock restore the bit only clears when the
    /// animation ends (~644ms), later than AX. So a `true` from this is stale news about a window the
    /// WindowServer has already ordered back in, and the un-minimize is derived from that order-in instead —
    /// see `WindowEventReducer.movedResizedOrOrderedIn`. Callers must apply the same rule the reducer does.
    static func isMinimized(_ w: WsRawWindow) -> Bool {
        w.tags & minimizedTag != 0
    }

    static func isFullscreen(_ w: WsRawWindow) -> Bool {
        w.spaceTypeMask & fullscreenSpaceMask != 0
    }
}
