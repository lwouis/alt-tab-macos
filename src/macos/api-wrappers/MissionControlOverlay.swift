import CoreGraphics

/// Reads which gesture is up from the window manager's own overlays, recognised by OWNER, LEVEL and SIZE
/// rather than by name. `kCGWindowName` would name them outright (`ExposeShieldWindow`, `Spaces Bar`,
/// `ShowDesktopOverlay`) but it is gated on Screen Recording, which a user running without thumbnails may
/// never have granted, and a detector that reads "no gesture is ever up" for those users is worse than
/// none. Owner name, level and bounds are not gated. Its Stage Manager and highlight surfaces are at 0 to 2.
enum MissionControlOverlay {
    struct Surface {
        let ownerName: String?
        let layer: Int?
        let bounds: CGRect?
    }

    enum Gesture {
        case none, missionControl, appExpose, showDesktop
    }

    /// Not localized, and not the bundle's display name: this is the process name the WindowServer records
    /// for the surface's owner. macOS 12 has no such process.
    static let windowManagerProcessName = "WindowManager"
    /// **Stage Manager, measured 2026-09-17 and 2026-09-26 on 26A428.** Its own surfaces are one 66×82
    /// `App Icon Window` per stage and a `Gesture Blocking Overlay` at level 0, and a full-screen
    /// `Event Shield Window` at the desktop-icon level, at rest, through every hover of the strip, while
    /// switching stages and while AltTab is up. Some machines have that icon at the shield's level
    /// instead (see `gesture`); what raises it there was not reproduced.
    ///
    /// Show Desktop is the one it hides: with Stage Manager on, macOS draws no `ShowDesktopOverlay` at all
    /// and reveals the desktop by removing the event shield instead, so `.showDesktop` never fires there.
    /// Both readers treat `.showDesktop` exactly as `.inactive`, so nothing downstream changes.
    static let exposeShieldLevel = 19
    static let showDesktopOverlayLevel = 18
    static let spacesBarLevel = 14

    /// The shield counts only when it covers a whole screen. Outside of any gesture, some machines on macOS 27
    /// list a 66×82 surface at the shield's level, off-screen, while an app window is focused: its size and
    /// place are those of a Stage Manager stage icon with the strip hidden. With several stages there is one
    /// per stage. Read as a shield, it made every summon abort as if App Exposé were up
    /// (`testSmallSurfaceAtShieldLevelIsNotAGesture`).
    static func gesture(_ surfaces: [Surface], screenSizes: [CGSize]) -> Gesture {
        var hasShield = false, hasSpacesBar = false, hasShowDesktop = false
        for surface in surfaces where surface.ownerName == windowManagerProcessName {
            switch surface.layer {
            case exposeShieldLevel: hasShield = hasShield || coversAScreen(surface.bounds, screenSizes)
            case showDesktopOverlayLevel: hasShowDesktop = true
            case spacesBarLevel: hasSpacesBar = true
            default: continue
            }
        }
        if hasShield { return hasSpacesBar ? .missionControl : .appExpose }
        return hasShowDesktop ? .showDesktop : .none
    }

    /// Sizes only: CG bounds are top-left based and NSScreen frames bottom-left based, and a shield that
    /// covers a screen has at least that screen's size wherever it sits.
    private static func coversAScreen(_ bounds: CGRect?, _ screenSizes: [CGSize]) -> Bool {
        guard let bounds else { return false }
        return screenSizes.contains { bounds.width >= $0.width && bounds.height >= $0.height }
    }
}
