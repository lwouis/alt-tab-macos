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
    /// window frame in top-left-origin global coordinates (origin = AX position, size = AX size). Defaulted
    /// so the pure-decode tests can build a `WsRawWindow` without it; `WindowServerQuery` fills it in live.
    var bounds: CGRect = .zero
}

/// Pure decode of a `WsRawWindow` into the booleans AltTab's model needs. The bit/mask constants were
/// reverse-engineered live (diffing windows across states) — see `WsWindowStateSpecs.md` for the evidence.
enum WsWindowState {
    /// `attributes` bit set while the window is on-screen / ordered-in; cleared when the window is ordered
    /// OUT — which happens for minimize, app-hide, moving to another Space, AND a closing window mid-teardown.
    /// So this is an ordered-in / on-screen signal (used for capture decisions), NOT a minimized signal.
    /// Minimized is read separately from AX (`kAXMinimized`) — the only reliable, unambiguous source.
    static let visibleAttribute: UInt64 = 0x2
    /// `spaceTypeMask` bit set when the window lives on a fullscreen-type Space.
    static let fullscreenSpaceMask: UInt64 = 0x20
    /// normal application windows sit at level 0; chrome (menu bar, Control Center, wallpaper) does not.
    static let applicationWindowLevel: Int32 = 0

    /// On screen / ordered-in. This is NOT "not minimized": an ordered-out window may be minimized, app-hidden,
    /// on another Space, or closing — those are distinguished elsewhere (minimized comes from AX `kAXMinimized`).
    static func isVisible(_ w: WsRawWindow) -> Bool {
        w.attributes & visibleAttribute != 0
    }

    static func isFullscreen(_ w: WsRawWindow) -> Bool {
        w.spaceTypeMask & fullscreenSpaceMask != 0
    }

    /// A coarse discrimination hint, NOT a subrole replacement: level 0 separates real app windows from
    /// chrome, but cannot tell `AXStandardWindow` from `AXDialog`/`AXUnknown` (tags don't encode that
    /// cleanly). The precise accept/reject still needs the AX subrole in `WindowDiscriminator`.
    static func isApplicationWindowLevel(_ w: WsRawWindow) -> Bool {
        w.level == applicationWindowLevel
    }
}
