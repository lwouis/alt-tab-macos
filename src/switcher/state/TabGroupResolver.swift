import CoreGraphics

/// The window facts tab-grouping decisions need, lifted off the `Window` class into a flat,
/// test-constructible record — the tab-grouping analogue of `WindowState` (which omits `pid` / `wid` /
/// `size` / `position` / `tabbedSiblingWids`, all of which live on `Window` and all of which grouping
/// reads). Primitive types only (`CGWindowID` / `CGSize` / `CGPoint` / `UInt64`), so the kernel and its
/// tests compile without `Spaces` / SkyLight / the `Window` graph. The impure `TabGroup` adapter maps
/// `Window` ⇄ `TabWindow`, calls the kernel, and applies the decisions back onto the live model.
struct TabWindow: Equatable {
    var pid: pid_t
    var wid: CGWindowID
    var size: CGSize?
    var position: CGPoint?
    var spaceIds: [UInt64]                  // CGSSpaceID === UInt64
    var title: String
    var isTabbed: Bool
    var isFullscreen: Bool
    var isMinimized: Bool
    var tabbedSiblingWids: [CGWindowID]?
}

/// A tab group inferred purely from geometry (no AX): the visible tab (holds a Space) plus the
/// background tabs (Space-less) that share its app + size.
struct GeometryGroup: Equatable {
    var visibleWid: CGWindowID
    var backgroundWids: [CGWindowID]
    var siblingWids: [CGWindowID] { [visibleWid] + backgroundWids }
}

/// The outcome of matching an active tab's AXTabGroup titles to tracked windows.
struct SiblingMatch: Equatable {
    /// the group's wids, active first then matched, in AX title order
    var siblingWids: [CGWindowID]
    /// the windows we matched as inactive tabs (subset of `siblingWids`, active excluded)
    var matchedWids: [CGWindowID]
    /// AXTabGroup titles with no tracked window — inactive tabs to brute-force-discover
    var untrackedTitles: [String]
    /// same-app windows no longer in this group whose stale tab state must be cleared
    var toUntabWids: [CGWindowID]
}

/// The outcome of shrinking a tab group after a member leaves (window destroyed, or active tab dragged
/// out and gone standalone). Either dissolve (a lone remaining window can't be a tab group) or shrink.
struct GroupDissolution: Equatable {
    /// the group's wids after the member left (the new `tabbedSiblingWids` for survivors when shrinking)
    var remainingSiblingWids: [CGWindowID]
    /// the still-tracked survivors to mutate
    var applyToWids: [CGWindowID]
    /// true ⇒ clear tab state on the survivors (≤ 1 left); false ⇒ shrink their group to `remainingSiblingWids`
    var dissolve: Bool
}

/// Pure decisions behind OS-tab detection, extracted from `TabGroup` so the brittle parts — the
/// geometry inference and the AX-title sibling matching (the documented "match tabs to windows by title"
/// limitation, see `TabbedWindowDetection.swift`) — are unit-testable without the `Window` graph. The
/// `TabGroup` adapter owns the `Windows.list` reads/writes; this kernel only decides. See
/// `TabGroupResolverSpecs.md`.
enum TabGroupResolver {
    /// Within one app, windows sharing an exact size are tabs of a single window; the visible tab keeps
    /// its Space while background tabs are Space-less (CGS lists no background tab on any Space). A
    /// SEPARATE real window is never Space-less, so it can't be mistaken for a background tab. Key on
    /// app + SIZE, not the full frame: a background tab's POSITION goes stale while it's ordered out (no
    /// geometry event), so a position key would never match it. Minimized / size-less windows are out.
    /// Result is sorted by `visibleWid` for deterministic output.
    static func geometryGroups(_ windows: [TabWindow]) -> [GeometryGroup] {
        let candidates = windows.filter { !$0.isMinimized && $0.size != nil }
        guard candidates.count > 1 else { return [] }
        var groups = [GeometryGroup]()
        for (_, group) in Dictionary(grouping: candidates, by: { sizeKey($0) }) where group.count > 1 {
            // attach every Space-less tab to ONE visible parent; leave other visible same-size windows
            // out, so genuinely separate windows aren't collapsed (AX refines membership on the review).
            guard let visible = group.first(where: { !$0.spaceIds.isEmpty }) else { continue }
            // Only geometry-group behind a visible tab AX already confirmed (`tabbedSiblingWids != nil`), OR a
            // fullscreen visible window (whose tabs AX can't read). Geometry alone is not enough to CREATE a
            // group: separate windows of one app routinely share a default size (every Terminal window is the
            // same size) and go briefly Space-less during a Space transition or a flaky CGS read, which looked
            // exactly like a background tab and collapsed real windows into a phantom tab group (#5830). The
            // two exemptions keep the cases AX can't cover: re-linking a tab switch on an already-known group
            // (visible keeps its `tabbedSiblingWids`), and a tab added to an already-fullscreen window. The
            // fullscreen branch can't false-positive: only a real background tab is both fullscreen-SIZED and
            // Space-less (a separate fullscreen window holds its own fullscreen Space; a normal window isn't
            // fullscreen-sized).
            guard visible.isFullscreen || visible.tabbedSiblingWids != nil else { continue }
            let background = group.filter { $0.spaceIds.isEmpty }
            guard !background.isEmpty else { continue }
            groups.append(GeometryGroup(visibleWid: visible.wid, backgroundWids: background.map { $0.wid }))
        }
        return groups.sorted { $0.visibleWid < $1.visibleWid }
    }

