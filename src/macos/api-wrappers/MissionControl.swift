import Cocoa

/// Whether Mission Control, App Exposé or Show Desktop is on screen right now.
///
/// Two sources, and the second is the only one left on macOS 27:
///
/// - the Dock's `AXExpose*` notifications (`DockEvents`), which up to macOS 26 arrive as the gesture starts.
///   On 27 the Dock accepts the subscription and posts none of the four, ever. Measured 2026-09-16 on
///   26A428, together with the two routes yabai uses (the WindowServer's connection notification 1204, and
///   the Dock's unnamed layer-18 window), which are dead the same way. Nothing errors and the subscription
///   still reports success, so a build that never learns looks exactly like one that did.
/// - the OVERLAY the window manager draws for the duration of the gesture. It is an observation rather than
///   an announcement, so it cannot go stale, and it tells the three apart on its own: the shield is common
///   to Mission Control and App Exposé, and only Mission Control puts the Spaces bar over it.
///
/// The overlay wins when it says something is up, and the notification answers otherwise. That keeps the
/// versions that still announce exactly as they were (including macOS 12, where the overlay belongs to no
/// separate process and this never fires), and it is also the safer way round: the observation is what
/// recovers when an exit notification is missed.
class MissionControl {
    private static let lock = NSLock()
    /// What the Dock last announced. On macOS 27 this stays `.inactive` for the life of the process.
    private static var announced = MissionControlState.inactive
    /// What the overlay last showed, and when it was looked at.
    private static var observed = MissionControlState.inactive
    private static var lastLookAt = 0.0
    /// A surface came or went since the last look began, so `observed` may be behind the screen. True at
    /// launch, so the first question is answered by a look rather than by the initial value.
    private static var changesSinceLook = true
    private static var lookScheduled = false
    /// While the last look saw a gesture up, an answer this old is refreshed before it is trusted: a stale
    /// yes costs the user a focus or a summon, which is the expensive direction to be wrong in.
    private static let maxAge = 0.1
    /// The overlay's window is created a beat before it is on screen (17ms, measured), so the look that a
    /// create triggers waits for it. Doubles as the coalescing window for the burst: one gesture creates
    /// five windows and has one state.
    private static let settleDelay = 0.15

    /// No round trip in the ordinary case. The overlay can only have moved if a surface came or went since
    /// the last look, and every such arrival reaches `surfacesChanged`, so a cache with nothing pending is
    /// exact whatever its age. The `CGWindowListCopyWindowInfo` (0.245ms p50, 0.43ms p95 measured, and it
    /// grows with the on-screen list) is paid on the caller's thread only when a change is still inside its
    /// settle window, or while the cache says a gesture is up (`maxAge`).
    static func state() -> MissionControlState {
        if needsFreshLook() { look() }
        lock.lock()
        defer { lock.unlock() }
        return observed == .inactive ? announced : observed
    }

    /// The Dock announced a gesture. Recorded whatever the overlay says, so the two never disagree about
    /// which source was heard from.
    static func setState(_ state: MissionControlState) {
        lock.lock()
        let changed = announced != state
        announced = state
        lock.unlock()
        if changed { Logger.info { "missionControl announced \(state.rawValue)" } }
    }

    /// A WindowServer surface came or went. The overlay's create and destroy travel on that same stream, so
    /// this is what makes the gesture known WHILE it is up instead of at the next question: `updatesBeforeShowing`
    /// and `focusSelectedWindow` then read a state that is already there, and a capture records the moment.
    /// Coalesced on the trailing edge, so a burst of window events costs one look, and that look runs on
    /// the WindowServer-read lane: every window created anywhere (a tooltip, a menu) lands here, and none of
    /// them is worth a round trip on the main thread.
    static func surfacesChanged() {
        lock.lock()
        defer { lock.unlock() }
        changesSinceLook = true
        guard !lookScheduled else { return }
        lookScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) {
            lock.lock()
            lookScheduled = false
            lock.unlock()
            CGSCallScheduler.run { look() }
        }
    }

    private static func needsFreshLook() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if changesSinceLook { return true }
        return observed != .inactive && ProcessInfo.processInfo.systemUptime - lastLookAt > maxAge
    }

    /// Cleared BEFORE the read, so a surface arriving during it is looked at again rather than lost.
    private static func look() {
        lock.lock()
        changesSinceLook = false
        lock.unlock()
        let state = overlayState()
        lock.lock()
        let changed = observed != state
        observed = state
        lastLookAt = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        if changed { Logger.info { "missionControl observed \(state.rawValue)" } }
    }

    private static func overlayState() -> MissionControlState {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [CGWindow] ?? []
        let surfaces = windows.map { MissionControlOverlay.Surface(ownerName: $0.ownerName(), layer: $0.layer(), bounds: $0.bounds()) }
        switch MissionControlOverlay.gesture(surfaces, screenSizes: displaySizes()) {
        case .missionControl: return .showAllWindows
        case .appExpose: return .showFrontWindows
        case .showDesktop: return .showDesktop
        case .none: return .inactive
        }
    }

    /// CoreGraphics rather than `NSScreen`: `look` runs on the WindowServer-read lane, and these are in the
    /// same point space as `kCGWindowBounds`.
    private static func displaySizes() -> [CGSize] {
        var count = UInt32(0)
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0).size }
    }
}
