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
            // only clear state if this window was the active tab of its group;
            // inactive tabs report nil titles (no AXTabGroup child) but are still tabbed
            if activeTab.tabbedSiblingWids != nil && !activeTab.isTabbed {
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
            }) {
                matchedSiblings.append(sibling)
                if let wid = sibling.cgWindowId { siblingWids.append(wid) }
            }
        }
        if activeTab.tabbedSiblingWids != siblingWids { changed = true }
        activeTab.tabbedSiblingWids = siblingWids
        activeTab.isTabbed = false
        for sibling in matchedSiblings {
            if !sibling.isTabbed || sibling.tabbedSiblingWids != siblingWids || sibling.spaceIds != activeTab.spaceIds { changed = true }
            sibling.tabbedSiblingWids = siblingWids
            sibling.isTabbed = true
            sibling.spaceIds = activeTab.spaceIds
            sibling.spaceIndexes = activeTab.spaceIndexes
            sibling.isOnAllSpaces = activeTab.isOnAllSpaces
        }
        for window in Windows.list where window !== activeTab && window.application.pid == pid
                && !matchedSiblings.contains(where: { $0 === window }) {
            if window.tabbedSiblingWids != nil {
                window.tabbedSiblingWids = nil
                window.isTabbed = false
                changed = true
            }
        }
        return changed
    }
}
