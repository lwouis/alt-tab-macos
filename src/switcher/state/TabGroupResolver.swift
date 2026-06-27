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
    /// compatible, not-yet-matched window. Titles with no tracked window are returned as `untrackedTitles`
    /// (inactive tabs to discover); same-app windows that fall out of the group are returned as
    /// `toUntabWids`.
    static func matchSiblings(active: TabWindow, axTitles: [String], sameAppWindows: [TabWindow]) -> SiblingMatch {
        var remainingTitles = axTitles
        if let i = remainingTitles.firstIndex(of: active.title) { remainingTitles.remove(at: i) }
        var matchedWids = [CGWindowID]()
        var matchedTitles = [String]()
        for title in remainingTitles {
            if let sibling = sameAppWindows.first(where: { s in
                s.wid != active.wid && s.title == title
                    && !matchedWids.contains(s.wid)
                    && positionsCompatible(active, s)
            }) {
                matchedWids.append(sibling.wid)
                matchedTitles.append(sibling.title)
            }
        }
        var untrackedTitles = remainingTitles
        for title in matchedTitles {
            if let i = untrackedTitles.firstIndex(of: title) { untrackedTitles.remove(at: i) }
        }
        let toUntabWids = sameAppWindows.filter {
            $0.wid != active.wid && !matchedWids.contains($0.wid) && $0.tabbedSiblingWids != nil
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
