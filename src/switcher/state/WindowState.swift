import Foundation

/// The canonical, test-constructible data record of a `Window`. One type, used by every kernel that
/// operates on window facts (`WindowFilterResolver`, `WindowOrderResolver`, `ExceptionMatcher`) —
/// replaces the per-feature mirror structs. Held as a stored `var state: WindowState` on the live
/// `Window` class (mutated in place when window data changes) and constructed directly in tests.
///
/// **No nested `ApplicationState`**: kernels that also need application facts take it as a separate
/// parameter alongside the window state. This avoids two mutable copies of the same app data going
/// out of sync (one on `Application`, one nested inside each `WindowState`).
///
/// `spaceIds` / `spaceIndexes` use the underlying primitive types (`UInt64` / `Int`) rather than the
/// app-only `CGSSpaceID` / `SpaceIndex` typealiases, so this file compiles in the unit-tests target
/// without dragging in `Spaces` / SkyLight.
struct WindowState: Equatable {
    var id: String
    var isPhantom: Bool
    var isWindowlessApp: Bool
    var isFullscreen: Bool
    var isMinimized: Bool
    var isTabbed: Bool
    var isOnAllSpaces: Bool
    var spaceIds: [UInt64]          // CGSSpaceID === UInt64
    var spaceIndexes: [Int]         // SpaceIndex === Int
    var lastFocusOrder: Int
    var creationOrder: Int
    var title: String
    // cached AXMain (is this the app's main window). Read off-main with the other window attributes so
    // `Windows.findMainWindow` reads a flag instead of doing AX IPC in a sort comparator on the show path.
    var isMainWindow = false
}
