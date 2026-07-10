import Cocoa

/// How to obtain an `AXUIElement` for a WindowServer-discovered wid. SLS discovery yields wids cheaply, but
/// subrole/title/tabs and the raise/minimize/close/fullscreen actions still need an AX element, and there is
/// NO wid→element API (RE-confirmed: the AX↔wid bridge is one-directional), so elements are acquired by
/// enumerate-and-match (then cached). This enum names the two acquisition routes; `WindowElementAcquisition`
/// picks one per newly-discovered wid and executes it.
enum WindowAcquisitionPolicy {
    struct ApplicationWindowObservation: Equatable {
        let wid: CGWindowID?
        let role: String?
    }

    /// How to get the AX element for a newly-discovered wid.
    enum Route: Equatable {
        case currentSpaceViaApplicationWindows  // cheap: AXUIElementCreateApplication(pid).kAXWindows, match by wid
        case otherSpaceViaBruteForce            // _AXUIElementCreateWithRemoteToken enumeration, targeted + cached
    }

    /// `kAXWindows` must contain window elements. Tahoe can instead return application elements whose wid is
    /// zero; that is a distinct system failure, not an ordinary missing/off-Space window, so WindowServer-only
    /// discovery is safe to enable for this app until AX recovers.
    static func applicationWindowsAreMalformed(_ observations: [ApplicationWindowObservation]) -> Bool {
        observations.contains { $0.wid == 0 && $0.role == kAXApplicationRole }
    }

    static func windowServerFallbackIsEligible(wid: CGWindowID, level: Int32, size: CGSize) -> Bool {
        wid != 0 && level == WsWindowState.applicationWindowLevel && size.width > 100 && size.height > 50
    }
}
