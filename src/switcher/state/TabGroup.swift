import Cocoa

/// Impure adapter for OS-tab grouping: reads/writes the live `Windows.list` model and the AX/CGS world,
/// delegating every *decision* to the pure `TabGroupResolver` kernel (geometry inference, AX-title
/// sibling matching, group dissolution). This file maps `Window` ⇄ `TabWindow`, applies the kernel's
/// verdicts back onto the model (the `isTabbed` / `tabbedSiblingWids` / Space backfill / phantom
/// recompute mutations the kernel can't do), and drives the side effects (inactive-tab discovery,
/// UI refresh). See `TabGroupResolverSpecs.md` for the decision logic and its scenarios.
class TabGroup {

    /// Snapshot the `Window` facts the kernel needs. `cgWindowId` is assumed non-nil by callers (every
    /// tracked, grouped window has one); they pre-filter `cgWindowId != nil` before mapping.
    private static func tabWindow(_ w: Window) -> TabWindow {
        TabWindow(pid: w.application.pid, wid: w.cgWindowId ?? 0, size: w.size, position: w.position,
            spaceIds: w.spaceIds, title: w.title, isTabbed: w.isTabbed, isFullscreen: w.isFullscreen,
            isMinimized: w.isMinimized, tabbedSiblingWids: w.tabbedSiblingWids)
    }

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
    /// (`inferTabGroupsByGeometry`) and push the visible tab's fullscreen/minimized onto its inactive siblings
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
    /// The grouping decision (which windows form a group, by app + size + Space-less-ness) is the pure
    /// `TabGroupResolver.geometryGroups`; here we DISCOVER nothing (a background tab still enters the list
    /// only once focused), we link windows already tracked, set the visible tab as the group's active one,
    /// and backfill each background tab's Space from it — handing off to the normal machinery (the
    /// `isTabbed` phantom exemption, "show every tab").
    static func inferTabGroupsByGeometry() {
        let candidates = Windows.list.filter { !$0.isWindowlessApp && !$0.isMinimized && $0.cgWindowId != nil && $0.size != nil }
        guard candidates.count > 1 else { return }
        var byWid = [CGWindowID: Window]()
        for w in candidates { if let id = w.cgWindowId { byWid[id] = w } }
        for group in TabGroupResolver.geometryGroups(candidates.map(tabWindow)) {
            guard let visible = byWid[group.visibleWid] else { continue }
            let background = group.backgroundWids.compactMap { byWid[$0] }
            guard !background.isEmpty else { continue }
            visible.isTabbed = false
            visible.tabbedSiblingWids = group.siblingWids
            for tab in background {
                tab.tabbedSiblingWids = group.siblingWids
                tab.isTabbed = true
                tab.spaceIds = visible.spaceIds
                tab.spaceIndexes = visible.spaceIndexes
                tab.isOnAllSpaces = visible.isOnAllSpaces
                tab.recomputeIsPhantom()
            }
            Logger.debug { "inferred tab group for \(visible.application.runningApplication.localizedName ?? "?"): visible \(visible.cgWindowId!) sp:\(visible.spaceIds), background \(background.compactMap { $0.cgWindowId })" }
        }
    }

    /// When a window is removed from the list, update its former siblings' tab group.
    /// If only 1 sibling remains, clear its tab state (a single window can't be tabbed).
    static func removedWindowFromGroup(wid: CGWindowID?, siblingWids: [CGWindowID]) {
        let presentWids = Set(Windows.list.compactMap { $0.cgWindowId })
        let d = TabGroupResolver.dissolution(siblingWids: siblingWids, leaving: wid ?? 0, presentWids: presentWids)
        let survivors = d.applyToWids.compactMap { id in Windows.list.first { $0.cgWindowId == id } }
        if d.dissolve {
            for s in survivors {
                s.tabbedSiblingWids = nil
                s.isTabbed = false
            }
        } else {
            for s in survivors {
                s.tabbedSiblingWids = d.remainingSiblingWids
            }
        }
    }

