import Cocoa

class Windows {
    static var list = [Window]()
    private(set) static var byWindowId = [CGWindowID: Window]()
    // we use this to track if the focused window changed while alt-tab was open
    private static var lastFocusedWindowTarget: String?
    private static var lastWindowActivityType = WindowActivityType.none
    private static var shouldSelectBestMatchOnSearchChange = false
    private static var shouldRestoreDefaultSelectionOnSearchClear = false

    static func shouldDisplay(_ window: Window) -> Bool {
        window.shouldShowTheUser && Search.matches(window, query: (SwitcherSession.current?.searchQuery ?? ""))
    }

    static func updateSearchQuery(_ query: String) {
        let previousTrimmedQuery = Search.normalizedQuery(SwitcherSession.current?.searchQuery ?? "")
        let newTrimmedQuery = Search.normalizedQuery(query)
        SwitcherSession.current?.searchQuery = query
        guard let session = SwitcherSession.current else {
            shouldSelectBestMatchOnSearchChange = false
            shouldRestoreDefaultSelectionOnSearchClear = false
            sort()
            return
        }
        if previousTrimmedQuery != newTrimmedQuery {
            if newTrimmedQuery.isEmpty {
                shouldRestoreDefaultSelectionOnSearchClear = !previousTrimmedQuery.isEmpty
                shouldSelectBestMatchOnSearchChange = false
            } else {
                shouldSelectBestMatchOnSearchChange = true
                shouldRestoreDefaultSelectionOnSearchClear = false
                session.hoveredIndex = nil
            }
        }
        sort()
    }

    static func updateIsFullscreenOnCurrentSpace() {
        let windowsOnCurrentSpace = list.filter { !$0.isWindowlessApp }
        for window in windowsOnCurrentSpace {
            guard let wid = window.cgWindowId, let axUiElement = window.axUiElement else { continue }
            AXCallScheduler.shared.schedule(key: "wid-\(wid)-geometry", context: window.debugId, pid: window.application.pid) { [weak window] in
                guard let window else { return }
                // we reuse existing code, to update .isFullscreen, as if there was a kAXWindowResizedNotification
                try AccessibilityEvents.handleEventWindow(kAXWindowResizedNotification, wid, window.application.pid, axUiElement)
            }
        }
    }

    private static func compareByAppNameThenWindowTitle(_ w1: Window, _ w2: Window) -> ComparisonResult {
        let order = w1.application.localizedName.localizedStandardCompare(w2.application.localizedName)
        if order == .orderedSame {
            return w1.title.localizedStandardCompare(w2.title)
        }
        return order
    }