    /// A rounded app + size key. Tabs of one window share a size; position is NOT in the key because a
    /// background tab's position goes stale while it's ordered out.
    private static func sizeKey(_ window: TabWindow) -> String {
        let s = window.size ?? .zero
        return "\(window.pid)-\(Int(s.width.rounded()))x\(Int(s.height.rounded()))"
    }

    /// Match an active tab's AXTabGroup titles to tracked same-app windows. `sameAppWindows` may include
    /// the active tab itself (filtered out by wid). The active tab's own title is removed once from the
    /// title list (there may be duplicate titles); each remaining title is matched to the first
    /// compatible, not-yet-matched window that is PLAUSIBLY an inactive tab (already tabbed or Space-less —
    /// an on-screen window is never claimed). A window already tabbed into THIS group is then kept even if no
    /// title named it, so a duplicate/renamed title can't flap an inactive tab out of its group (#5830).
    /// Titles with no tracked window are returned as `untrackedTitles` (inactive tabs to discover); windows
    /// that were in this group but are no longer tabbed (became standalone) are returned as `toUntabWids`.
    static func matchSiblings(active: TabWindow, axTitles: [String], sameAppWindows: [TabWindow]) -> SiblingMatch {
        var remainingTitles = axTitles
        if let i = remainingTitles.firstIndex(of: active.title) { remainingTitles.remove(at: i) }
        var matchedWids = [CGWindowID]()
        var matchedTitles = [String]()
        for title in remainingTitles {
            if let sibling = sameAppWindows.first(where: { s in
                s.wid != active.wid && s.title == title
                    && !matchedWids.contains(s.wid)
                    // Only a window that is PLAUSIBLY an inactive tab can be claimed: already tabbed, or
                    // Space-less (an inactive tab is on no Space; 1325/1326 keep that live). An on-screen
                    // window is by definition NOT an inactive tab — without this, a NEW same-title window
                    // (Finder cmd-N, duplicate titles) was claimed to fill a title whose real tab has no
                    // window (Finder destroys a backgrounded tab's window), and vanished from the switcher.
                    && (s.isTabbed || s.spaceIds.isEmpty)
                    && positionsCompatible(active, s)
            }) {
                matchedWids.append(sibling.wid)
                matchedTitles.append(sibling.title)
            }
        }
        // Stability (#5830): a window already in THIS group and still tabbed stays in it even when the AX
        // titles don't name it. Terminal's tabs all read "~" and get renamed by cwd/command, so a title miss
        // must not eject an inactive tab from its own group (the "cause-B flap") — it would flash out as a
        // separate window and re-trigger discovery. Keyed on `tabbedSiblingWids` containing the active wid, so
        // a DIFFERENT group's tabs (same app) are left alone. A tab that truly left (drag-out) has its
        // `isTabbed` cleared by its own AX read first, so it is not kept and falls through to `toUntabWids`.
        let keptWids = sameAppWindows.filter { s in
            s.wid != active.wid && !matchedWids.contains(s.wid) && s.isTabbed
                && s.tabbedSiblingWids?.contains(active.wid) == true
        }.map { $0.wid }
        matchedWids.append(contentsOf: keptWids)
        var untrackedTitles = remainingTitles
        for title in matchedTitles {
            if let i = untrackedTitles.firstIndex(of: title) { untrackedTitles.remove(at: i) }
        }
        // each kept sibling accounts for one AX title we couldn't name — don't re-discover a tab we hold.
        for _ in keptWids where !untrackedTitles.isEmpty { untrackedTitles.removeFirst() }
        // Un-tab only windows that WERE in this group but are neither matched nor kept — their `isTabbed` was
        // cleared (they became standalone). A different group's tabs never contain the active wid.
        let toUntabWids = sameAppWindows.filter { s in
            s.wid != active.wid && !matchedWids.contains(s.wid) && s.tabbedSiblingWids?.contains(active.wid) == true
        }.map { $0.wid }
        return SiblingMatch(siblingWids: [active.wid] + matchedWids, matchedWids: matchedWids,
            untrackedTitles: untrackedTitles, toUntabWids: toUntabWids)
    }

    /// Tabs of one window share the parent's geometry. If both positions are known and differ noticeably,
    /// the candidate is no longer in the same window (likely dragged out). When either position is
    /// unknown, or either is fullscreen (a fullscreen window's tabs can't share its frame, and an inactive
    /// tab's position goes stale when its parent fullscreens), fall back to a title-only match. An
    /// existing tab link is respected so a stale position can't split an already-grouped pair (e.g. after
    /// Merge All Windows, where tabs keep distinct pre-merge positions).
    static func positionsCompatible(_ a: TabWindow, _ b: TabWindow) -> Bool {
        if b.tabbedSiblingWids?.contains(a.wid) == true { return true }
        guard let pa = a.position, let pb = b.position, !a.isFullscreen, !b.isFullscreen else { return true }
        return abs(pa.x - pb.x) < 50 && abs(pa.y - pb.y) < 50
    }

    /// Decide a group's fate when `leavingWid` leaves it (destroyed, or an active tab gone standalone).
    /// `presentWids` are the wids still tracked in the model. ≤ 1 survivor ⇒ dissolve (a single window
    /// can't be a tab group); otherwise shrink the survivors' group to the remaining wids.
    static func dissolution(siblingWids: [CGWindowID], leaving leavingWid: CGWindowID,
                            presentWids: Set<CGWindowID>) -> GroupDissolution {
        let remaining = siblingWids.filter { $0 != leavingWid }
        let present = remaining.filter { presentWids.contains($0) }
        return GroupDissolution(remainingSiblingWids: remaining, applyToWids: present, dissolve: present.count <= 1)
    }
}
