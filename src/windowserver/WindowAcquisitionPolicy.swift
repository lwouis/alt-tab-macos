import Cocoa

/// How to obtain an `AXUIElement` for a WindowServer-discovered wid. SLS discovery yields wids cheaply, but
/// subrole/title/tabs and the raise/minimize/close/fullscreen actions still need an AX element, and there is
/// NO wid→element API (RE-confirmed: the AX↔wid bridge is one-directional), so elements are acquired by
/// enumerate-and-match (then cached). This enum names the two acquisition routes; `WindowElementAcquisition`
/// picks one per newly-discovered wid and executes it.
enum WindowAcquisitionPolicy {
    /// How to get the AX element for a newly-discovered wid.
    enum Route: Equatable {
        case currentSpaceViaApplicationWindows  // cheap: AXUIElementCreateApplication(pid).kAXWindows, match by wid
        case otherSpaceViaBruteForce            // _AXUIElementCreateWithRemoteToken enumeration, targeted + cached
    }
}