    static func voiceOverWindow(_ windowIndex: Int = (SwitcherSession.current?.selectedIndex ?? 0)) {
        guard SwitcherSession.isActive && TilesPanel.shared.isKeyWindow else { return }
        if TilesView.isSearchEditing { return }
        // it seems that sometimes makeFirstResponder is called before the view is visible
        // and it creates a delay in showing the main window; calling it with some delay seems to work around this
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
            if TilesView.isSearchEditing { return }
            let window = TilesView.recycledViews[windowIndex]
            if window.window_ != nil && window.window != nil {
                TilesPanel.shared.makeFirstResponder(window)
            }
        }
    }

    static func updatesBeforeShowing() -> Bool {
        if MissionControl.state() == .showAllWindows || MissionControl.state() == .showFrontWindows { return false }
        if list.isEmpty { return true }
        // TODO: find a way to update space info when spaces are changed, instead of on every trigger
        // workaround: when Preferences > Mission Control > "Displays have separate Spaces" is unchecked,
        // switching between displays doesn't trigger .activeSpaceDidChangeNotification; we get the latest manually
        Spaces.refresh()
        let windowToSpacesMap = shouldBatchSpaceUpdates() ? Spaces.buildWindowToSpacesMap() : nil
        // Per-shortcut prefs and `exceptions` don't change for the duration of one show, but each
        // computed-property access rebuilds the underlying array via N×`CachedUserDefaults.macroPref`
        // calls. Snapshot them once and pass into the per-window helper.
        let filters = WindowFilters.snapshot()
        for window in list {
            window.updateSpacesAndScreen(windowToSpacesMap)
            refreshIfWindowShouldBeShownToTheUser(window, filters)
        }
        refreshWhichWindowsToShowTheUser()
        sort()
        return true
    }

    private static func shouldBatchSpaceUpdates() -> Bool {
        let trackedWindowCount = list.reduce(0) { $0 + ($1.cgWindowId == nil ? 0 : 1) }
        return trackedWindowCount > Spaces.idsAndIndexes.count
    }

    static func refreshWhichWindowsToShowTheUser() {
        if Preferences.onlyShowApplications() {
            // Group windows by application and select the optimal main window
            let windowsGroupedByApp = Dictionary(grouping: list) { $0.application.pid }
            windowsGroupedByApp.forEach { (app, windows) in
                if windows.count > 1, let mainWindow = findMainWindow(windows) {
                    windows.forEach { window in
                        if window.cgWindowId != mainWindow.cgWindowId {
                            window.shouldShowTheUser = false
                        }
                    }
                }
            }
        }
    }

    private static func shouldHideWindow(_ window: Window, _ entry: ExceptionEntry) -> Bool {
        switch entry.hide {
        case .none:
            return false
        case .always:
            return true
        case .whenNoOpenWindow:
            return window.isWindowlessApp
        case .windowTitleContains:
            guard let patterns = entry.windowTitleContains, !patterns.isEmpty else {
                return false
            }
            return patterns.contains { !$0.isEmpty && window.title.contains($0) }
        }
    }

    private static func refreshIfWindowShouldBeShownToTheUser(_ window: Window, _ f: WindowFilters) {
        window.shouldShowTheUser =
            !window.isInvisible &&
            !(window.application.bundleIdentifier.flatMap { id in
                f.exceptions.contains {
                    !$0.bundleIdentifier.isEmpty && id.hasPrefix($0.bundleIdentifier) && shouldHideWindow(window, $0)
                }
            } ?? false) &&
            !(f.appsToShow == .active && window.application.pid != Applications.frontmostPid) &&
            !(f.appsToShow == .nonActive && window.application.pid == Applications.frontmostPid) &&
            !(!(f.showHiddenWindows != .hide) && window.isHidden) &&
            ((f.showWindowlessApps != .hide && window.isWindowlessApp) ||
                !window.isWindowlessApp &&
                !(!(f.showFullscreenWindows != .hide) && window.isFullscreen) &&
                !(!(f.showMinimizedWindows != .hide) && window.isMinimized) &&
                !(f.spacesToShow == .visible && !Spaces.visibleSpaces.contains { visibleSpace in window.spaceIds.contains { $0 == visibleSpace } }) &&
                !(f.spacesToShow == .nonVisible && Spaces.visibleSpaces.contains { visibleSpace in window.spaceIds.contains { $0 == visibleSpace } }) &&
                !(f.screensToShow == .showingAltTab && !window.isOnScreen(NSScreen.preferred)) &&
                (f.groupTabs == .separateWindows || !window.isTabbed))
    }

    /// Selects the most appropriate main window from a given list of windows.
    ///
    /// The selection criteria are as follows:
    /// 1. Prefer the focused window if it exists.
    /// 2. Prefer the main window of the application if the focused window is not found.
    ///
    /// - Parameter windows: An array of `Window` objects to select from.
    /// - Returns: The most appropriate `Window` object based on the selection criteria, or `nil` if the array is empty.
    static func findMainWindow(_ windows: [Window]) -> Window? {
        let sortedWindows = windows.sorted { (window1, window2) -> Bool in
            // Prefer the focus window
            if window1.application.focusedWindow?.cgWindowId == window1.cgWindowId {
                return true
            } else if window2.application.focusedWindow?.cgWindowId == window2.cgWindowId {
                return false
            }
            // Prefer the main window
            if window1.isAppMainWindow() && !window2.isAppMainWindow() {
                return true
            } else if !window1.isAppMainWindow() && window2.isAppMainWindow() {
                return false
            }
            return true
        }
        return sortedWindows.first { $0.shouldShowTheUser }
    }

    /// selection + hover methods (all operate on `SwitcherSession.current`)
    //////////////////////////////

    static func selectedWindow() -> Window? {
        guard let session = SwitcherSession.current, list.count > session.selectedIndex else { return nil }
        let window = list[session.selectedIndex]
        return shouldDisplay(window) ? window : nil
    }

    static func setInitialSelectedAndHoveredWindowIndex() {
        guard let session = SwitcherSession.current else { return }
        let oldIndex = session.selectedIndex
        session.selectedIndex = 0
        session.selectedTarget = nil
        TilesView.highlight(oldIndex)
        if let oldHovered = session.hoveredIndex {
            session.hoveredIndex = nil
            TilesView.highlight(oldHovered)
        }
        if Applications.frontmostPid != nil,
           Preferences.windowOrder[session.shortcutIndex] != .recentlyFocused,
           let lastFocusedOrderWindowIndex = getLastFocusedOrderWindowIndex() {
            updateSelectedAndHoveredWindowIndex(lastFocusedOrderWindowIndex)
        } else {
            // edge-case: when the 2 most recently focused windows are both minimized, select the first
            if list.count >= 2 && list[0].isMinimized && list[1].isMinimized {
                updateSelectedAndHoveredWindowIndex(0)
            } else {
                cycleSelectedWindowIndex(1)
                if session.selectedIndex == 0 {
                    updateSelectedAndHoveredWindowIndex(0)
                }
            }
        }
    }

    static func updateSelectedWindow() {
        guard let session = SwitcherSession.current else { return }
        let focusedWindowTarget = currentFocusedWindowTarget()
        defer { lastFocusedWindowTarget = focusedWindowTarget }
        if shouldRestoreDefaultSelectionOnSearchClear {
            shouldRestoreDefaultSelectionOnSearchClear = false
            setInitialSelectedAndHoveredWindowIndex()
            return
        }
        let visibleIndexes = visibleWindowIndexes()
        guard let firstVisibleIndex = visibleIndexes.first else {
            session.selectedTarget = nil
            session.hoveredIndex = nil
            return
        }
        if shouldSelectBestMatchOnSearchChange {
            shouldSelectBestMatchOnSearchChange = false
            updateSelectedAndHoveredWindowIndex(firstVisibleIndex)
            return
        }
        if shouldSelectFromScratch(focusedWindowTarget) {
            setInitialSelectedAndHoveredWindowIndex()
            return
        }
        if restoreSelectionTargetIfVisible() { return }
        adaptSelectionToVisibleIndexes(visibleIndexes, firstVisibleIndex)
    }

    private static func visibleWindowIndexes() -> [Int] {
        list.indices.filter { shouldDisplay(list[$0]) }
    }

    private static func currentFocusedWindowTarget() -> String? {
        getLastFocusedOrderWindowIndex().map { list[$0].id }
    }

    private static func shouldSelectFromScratch(_ focusedWindowTarget: String?) -> Bool {
        SwitcherSession.current?.selectedTarget == nil || focusedWindowChangedWhileShowing(focusedWindowTarget)
    }

    private static func focusedWindowChangedWhileShowing(_ focusedWindowTarget: String?) -> Bool {
        guard let session = SwitcherSession.current, Search.normalizedQuery(session.searchQuery).isEmpty else { return false }
        guard let lastFocusedWindowTarget, let focusedWindowTarget else { return false }
        return focusedWindowTarget != lastFocusedWindowTarget
    }

    private static func restoreSelectionTargetIfVisible() -> Bool {
        guard let session = SwitcherSession.current, let target = session.selectedTarget else { return false }
        guard let index = list.firstIndex(where: { $0.id == target && shouldDisplay($0) }) else { return false }
        if index == session.selectedIndex { return true }
        updateSelectedAndHoveredWindowIndex(index)
        return true
    }

    private static func adaptSelectionToVisibleIndexes(_ visibleIndexes: [Int], _ firstVisibleIndex: Int) {
        guard let session = SwitcherSession.current, let lastVisibleIndex = visibleIndexes.last else { return }
        if !visibleIndexes.contains(session.selectedIndex) {
            let closest = visibleIndexes.last(where: { $0 < session.selectedIndex }) ?? lastVisibleIndex
            updateSelectedAndHoveredWindowIndex(closest)
            return
        }
        if session.selectedIndex > lastVisibleIndex {
            updateSelectedAndHoveredWindowIndex(lastVisibleIndex)
            return
        }
        if session.selectedIndex < firstVisibleIndex {
            updateSelectedAndHoveredWindowIndex(firstVisibleIndex)
            return
        }
        if session.selectedTarget == nil {
            session.selectedTarget = list[session.selectedIndex].id
        }
    }

    static func updateSelectedAndHoveredWindowIndex(_ newIndex: Int, _ fromMouse: Bool = false) {
        guard let session = SwitcherSession.current else { return }
        guard newIndex >= 0 && newIndex < list.count else { return }
        guard shouldDisplay(list[newIndex]) else { return }
        var index: Int?
        if fromMouse && (newIndex != session.hoveredIndex || lastWindowActivityType == .focus) {
            let oldIndex = session.hoveredIndex
            session.hoveredIndex = newIndex
            if let oldIndex {
                TilesView.highlight(oldIndex)
            }
            index = session.hoveredIndex
            lastWindowActivityType = .hover
        }
        if !fromMouse {
            TilesView.thumbnailOverView.resetHoveredWindow()
        }
        if (!fromMouse || Preferences.mouseHoverEnabled)
               && (newIndex != session.selectedIndex || lastWindowActivityType == .hover) {
            let oldIndex = session.selectedIndex
            session.selectedIndex = newIndex
            session.selectedTarget = list[newIndex].id
            TilesView.highlight(oldIndex)
            WindowThumbnails.previewSelectedIfNeeded()
            index = session.selectedIndex
            lastWindowActivityType = .focus
        }
        guard let index else { return }
        TilesView.highlight(index)
        let focusedView = TilesView.recycledViews[index]
        TilesView.scrollView.contentView.scrollToVisible(focusedView.frame)
        voiceOverWindow(index)
    }

    static func cycleSelectedWindowIndex(_ step: Int, allowWrap: Bool = true) {
        guard let session = SwitcherSession.current else { return }
        guard list.contains(where: { shouldDisplay($0) }) else { return }
        let nextIndex = selectedWindowIndexAfterCycling(step)
        // don't wrap-around at the end, if key-repeat
        if (((step > 0 && nextIndex < session.selectedIndex) || (step < 0 && nextIndex > session.selectedIndex)) &&
            (!allowWrap || ATShortcut.lastEventIsARepeat || !KeyRepeatTimer.timerIsSuspended))
               // don't cycle to another row, if !allowWrap
               || (!allowWrap && list[nextIndex].rowIndex != list[session.selectedIndex].rowIndex) {
            return
        }
        updateSelectedAndHoveredWindowIndex(nextIndex)
    }

    static func selectedWindowIndexAfterCycling(_ step: Int) -> Int {
        let currentIndex = SwitcherSession.current?.selectedIndex ?? 0
        if list.count == 0 || !list.contains(where: { shouldDisplay($0) }) { return currentIndex }
        var iterations = 0
        var targetIndex = currentIndex
        repeat {
            let next = (targetIndex + step) % list.count
            targetIndex = next < 0 ? list.count + next : next
            iterations += 1
        } while !shouldDisplay(list[targetIndex]) && iterations <= list.count
        return targetIndex
    }

    /// lastFocusOrder methods
    //////////////////////////////

    /// Updates windows "lastFocusOrder" to ensure unique values based on window z-order.
    /// Windows are ordered by their position in Spaces.windowsInSpaces() results,
    /// with topmost windows first.
    static func sortByLevel() {
        var windowLevelMap = [CGWindowID?: Int]()
        for (index, cgWindowId) in Spaces.windowsInSpaces(Spaces.visibleSpaces).enumerated() {
            windowLevelMap[cgWindowId] = index
        }
        list = list
        .sorted { w1, w2 in
            (windowLevelMap[w1.cgWindowId] ?? .max) < (windowLevelMap[w2.cgWindowId] ?? .max)
        }
        .enumerated()
        .map { (index, window) -> Window in
            window.lastFocusOrder = index
            return window
        }
    }

    /// reordered list based on preferences, keeping the original index
    private static func sort() {
        let trimmedQuery = Search.normalizedQuery((SwitcherSession.current?.searchQuery ?? ""))
        let shortcutIndex = (SwitcherSession.current?.shortcutIndex ?? 0)
        let showWindowlessApps = Preferences.showWindowlessApps(shortcutIndex)
        let showHiddenWindows = Preferences.showHiddenWindows(shortcutIndex)
        let showMinimizedWindows = Preferences.showMinimizedWindows(shortcutIndex)
        let sortType = Preferences.windowOrder(shortcutIndex)
        list.sort {
            if !trimmedQuery.isEmpty {
                let matches0 = Search.matches($0, query: trimmedQuery)
                let matches1 = Search.matches($1, query: trimmedQuery)
                if matches0 != matches1 { return matches0 }
                let score0 = Search.relevance(for: $0, query: trimmedQuery)
                let score1 = Search.relevance(for: $1, query: trimmedQuery)
                if score0 != score1 { return score0 > score1 }
                return $0.lastFocusOrder < $1.lastFocusOrder
            }
            // separate buckets for these types of windows
            if showWindowlessApps == .showAtTheEnd && $0.isWindowlessApp != $1.isWindowlessApp {
                return $1.isWindowlessApp
            }
            if showHiddenWindows == .showAtTheEnd && $0.isHidden != $1.isHidden {
                return $1.isHidden
            }
            if showMinimizedWindows == .showAtTheEnd && $0.isMinimized != $1.isMinimized {
                return $1.isMinimized
            }
            // sort within each buckets
            if sortType == .recentlyFocused {
                return $0.lastFocusOrder < $1.lastFocusOrder
            }
            if sortType == .recentlyCreated {
                return $1.creationOrder < $0.creationOrder
            }
            var order = ComparisonResult.orderedSame
            if sortType == .alphabetical {
                order = compareByAppNameThenWindowTitle($0, $1)
            }
            if sortType == .space {
                if $0.isOnAllSpaces && $1.isOnAllSpaces {
                    order = .orderedSame
                } else if $0.isOnAllSpaces {
                    order = .orderedAscending
                } else if $1.isOnAllSpaces {
                    order = .orderedDescending
                } else if let spaceIndex0 = $0.spaceIndexes.first, let spaceIndex1 = $1.spaceIndexes.first {
                    order = spaceIndex0.compare(spaceIndex1)
                }
                if order == .orderedSame {
                    order = compareByAppNameThenWindowTitle($0, $1)
                }
            }
            if order == .orderedSame {
                order = $0.lastFocusOrder.compare($1.lastFocusOrder)
            }
            return order == .orderedAscending
        }
    }

    static func getLastFocusedOrderWindowIndex() -> Int? {
        var index: Int? = nil
        var lastFocusOrderMin = Int.max
        for (offset, w) in list.enumerated() {
            if !w.isWindowlessApp && shouldDisplay(w) && w.lastFocusOrder < lastFocusOrderMin {
                lastFocusOrderMin = w.lastFocusOrder
                index = offset
            }
        }
        return index
    }

    static func updateLastFocusOrder(_ focusedWindow: Window) -> [Window]? {
        // no need to update the list is the window is already lastFocusOrder 0
        guard focusedWindow.lastFocusOrder != 0 && list.count > 1, let previousFocus = (list.first { $0.lastFocusOrder == 0 }) else { return [focusedWindow] }
        // 2 windows have recently changed: the one which got focused, and the one who just lost focus
        let windowsToRefresh = [focusedWindow, previousFocus]
        let focusedWindowOldFocusOrder = focusedWindow.lastFocusOrder
        list.forEach {
            if $0.lastFocusOrder == focusedWindowOldFocusOrder {
                $0.lastFocusOrder = 0
            } else if $0.lastFocusOrder < focusedWindowOldFocusOrder {
                $0.lastFocusOrder += 1
            }
        }
        return windowsToRefresh
    }

    static func findOrCreate(_ windowAxUiElement: AXUIElement, _ wid: CGWindowID, _ app: Application, _ level: CGWindowLevel, _ title: String?, _ subrole: String?, _ role: String?, _ size: CGSize?, _ position: CGPoint?, _ isFullscreen: Bool?, _ isMinimized: Bool?) -> (Window?, Bool) {
        if let window = byWindowId[wid] ?? (list.first { $0.isEqualRobust(windowAxUiElement, wid) }) {
            // on any window event, we take the opportunity to refresh all window attributes
            window.updateFromAxAttributes(title, size, position, isFullscreen, isMinimized)
            return (window, false)
        }
        guard WindowDiscriminator.isActualWindow(app, wid, level, title, subrole, role, size) else { return (nil, false) }
        let window = Window(windowAxUiElement, app, wid, title, isFullscreen, isMinimized, position, size)
        appendWindow(window)
        return (window, true)
    }

    static func appendWindow(_ window: Window) {
        window.lastFocusOrder = list.count
        list.append(window)
        if let wid = window.cgWindowId {
            byWindowId[wid] = window
        }
        if list.count > TilesView.recycledViews.count {
            TilesView.recycledViews.append(TileView())
        }
    }

    static func removeWindows(_ windows: [Window], _ addWindowlessWindowIfNeeded: Bool) {
        // Release any pooled TileView pinned to a window we're removing so its thumbnail
        // IOSurface can deallocate now. Otherwise the layer.contents reference keeps the
        // IOSurface alive until the next switcher show — which may be much later, and
        // never if the user has already closed many windows in the background.
        // Match by Window identity (not cgWindowId) so windowless-app tiles aren't hit.
        for view in TilesView.recycledViews {
            if let win = view.window_, windows.contains(where: { $0 === win }) {
                view.thumbnail.releaseImage()
                view.appIcon.releaseImage()
                view.window_ = nil
            }
        }
        // Same for PreviewPanel: if the previewed window is being removed, drop its IOSurface.
        for w in windows {
            if let wid = w.cgWindowId {
                PreviewPanel.clearIfShowing(wid)
            }
        }
        for w in windows {
            if w.application.focusedWindow?.cgWindowId == w.cgWindowId {
                w.application.focusedWindow = nil
            }
            if let wid = w.cgWindowId {
                byWindowId.removeValue(forKey: wid)
            }
        }
        let toRemove = windows.map { $0.lastFocusOrder }
        list.removeAll { w in
            if toRemove.contains(w.lastFocusOrder) {
                return true
            }
            let howManyToShift = toRemove.reduce(0) { $1 < w.lastFocusOrder ? $0 + 1 : $0 }
            w.lastFocusOrder -= howManyToShift
            return false
        }
        // Drop the cached `SCWindow` for any window we're removing. Otherwise the array
        // grows over time as new shareable-content refreshes leave stale entries behind
        // (see leak #5).
        if #available(macOS 14.0, *) {
            let removedWids = Set(windows.compactMap { $0.cgWindowId })
            if !removedWids.isEmpty {
                BackgroundWork.screenshotsQueue.addOperation {
                    WindowCaptureScreenshots.cachedSCWindows.withLock { $0.removeAll { removedWids.contains($0.windowID) } }
                }
            }
        }
        for w in windows {
            if let wid = w.cgWindowId {
                AXCallScheduler.shared.removeEntries(withPrefix: "wid-\(wid)-")
                Applications.windowListUpdateThrottler.removeEntries(withPrefix: "\(wid)-")
                Applications.captureThrottler.removeEntry(withKey: "capture-wid-\(wid)")
            }
            // Detach the per-window AX observer's runloop source. Without this the AX events
            // thread's runloop accumulates one orphaned source per window-ever-opened (leak #1,
            // dominant cause of the 399 GB VM growth in long sessions).
            w.releaseAxObserver()
            // when a tabbed window is removed, update its former siblings' tab group
            if let siblingWids = w.tabbedSiblingWids {
                TabGroup.removedWindowFromGroup(wid: w.cgWindowId, siblingWids: siblingWids)
            }
        }
        if addWindowlessWindowIfNeeded {
            windows.forEach { $0.application.addWindowlessWindowIfNeeded() }
        }
        lastFocusedWindowTarget = getLastFocusedOrderWindowIndex().map { list[$0].id }
        App.refreshOpenUiAfterExternalEvent([], windowRemoved: true)
    }
}

