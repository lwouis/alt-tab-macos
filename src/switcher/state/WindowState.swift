import Foundation

/// The canonical, test-constructible data record of a `Window`. One type, used by every kernel that
/// operates on window facts (`WindowFilterResolver`, `WindowOrderResolver`, `ExceptionMatcher`) —
/// replaces the per-feature mirror structs. DERIVED, not stored: both sides project it from the record
/// they hold (`TrackedWindow.storedWindowState`, then the derived facts patched in by `Window.state` or
/// `TrackedWindowState.windowState(_:)`). Constructed directly in tests.
///
/// **No nested `ApplicationState`**: kernels that also need application facts take it as a separate
/// parameter alongside the window state. This avoids two mutable copies of the same app data going
/// out of sync (one on `Application`, one nested inside each `WindowState`).
///
/// `spaceIds` / `spaceIndexes` use the underlying primitive types (`UInt64` / `Int`) rather than the
/// app-only `CGSSpaceID` / `SpaceIndex` typealiases, so this file compiles in the unit-tests target
/// without dragging in `Spaces` / SkyLight.
struct WindowState: Equatable {
    // periphery:ignore - read by the synthesized Equatable
    var id: String
    var isPhantom: Bool
    var isWindowlessApp: Bool
    var isFullscreen: Bool
    var isMinimized: Bool
    var isTabbed: Bool
    /// A tab kept visible through the new-tab discovery gap (`Windows.windowsHeldVisibleForTab`). Like
    /// `isPhantom`/`isTabbed` it is DERIVED (patched into `state` by the live `Window`), never stored raw.
    /// The switcher's Space/screen filters read it: a held tab just backgrounded on the CURRENT visible
    /// Space, so it is Space-less (its 1326 landed) yet must still draw one tile — see `WindowFilterResolver`.
    var isHeldVisibleForTab = false
    var isOnAllSpaces: Bool
    var spaceIds: [UInt64]          // CGSSpaceID === UInt64
    var spaceIndexes: [Int]         // SpaceIndex === Int
    var lastFocusOrder: Int
    var creationOrder: Int
    var title: String
    // cached AXMain (is this the app's main window). Read off-main with the other window attributes; used only
    // as the one-window-per-app cold-start fallback when attention has not named a representative.
    var isMainWindow = false
    /// How much AltTab actually KNOWS about this window, as opposed to what the WindowServer says exists.
    /// Defaults to `.axVerified` because every window that comes through the ordinary discovery path was
    /// discriminated against real AX attributes before it was constructed.
    var axStatus = AxSemanticStatus.axVerified
}

/// Which source currently backs a tracked switch destination. Unresolved/rejected physical surfaces live in
/// `WindowSurfaceInventory`, not in the user-facing `Windows` collection.
enum AxSemanticStatus: Equatable {
    case axVerified
    case attentionCandidate
}
