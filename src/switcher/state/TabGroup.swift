import Cocoa

class TabGroup {

    /// Parse AXTabGroup children from a prior `.attributes([..., kAXChildrenAttribute])` call.
    /// Returns tab titles if the window has tabs (always >= 2), nil otherwise.
    static func extractTabTitles(_ children: [AXUIElement]?) -> [String]? {
        AXUIElement.tabGroupInfo(children)
    }

    /// Find the active tab (non-isTabbed) sibling in the same tab group.
    static func activeTabSibling(of window: Window) -> Window? {
        guard let siblingWids = window.tabbedSiblingWids else { return nil }
        return Windows.list.first { sibling in
            sibling !== window && !sibling.isTabbed
                && sibling.cgWindowId != nil && siblingWids.contains(sibling.cgWindowId!)
        }
    }

    /// Re-derive the parts of tab state that AX can't keep live: link fullscreen tab siblings AX can't read
    /// (`inferFullscreenTabGroups`) and push the visible tab's fullscreen/minimized onto its inactive siblings
    /// (`mirrorActiveTabStateToInactiveTabs`). Both depend only on geometry/Space/fullscreen facts that change
    /// on WindowServer events, so this runs from those reactive handlers — NOT from the synchronous show path,
    /// where mutating the model mid-render reorders tiles (UI jump). By the time the switcher opens, the model
    /// is already grouped. Cheap and idempotent: both steps no-op when there's nothing to do.
    static func reconcile() {
        inferTabGroupsByGeometry()
        mirrorActiveTabStateToInactiveTabs()
    }

    /// Inactive tabs share their parent window's frame, so an inactive tab is fullscreen/minimized exactly
    /// when its active sibling is. A background tab gets no WindowServer geometry event of its own (only the
    /// visible tab does) and its `isFullscreen` is never read from AX, so those flags would otherwise stay
    /// stale (a fullscreened window's inactive tabs kept showing as non-fullscreen). Mirror the active
    /// sibling onto every inactive tab — the same idea as the spaceIds propagation.
    static func mirrorActiveTabStateToInactiveTabs() {
        for window in Windows.list where window.isTabbed {
            guard let active = activeTabSibling(of: window) else { continue }
            window.isFullscreen = active.isFullscreen
            window.isMinimized = active.isMinimized
        }
    }

    /// Link tab siblings AX can't reconcile in time, from geometry. AX tab titles are read by `updateState`,
    /// but only at discovery and the post-show review — not on a tab switch (order events skip tab reconcile
    /// since the fullscreen-dissolve fix) — and never at all for a fullscreen window (it exposes no readable
    /// AXTabGroup). So after switching tabs, the newly-backgrounded tab is left Space-less (CGS lists no
    /// background tab on any Space) with a stale `isTabbed`, the phantom rule hides it, and it only reappears
    /// on the late post-show pass: the "pop-in". Switching repeatedly just swaps which tab is hidden.
    ///
    /// Geometry settles it reactively: within one app, windows sharing the exact frame are tabs of a single
    /// window; the visible tab keeps its Space while the background tabs are Space-less. A SEPARATE real window
    /// is never Space-less (it always sits on some Space), so it can't be mistaken for a background tab here —
    /// the frame key only disambiguates when an app has several windows. We DISCOVER nothing (a background tab
    /// still enters the list only once focused); we link windows already tracked, set the visible tab as the
    /// group's active one, and backfill each background tab's Space from it — handing off to the normal
    /// machinery (the `isTabbed` phantom exemption, "show every tab"). Frame match can briefly go stale right
    /// after moving a window (the background tab gets no geometry event); it self-corrects on the next event.
    static func inferTabGroupsByGeometry() {
        let candidates = Windows.list.filter { !$0.isWindowlessApp && !$0.isMinimized && $0.cgWindowId != nil && $0.size != nil }
        guard candidates.count > 1 else { return }
        // Key on app + window SIZE, not the full frame: tabs of one window share a size, but a background tab's
        // POSITION goes stale while it's ordered out (it gets no geometry event — after Merge All Windows the
        // tabs keep their pre-merge cascaded positions), so a position-based key would never match them.
        for (_, group) in Dictionary(grouping: candidates, by: { sizeKey($0) }) where group.count > 1 {
            // the visible tab holds the Space; background tabs are Space-less. Attach every Space-less tab to
            // ONE visible parent; leave any other visible same-size windows out, so genuinely separate windows
            // aren't collapsed into one group (the authoritative AX path refines membership on the next review).
            guard let visible = (group.first { !$0.spaceIds.isEmpty }) else { continue }
            let background = group.filter { $0.spaceIds.isEmpty }
            guard !background.isEmpty else { continue }
            let siblingWids = ([visible] + background).compactMap { $0.cgWindowId }
            visible.isTabbed = false
            visible.tabbedSiblingWids = siblingWids
            for tab in background {
                tab.tabbedSiblingWids = siblingWids
                tab.isTabbed = true
                tab.spaceIds = visible.spaceIds
                tab.spaceIndexes = visible.spaceIndexes
                tab.isOnAllSpaces = visible.isOnAllSpaces
                tab.recomputeIsPhantom()
            }
            Logger.debug { "inferred tab group for \(visible.application.runningApplication.localizedName ?? "?"): visible \(visible.cgWindowId!) sp:\(visible.spaceIds), background \(background.compactMap { $0.cgWindowId })" }
        }
    }