enum WindowActivityType: Int {
    case none = 0
    case hover = 1
    case focus = 2
}

/// Snapshot of per-shortcut preferences used by `refreshIfWindowShouldBeShownToTheUser`. The
/// `Preferences.<arrayPref>` getters each rebuild a `[MacroPreference]` array via N×`macroPref`
/// calls — cheap once, dominant when read inside a per-window loop. Snapshotting once at the
/// start of `updatesBeforeShowing` collapses N_windows × M_prefs accesses into M_prefs.
struct WindowFilters {
    let exceptions: [ExceptionEntry]
    let appsToShow: AppsToShowPreference
    let showHiddenWindows: ShowHowPreference
    let showWindowlessApps: ShowHowPreference
    let showFullscreenWindows: ShowHowPreference
    let showMinimizedWindows: ShowHowPreference
    let spacesToShow: SpacesToShowPreference
    let screensToShow: ScreensToShowPreference
    let groupTabs: GroupTabsPreference

    static func snapshot() -> WindowFilters {
        let i = SwitcherSession.current?.shortcutIndex ?? 0
        return WindowFilters(
            exceptions: Preferences.exceptions,
            appsToShow: Preferences.appsToShow[i],
            showHiddenWindows: Preferences.showHiddenWindows[i],
            showWindowlessApps: Preferences.showWindowlessApps[i],
            showFullscreenWindows: Preferences.showFullscreenWindows[i],
            showMinimizedWindows: Preferences.showMinimizedWindows[i],
            spacesToShow: Preferences.spacesToShow[i],
            screensToShow: Preferences.screensToShow[i],
            groupTabs: Preferences.groupTabs(i))
    }
}
