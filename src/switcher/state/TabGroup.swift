import Cocoa

/// THE single owner of tab-group membership — the write funnel every grouping mutation goes through.
///
/// Membership is NORMALIZED here, and `Window.isTabbed` / `tabbedSiblingWids` are DERIVED reads over it —
/// never storage, and never written from anywhere else. A wid belongs to AT MOST one group, a group always
/// has ≥ 2 members and exactly ONE representative (the member it shows). Storing membership per-window
/// instead makes a whole bug class REPRESENTABLE rather than merely detected-and-repaired: two groups
/// claiming one window, members disagreeing on their links, the focused window flagged tabbed and hidden
/// with nothing to correct it (rec8/10). Every mutation logs one line, so "who tabbed this window?" is one
/// grep. Main-thread only, like the `Windows` model it annotates.
///
/// The tables and mutation semantics live in the pure `TabGroupsTable` (shared with `TrackedWindowState`, so the
/// event-replay reducer and the live model run ONE implementation); this class binds them to the live
/// world — `TabGroupResolver` re-picks over live snapshots, the log lines.
///
/// Nearly every mutation now happens inside the reducer and arrives here as a whole table (`replace`). The
/// one exception is `remove`, called from `Windows.removeWindows`: the reducer asks the shell to drop a
/// window and never sees the shortened list until the next snapshot, so the group shrink has to happen live.
class TabGroups {
    private(set) static var table = TabGroupsTable()

    /// groupId → ordered member wids (order = AX title order / geometry order; ≥ 2 by construction)
    static var membersByGroup: [Int: [CGWindowID]] { table.membersByGroup }
    /// groupId → the member the group shows (its active tab). Every group has exactly one.
    static var representativeByGroup: [Int: CGWindowID] { table.representativeByGroup }

    static func groupId(of wid: CGWindowID) -> Int? { table.groupId(of: wid) }

    static func siblingWids(of wid: CGWindowID) -> [CGWindowID]? { table.siblingWids(of: wid) }

    static func isTabbed(_ wid: CGWindowID) -> Bool { table.isTabbed(wid) }

    /// Does this group have a CLAIM TO THE SCREEN — a member on some Space, or one held through a tab swap?
    /// The phantom exemption for group members rides on this: a live group's background tabs are legitimately
    /// Space-less and its representative must show, but a group whose EVERY member is Space-less is dead
    /// remains (Finder retains destroyed tab windows), and exempting those kept a ghost tile visible forever
    /// and shielded the corpses from the dead-window sweep (rec22).
    static func hasScreenClaim(_ gid: Int) -> Bool {
        table.hasScreenClaim(gid) { wid in
            !(Windows.byWindowId[wid]?.spaceIds.isEmpty ?? true) || Windows.windowsHeldVisibleForTab.contains(wid)
        }
    }

    /// Take `wid` out of its group: the window was destroyed. Its group shrinks; with ≤ 1 member left it
    /// dissolves (a single window can't be a tab group). A member that leaves KEEPS the Space its group lent
    /// it, still marked borrowed — see `Window.spaceIsBorrowed` for why stripping it hid live windows.
    static func remove(_ wid: CGWindowID, reason: String) {
        var t = table
        let m = t.remove(wid, reason: reason, repPicker: repPicker)
        table = t
        for line in m.logs { Logger.debug { line } }
    }

    /// Adopt the tables a reducer pass computed (`TrackedWindowStateBridge.apply`). The reducer already
    /// returned the log lines as effects, so this is a plain swap.
    static func replace(_ newTable: TabGroupsTable) {
        table = newTable
    }

    /// Re-pick a shrunk group's representative — the kernel decides, over snapshots taken against the
    /// MID-MUTATION tables (the shrunk member list is already written, so the links are coherent), and its
    /// focused-member rule recovers a group whose visible was stolen.
    ///
    /// Goes through the SAME projection the reducer uses (`TrackedWindowState.tabWindow`), assembled from a
    /// minimal state holding just these windows and the mid-mutation table. Never add a live-only second copy
    /// of that projection: one drifted here silently, forwarding neither `lastLeftSpaceId` nor the handover
    /// edge, so the live model and the replayed one handed a kernel different facts. The synthetic-fact rule
    /// (rec14/15/20/21) is only a rule if there is one place to break it.
    private static func repPicker(_ remaining: [CGWindowID], _ mid: TabGroupsTable) -> CGWindowID? {
        var state = TrackedWindowState()
        state.groups = mid
        state.held = Windows.windowsHeldVisibleForTab
        state.windows = remaining.compactMap { Windows.byWindowId[$0] }.map { TrackedWindowStateBridge.modelWindow($0) }
        return TabGroupResolver.groupRepresentative(state.windows.map { state.tabWindow($0) })
    }
}

/// What is left of the impure OS-tab adapter, now that the orchestration lives in `WindowEventReducer` and
/// the `Window` ⇄ `TabWindow` projection lives in `TrackedWindowState`. See `TabGroupResolverSpecs.md` for
/// the decision logic and its scenarios.
class TabGroup {
    /// Find the active tab (non-isTabbed) sibling in the same tab group.
    static func activeTabSibling(of window: Window) -> Window? {
        guard let siblingWids = window.tabbedSiblingWids else { return nil }
        return Windows.list.first { sibling in
            sibling !== window && !sibling.isTabbed
                && sibling.cgWindowId != nil && siblingWids.contains(sibling.cgWindowId!)
        }
    }
}