    /// A rounded app+size key for geometry tab-matching. Tabs of one window share a size; position is NOT in
    /// the key because a background tab's position goes stale while it's ordered out.
    private static func sizeKey(_ window: Window) -> String {
        let s = window.size ?? .zero
        return "\(window.application.pid)-\(Int(s.width.rounded()))x\(Int(s.height.rounded()))"
    }

    /// When a window is removed from the list, update its former siblings' tab group.
    /// If only 1 sibling remains, clear its tab state (a single window can't be tabbed).
    static func removedWindowFromGroup(wid: CGWindowID?, siblingWids: [CGWindowID]) {
        let remainingWids = siblingWids.filter { $0 != wid }
        let remainingSiblings = Windows.list.filter { w in
            w.cgWindowId != nil && remainingWids.contains(w.cgWindowId!)
        }
        if remainingSiblings.count <= 1 {
            // no longer a tab group
            for s in remainingSiblings {
                s.tabbedSiblingWids = nil
                s.isTabbed = false
            }
        } else {
            // shrink the group
            for s in remainingSiblings {
                s.tabbedSiblingWids = remainingWids
            }
        }
    }

    /// Update tab state for a window and its siblings using AX-discovered tab titles.
    /// Resolves titles to WIDs, propagates space info from active to inactive tabs,
    /// and clears stale state on windows no longer in the group.
    /// Returns true if any window's tab state or space changed.
    @discardableResult
    static func updateState(_ activeTab: Window, _ siblingTitles: [String]?) -> Bool {
        var changed = false
        guard let titles = siblingTitles else {
            // inactive tabs report nil titles (no AXTabGroup child) but are still tabbed,
            // so we only act when this was the active tab of its group (i.e. !isTabbed).
            // when an active tab becomes standalone (drag-out), we must also reconcile
            // former siblings — they receive no AX event of their own.
            // A fullscreen active tab is excluded: it transiently reports no AXTabGroup mid-transition, and
            // its inactive siblings are off-screen background tabs with no CGS Space of their own — they
            // recover their Space from this active sibling (Window.updateSpaces). Dissolving the group here
            // would strand them with empty spaceIds → flagged phantom → gone from the switcher.
            if !activeTab.isTabbed, !activeTab.isFullscreen, let oldSiblings = activeTab.tabbedSiblingWids {
                let activeWid = activeTab.cgWindowId
                let remainingWids = oldSiblings.filter { $0 != activeWid }
                let remainingSiblings = Windows.list.filter { w in
                    w !== activeTab && w.cgWindowId != nil && remainingWids.contains(w.cgWindowId!)
                }
                if remainingSiblings.count <= 1 {
                    for s in remainingSiblings where s.isTabbed || s.tabbedSiblingWids != nil {
                        s.tabbedSiblingWids = nil
                        s.isTabbed = false
                        s.recomputeIsPhantom()
                        changed = true
                    }
                } else {
                    for s in remainingSiblings where s.tabbedSiblingWids != remainingWids {
                        s.tabbedSiblingWids = remainingWids
                        s.recomputeIsPhantom()
                        changed = true
                    }
                }
                activeTab.tabbedSiblingWids = nil
                changed = true
            }
            return changed
        }
        let pid = activeTab.application.pid
        var siblingWids = [CGWindowID]()
        if let wid = activeTab.cgWindowId { siblingWids.append(wid) }
        var matchedSiblings = [Window]()
        // remove one occurrence of the active tab's title (not all — there may be duplicate titles)
        var remainingTitles = titles
        if let i = remainingTitles.firstIndex(of: activeTab.title) {
            remainingTitles.remove(at: i)
        }
        for title in remainingTitles {
            if let sibling = (Windows.list.first { s in
                s !== activeTab && s.application.pid == pid && s.title == title
                    && !matchedSiblings.contains(where: { $0 === s })
                    && positionsCompatibleForTabSiblings(activeTab, s)
            }) {
                matchedSiblings.append(sibling)
                if let wid = sibling.cgWindowId { siblingWids.append(wid) }
            }
        }
        // Some AXTabGroup titles had no tracked window: these are INACTIVE tabs, whose window is in no CGS list
        // so normal discovery never finds them — that's why a tabbed window shows only its focused tab until you
        // click another. The inactive tab's accessibility element is still reachable, so discover it from there.
        var untrackedTitles = remainingTitles
        for s in matchedSiblings where !untrackedTitles.isEmpty {
            if let i = untrackedTitles.firstIndex(of: s.title) { untrackedTitles.remove(at: i) }
        }
        if !untrackedTitles.isEmpty {
            Applications.discoverInactiveTabs(activeTab.application, untrackedTitles)
        }
        if activeTab.tabbedSiblingWids != siblingWids { changed = true }
        activeTab.tabbedSiblingWids = siblingWids
        activeTab.isTabbed = false
        activeTab.recomputeIsPhantom()
        for sibling in matchedSiblings {
            if !sibling.isTabbed || sibling.tabbedSiblingWids != siblingWids || sibling.spaceIds != activeTab.spaceIds { changed = true }
            sibling.tabbedSiblingWids = siblingWids
            sibling.isTabbed = true
            sibling.spaceIds = activeTab.spaceIds
            sibling.spaceIndexes = activeTab.spaceIndexes
            sibling.isOnAllSpaces = activeTab.isOnAllSpaces
            sibling.recomputeIsPhantom()
        }
        for window in Windows.list where window !== activeTab && window.application.pid == pid
                && !matchedSiblings.contains(where: { $0 === window }) {
            if window.tabbedSiblingWids != nil {
                window.tabbedSiblingWids = nil
                window.isTabbed = false
                window.recomputeIsPhantom()
                changed = true
            }
        }
        return changed
    }

