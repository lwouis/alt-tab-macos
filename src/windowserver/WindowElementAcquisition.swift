import Cocoa

/// Impure executor for `WindowAcquisitionPolicy`: resolve an `AXUIElement` for a WindowServer-discovered wid.
/// There is no wid->element API (RE-confirmed: the AX↔wid bridge is one-directional), so this enumerates the
/// owning app's window elements and matches by wid — one batched attribute read
/// (`windowsIncludingKeyAndMain`) covers the current Space plus the app's key/main window whatever Space that
/// is on, and the remote-token brute-force covers the rest. The inventory batches all requested wids of one
/// process through both reads; event paths can still ask for one. Mach IPC; call off the main thread. No
/// Specs/Tests triad (impure — verified at runtime). See README.md.
enum WindowElementAcquisition {
    /// **"Not found" and "could not ask" are different answers**, and one caller condemns a window on the
    /// first (`Applications.removeIfClosedAfterOrderOut`). So `.absent` requires the app to list its windows
    /// AND every listed element's window-id read to succeed: a busy app that fails either read must not look
    /// like an app reporting the window gone.
    enum Outcome: Equatable {
        /// the app listed its windows and this wid is among them
        case found(AXUIElement)
        /// the app answered, and this wid is NOT one of its windows: real evidence the window is gone
        case absent
        /// enumeration or window-id matching was incomplete. The caller must retry, never condemn.
        case noAnswer
    }

    /// Resolve one inventory pass's complete wid set for a process. The app's published windows are read
    /// once, then every wid they did not cover shares one remote-token traversal and one 250ms budget. Missing
    /// entries are not an absence verdict: the traversal is time-bounded, so the caller retains its existing
    /// retry policy.
    /// Takes the WindowServer rows rather than bare wids so the unresolved log can name each surface's level
    /// and tags: a repeatedly-unresolved surface is triaged by what it IS, and those two fields separate
    /// desktop furniture from a window the sweep is failing to reach.
    static func elements(for rows: [WsRawWindow], pid: pid_t,
                         route: WindowAcquisitionPolicy.Route) -> [CGWindowID: AXUIElement] {
        let wids = Set(rows.map { $0.wid })
        guard !wids.isEmpty else { return [:] }
        let app = AXUIElementCreateApplication(pid)
        let published = AXUIElement.onCorrectThread(pid: pid) { (try? app.windowsIncludingKeyAndMain()) ?? [] }
        var found = [CGWindowID: AXUIElement]()
        found.reserveCapacity(wids.count)
        for element in published {
            // First wins, like the brute-force merge below. `published` is ordered `kAXWindows` first, so an
            // app that names one wid twice with two different elements keeps its canonical window-list one
            // over the `kAXFocusedWindow` / `kAXMainWindow` ivar read.
            guard let wid = try? element.cgWindowId(pid: pid), wids.contains(wid), found[wid] == nil else { continue }
            found[wid] = element
        }
        guard route == .otherSpaceViaBruteForce, pid != AXUIElement.currentProcessPid else { return found }
        let missing = wids.subtracting(Set(found.keys))
        found.merge(AXUIElement.windowsByBruteForce(pid, missing)) { current, _ in current }
        let unresolved = rows.filter { found[$0.wid] == nil }.sorted { $0.wid < $1.wid }
        if !unresolved.isEmpty {
            Logger.debug { "AX unavailable for physical surfaces (pid:\(pid) "
                + unresolved.map { "wid:\($0.wid) level:\($0.level) tags:0x\(String($0.tags, radix: 16))" }
                    .joined(separator: " ") + ")" }
        }
        return found
    }

    static func element(for wid: CGWindowID, pid: pid_t, route: WindowAcquisitionPolicy.Route) -> AXUIElement? {
        if case let .found(element) = outcome(for: wid, pid: pid, route: route) { return element }
        return nil
    }

    static func outcome(for wid: CGWindowID, pid: pid_t, route: WindowAcquisitionPolicy.Route) -> Outcome {
        let app = AXUIElementCreateApplication(pid)
        // The app's own answer first: one batched read resolves the wid with no brute-force — the common case,
        // since most newly-discovered windows are on the active Space. The own-process read is routed to main
        // (own-process AX is an in-process AppKit call, not IPC; off-main it races AppKit teardown).
        var appAnswered = true
        let published = AXUIElement.onCorrectThread(pid: pid) { () -> [AXUIElement]? in
            do { return try app.windowsIncludingKeyAndMain() } catch { appAnswered = false; return nil }
        }
        for element in published ?? [] {
            do {
                if try element.cgWindowId(pid: pid) == wid { return .found(element) }
            } catch {
                appAnswered = false
            }
        }
        // Other Space, and not the app's key/main window: the only path left is the targeted remote-token
        // brute-force. Skipped for the current-Space-only route and for our own process (always current-Space,
        // and off-main AX on self would crash).
        guard route == .otherSpaceViaBruteForce, pid != AXUIElement.currentProcessPid else {
            return appAnswered ? .absent : .noAnswer
        }
        if let result = AXUIElement.windowByBruteForce(pid, wid) { return .found(result) }
        Logger.debug { "AX unavailable for physical surface (pid:\(pid) wid:\(wid))" }
        // The sweep is time-budgeted, so exhausting it is not proof the window is gone either.
        return .noAnswer
    }
}