    /// Update tab state for a window and its siblings using AX-discovered tab titles.
    /// Resolves titles to WIDs (via `TabGroupResolver.matchSiblings`), propagates space info from active to
    /// inactive tabs, and clears stale state on windows no longer in the group.
    /// Returns true if any window's tab state or space changed.
    @discardableResult
    static func updateState(_ activeTab: Window, _ siblingTitles: [String]?) -> Bool {
        var changed = false
        guard let titles = siblingTitles else {
            // inactive tabs report nil titles (no AXTabGroup child) but are still tabbed, so we only act
            // when this was the active tab of its group (i.e. !isTabbed). When an active tab becomes
            // standalone (drag-out), we must also reconcile former siblings — they receive no AX event of
            // their own. A fullscreen active tab is excluded: it transiently reports no AXTabGroup
            // mid-transition, and its inactive siblings are off-screen background tabs with no CGS Space of
            // their own — dissolving the group here would strand them with empty spaceIds → flagged phantom.
            if !activeTab.isTabbed, !activeTab.isFullscreen,
               let oldSiblings = activeTab.tabbedSiblingWids, let activeWid = activeTab.cgWindowId {
                let presentWids = Set(Windows.list.compactMap { $0.cgWindowId })
                let d = TabGroupResolver.dissolution(siblingWids: oldSiblings, leaving: activeWid, presentWids: presentWids)
                let survivors = d.applyToWids.compactMap { id in Windows.list.first { $0 !== activeTab && $0.cgWindowId == id } }
                if d.dissolve {
                    for s in survivors where s.isTabbed || s.tabbedSiblingWids != nil {
                        s.tabbedSiblingWids = nil
                        s.isTabbed = false
                        s.recomputeIsPhantom()
                        changed = true
                    }
                } else {
                    for s in survivors where s.tabbedSiblingWids != d.remainingSiblingWids {
                        s.tabbedSiblingWids = d.remainingSiblingWids
                        s.recomputeIsPhantom()
                        changed = true
                    }
                }
                activeTab.tabbedSiblingWids = nil
                changed = true
            }
            return changed
        }
        guard activeTab.cgWindowId != nil else { return changed }
        let pid = activeTab.application.pid
        let sameApp = Windows.list.filter { $0.application.pid == pid && $0.cgWindowId != nil }
        var byWid = [CGWindowID: Window]()
        for w in sameApp { byWid[w.cgWindowId!] = w }
        let match = TabGroupResolver.matchSiblings(active: tabWindow(activeTab), axTitles: titles, sameAppWindows: sameApp.map(tabWindow))
        // Some AXTabGroup titles had no tracked window: these are INACTIVE tabs, whose window is in no CGS
        // list so normal discovery never finds them — that's why a tabbed window shows only its focused tab
        // until you click another. The inactive tab's accessibility element is still reachable, so discover
        // it from there.
        if !match.untrackedTitles.isEmpty {
            Applications.discoverInactiveTabs(activeTab.application, match.untrackedTitles)
        }
        if activeTab.tabbedSiblingWids != match.siblingWids { changed = true }
        activeTab.tabbedSiblingWids = match.siblingWids
        activeTab.isTabbed = false
        activeTab.recomputeIsPhantom()
        for sibling in match.matchedWids.compactMap({ byWid[$0] }) {
            if !sibling.isTabbed || sibling.tabbedSiblingWids != match.siblingWids || sibling.spaceIds != activeTab.spaceIds { changed = true }
            sibling.tabbedSiblingWids = match.siblingWids
            sibling.isTabbed = true
            sibling.spaceIds = activeTab.spaceIds
            sibling.spaceIndexes = activeTab.spaceIndexes
            sibling.isOnAllSpaces = activeTab.isOnAllSpaces
            sibling.recomputeIsPhantom()
        }
        for window in match.toUntabWids.compactMap({ byWid[$0] }) where window.tabbedSiblingWids != nil {
            window.tabbedSiblingWids = nil
            window.isTabbed = false
            window.recomputeIsPhantom()
            changed = true
        }
        return changed
    }
}