    /// Tabs of one window share the parent's geometry. If both positions are known and differ
    /// noticeably, the candidate is no longer in the same window (likely dragged out).
    /// When either position is unknown (e.g. an inactive tab not yet focused), fall back to title match.
    private static func positionsCompatibleForTabSiblings(_ a: Window, _ b: Window) -> Bool {
        // Respect an existing tab link: if b is already grouped with a (e.g. linked by inferTabGroupsByGeometry —
        // after Merge All Windows the tabs keep their distinct pre-merge positions, which proximity would
        // wrongly read as "dragged out"), don't let a stale position split it back out. A real drag-out is
        // handled separately: the dragged tab leaves the active window's AXTabGroup, so its title is no longer
        // in `titles` and the unmatched-sibling pass un-tabs it — proximity isn't what catches that.
        if let wa = a.cgWindowId, b.tabbedSiblingWids?.contains(wa) == true { return true }
        // A fullscreen window's tabs can't share its frame, and an inactive tab's position goes stale when its
        // parent fullscreens, so the proximity test would wrongly split the group (dropping the inactive tab,
        // which then has empty spaceIds and gets flagged phantom). Fall back to the title match there.
        guard let pa = a.position, let pb = b.position, !a.isFullscreen, !b.isFullscreen else { return true }
        return abs(pa.x - pb.x) < 50 && abs(pa.y - pb.y) < 50
    }
}
