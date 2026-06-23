import Cocoa

/// Impure executor for `WindowAcquisitionPolicy`: resolve an `AXUIElement` for a WindowServer-discovered wid.
/// There is no wid->element API (RE-confirmed: the AX↔wid bridge is one-directional), so this enumerates the
/// owning app's window elements and matches by wid — the cheap `kAXWindows` read for current-Space windows,
/// the remote-token brute-force for other-Space ones. Mach IPC; call off the main thread. No Specs/Tests
/// triad (impure — verified at runtime). See README.md.
enum WindowElementAcquisition {
    static func element(for wid: CGWindowID, pid: pid_t, route: WindowAcquisitionPolicy.Route) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        // Current Space first: the cheap `kAXWindows` read resolves the wid with no brute-force — the common
        // case, since most newly-discovered windows are on the active Space. The own-process read is routed to
        // main (own-process AX is an in-process AppKit call, not IPC; off-main it races AppKit teardown).
        let currentSpace = AXUIElement.onCorrectThread(pid: pid) { try? app.windows() }
        if let found = currentSpace?.first(where: { (try? $0.cgWindowId()) == wid }) {
            return found
        }
        // Other Space: the only path is the targeted remote-token brute-force. Skipped for the current-Space
        // -only route and for our own process (always current-Space, and off-main AX on self would crash).
        guard route == .otherSpaceViaBruteForce, pid != AXUIElement.currentProcessPid else { return nil }
        return AXUIElement.windowByBruteForce(pid, wid)
    }
}
