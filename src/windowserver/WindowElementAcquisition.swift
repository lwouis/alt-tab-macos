import Cocoa

/// Impure executor for `WindowAcquisitionPolicy`: resolve an `AXUIElement` for a WindowServer-discovered wid.
/// There is no wid->element API (RE-confirmed: the AX↔wid bridge is one-directional), so this enumerates the
/// owning app's window elements and matches by wid — the cheap `kAXWindows` read for current-Space windows,
/// the remote-token brute-force for other-Space ones. Mach IPC; call off the main thread. No Specs/Tests
/// triad (impure — verified at runtime). See README.md.
enum WindowElementAcquisition {
    enum Resolution {
        case acquired(AXUIElement)
        case malformedApplicationWindows
        case unavailable
    }

    static func resolve(for wid: CGWindowID, pid: pid_t, route: WindowAcquisitionPolicy.Route) -> Resolution {
        let app = AXUIElementCreateApplication(pid)
        // Current Space first: the cheap `kAXWindows` read resolves the wid with no brute-force — the common
        // case, since most newly-discovered windows are on the active Space. The own-process read is routed to
        // main (own-process AX is an in-process AppKit call, not IPC; off-main it races AppKit teardown).
        let currentSpace = AXUIElement.onCorrectThread(pid: pid) { try? app.windows() }
        var observations = [WindowAcquisitionPolicy.ApplicationWindowObservation]()
        for candidate in currentSpace ?? [] {
            let candidateWid = try? candidate.cgWindowId(pid: pid)
            if candidateWid == wid { return .acquired(candidate) }
            guard candidateWid == 0 else { continue }
            let role = try? candidate.attributes([kAXRoleAttribute], pid: pid).role
            observations.append(.init(wid: candidateWid, role: role))
        }
        // Tahoe can poison kAXWindows system-wide, returning AXApplication elements with wid 0. Brute-force
        // uses the same broken service and only burns its 250ms budget; report the distinct failure so discovery
        // can retain the authoritative WindowServer skeleton instead of collapsing the app to one icon.
        if WindowAcquisitionPolicy.applicationWindowsAreMalformed(observations) { return .malformedApplicationWindows }
        // Other Space: the only path is the targeted remote-token brute-force. Skipped for the current-Space
        // -only route and for our own process (always current-Space, and off-main AX on self would crash).
        guard route == .otherSpaceViaBruteForce, pid != AXUIElement.currentProcessPid else { return .unavailable }
        guard let element = AXUIElement.windowByBruteForce(pid, wid) else { return .unavailable }
        return .acquired(element)
    }

    static func element(for wid: CGWindowID, pid: pid_t, route: WindowAcquisitionPolicy.Route) -> AXUIElement? {
        guard case let .acquired(element) = resolve(for: wid, pid: pid, route: route) else { return nil }
        return element
    }
}
