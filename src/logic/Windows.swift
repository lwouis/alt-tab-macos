import Cocoa

class Windows {
    static var list = [Window]()
    static var selectedWindowIndex = Int(0)
    static var selectedWindowTarget: String?
    static var hoveredWindowIndex: Int?
    // we use this to track if the focused window changed while alt-tab was open
    private static var lastFocusedWindowTarget: String?
    private static var lastWindowActivityType = WindowActivityType.none
    static var searchQuery = ""
    private static var shouldSelectBestMatchOnSearchChange = false
    private static var shouldRestoreDefaultSelectionOnSearchClear = false

    static func shouldDisplay(_ window: Window) -> Bool {
        window.shouldShowTheUser && Search.matches(window, query: searchQuery)
    }

    static func updateSearchQuery(_ query: String) {
        let previousTrimmedQuery = Search.normalizedQuery(searchQuery)
        let newTrimmedQuery = Search.normalizedQuery(query)
        searchQuery = query
        guard App.app.appIsBeingUsed else {
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
                hoveredWindowIndex = nil
                selectedWindowTarget = nil
            }
        }
        sort()
    }

    static func updateIsFullscreenOnCurrentSpace() {
        let windowsOnCurrentSpace = list.filter { !$0.isWindowlessApp }
        for window in windowsOnCurrentSpace {
            AXUIElement.retryAxCallUntilTimeout(context: window.debugId, after: .now() + humanPerceptionDelay, wid: window.cgWindowId, callType: .updateWindowFromAxEvent) { [weak window] in
                guard let window else { return }
                // we reuse existing code, to update .isFullscreen, as if there was a kAXWindowResizedNotification
                try AccessibilityEvents.handleEventWindow(kAXWindowResizedNotification, window.cgWindowId!, window.application.pid, window.axUiElement!)
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

    static func voiceOverWindow(_ windowIndex: Int = selectedWindowIndex) {
        guard App.app.appIsBeingUsed && App.app.tilesPanel.isKeyWindow else { return }
        if App.app.tilesPanel.tilesView.isSearchEditing { return }
        // it seems that sometimes makeFirstResponder is called before the view is visible
        // and it creates a delay in showing the main window; calling it with some delay seems to work around this
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
            if App.app.tilesPanel.tilesView.isSearchEditing { return }
            let window = TilesView.recycledViews[windowIndex]
            if window.window_ != nil && window.window != nil {
                App.app.tilesPanel.makeFirstResponder(window)
            }
        }
    }

    static func previewSelectedWindowIfNeeded() {
        if App.app.appIsBeingUsed && ScreenRecordingPermission.status == .granted
               && Preferences.previewSelectedWindow && !Preferences.onlyShowApplications()
               && App.app.tilesPanel.isKeyWindow,
           let window = selectedWindow(),
           let id = window.cgWindowId,
           let thumbnail = window.thumbnail,
           let position = window.position,
           let size = window.size {
            App.app.previewPanel.show(id, thumbnail, position, size)
        } else {
            App.app.previewPanel.orderOut(nil)
        }
    }

    /// tabs detection is a flaky work-around the lack of public API to observe OS tabs
    /// see: https://github.com/lwouis/alt-tab-macos/issues/1540
    private static func detectTabbedWindows(_ window: Window, _ cgsWindowIds: [CGWindowID], _ visibleCgsWindowIds: [CGWindowID]) {
        if let cgWindowId = window.cgWindowId {
            if window.isMinimized || window.isHidden {
                if #available(macOS 13.0, *) {
                    // not exact after window merging
                    window.isTabbed = !cgsWindowIds.contains(cgWindowId)
                } else {
                    // not known
                    window.isTabbed = false
                }
            } else {
                window.isTabbed = !visibleCgsWindowIds.contains(cgWindowId)
            }
        }
    }

    static func updatesBeforeShowing() -> Bool {
        if list.count == 0 || MissionControl.state() == .showAllWindows || MissionControl.state() == .showFrontWindows { return false }
        // TODO: find a way to update space info when spaces are changed, instead of on every trigger
        // workaround: when Preferences > Mission Control > "Displays have separate Spaces" is unchecked,
        // switching between displays doesn't trigger .activeSpaceDidChangeNotification; we get the latest manually
        Spaces.refresh()
        let spaceIdsAndIndexes = Spaces.idsAndIndexes.map { $0.0 }
        lazy var cgsWindowIds = Spaces.windowsInSpaces(spaceIdsAndIndexes)
        lazy var visibleCgsWindowIds = Spaces.windowsInSpaces(spaceIdsAndIndexes, false)
        for window in list {
            detectTabbedWindows(window, cgsWindowIds, visibleCgsWindowIds)
            window.updateSpacesAndScreen()
            refreshIfWindowShouldBeShownToTheUser(window)
        }
        refreshWhichWindowsToShowTheUser()
        sort()
        if (!list.contains { $0.shouldShowTheUser }) { return false }
        return true
    }

    // dispatch screenshot requests off the main-thread, then wait for completion
    static func refreshThumbnailsAsync(_ windows: [Window], _ source: RefreshCausedBy, windowRemoved: Bool = false) {
        guard (!windows.isEmpty || windowRemoved) && ScreenRecordingPermission.status == .granted
               && !Preferences.onlyShowApplications()
               && (!Appearance.hideThumbnails || Preferences.previewSelectedWindow) else { return }
        var eligibleWindows = [Window]()
        for window in windows {
            if !window.isWindowlessApp, let cgWindowId = window.cgWindowId, cgWindowId != CGWindowID(bitPattern: -1) {
                eligibleWindows.append(window)
            }
        }
        guard (!eligibleWindows.isEmpty || windowRemoved) else { return }
        if #available(macOS 14.0, *),
           // mitigate macOS 15 bugs with ScreenCapture Kit (see https://github.com/lwouis/alt-tab-macos/issues/5190)
           ProcessInfo.processInfo.operatingSystemVersion.majorVersion != 15 {
            WindowCaptureScreenshots.oneTimeScreenshots(eligibleWindows, source)
        } else {
            WindowCaptureScreenshotsPrivateApi.oneTimeScreenshots(eligibleWindows, source)
        }
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
            guard let titleFilter = entry.windowTitleContains, !titleFilter.isEmpty else {
                return false
            }
            return window.title.contains(titleFilter)
        }
    }

    private static func refreshIfWindowShouldBeShownToTheUser(_ window: Window) {
        window.shouldShowTheUser =
            !(window.application.bundleIdentifier.flatMap { id in
                Preferences.exceptions.contains {
                    id.hasPrefix($0.bundleIdentifier) && shouldHideWindow(window, $0)
                }
            } ?? false) &&
            !(Preferences.appsToShow[App.app.shortcutIndex] == .active && window.application.pid != Applications.frontmostPid) &&
            !(Preferences.appsToShow[App.app.shortcutIndex] == .nonActive && window.application.pid == Applications.frontmostPid) &&
            !(!(Preferences.showHiddenWindows[App.app.shortcutIndex] != .hide) && window.isHidden) &&
            ((Preferences.showWindowlessApps[App.app.shortcutIndex] != .hide && window.isWindowlessApp) ||
                !window.isWindowlessApp &&
                !(!(Preferences.showFullscreenWindows[App.app.shortcutIndex] != .hide) && window.isFullscreen) &&
                !(!(Preferences.showMinimizedWindows[App.app.shortcutIndex] != .hide) && window.isMinimized) &&
                !(Preferences.spacesToShow[App.app.shortcutIndex] == .visible && !Spaces.visibleSpaces.contains { visibleSpace in window.spaceIds.contains { $0 == visibleSpace } }) &&
                !(Preferences.spacesToShow[App.app.shortcutIndex] == .nonVisible && Spaces.visibleSpaces.contains { visibleSpace in window.spaceIds.contains { $0 == visibleSpace } }) &&
                !(Preferences.screensToShow[App.app.shortcutIndex] == .showingAltTab && !window.isOnScreen(NSScreen.preferred)) &&
                (Preferences.showTabsAsWindows || !window.isTabbed))
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

    /// selectedWindowIndex methods
    //////////////////////////////

    static func selectedWindow() -> Window? {
        guard list.count > selectedWindowIndex else { return nil }
        let window = list[selectedWindowIndex]
        return shouldDisplay(window) ? window : nil
    }

    static func setInitialSelectedAndHoveredWindowIndex() {
        let oldIndex = selectedWindowIndex
        selectedWindowIndex = 0
        selectedWindowTarget = nil
        TilesView.highlight(oldIndex)
        if let oldIndex = hoveredWindowIndex {
            hoveredWindowIndex = nil
            TilesView.highlight(oldIndex)
        }
        if let frontmostPid = Applications.frontmostPid,
           let frontmostApp = Applications.findOrCreate(frontmostPid, false),
           (frontmostApp.focusedWindow == nil || Preferences.windowOrder[App.app.shortcutIndex] != .recentlyFocused),
           let lastFocusedOrderWindowIndex = getLastFocusedOrderWindowIndex() {
            updateSelectedAndHoveredWindowIndex(lastFocusedOrderWindowIndex)
        } else {
            // edge-case: when the 2 most recently focused windows are both minimized, select the first
            if list.count >= 2 && list[0].isMinimized && list[1].isMinimized {
                updateSelectedAndHoveredWindowIndex(0)
            } else {
                cycleSelectedWindowIndex(1)
                if selectedWindowIndex == 0 {
                    updateSelectedAndHoveredWindowIndex(0)
                }
            }
        }
    }

    static func updateSelectedWindow() {
        let focusedWindowTarget = currentFocusedWindowTarget()
        defer { lastFocusedWindowTarget = focusedWindowTarget }
        if shouldRestoreDefaultSelectionOnSearchClear {
            shouldRestoreDefaultSelectionOnSearchClear = false
            setInitialSelectedAndHoveredWindowIndex()
            return
        }
        let visibleIndexes = visibleWindowIndexes()
        guard let firstVisibleIndex = visibleIndexes.first else {
            selectedWindowTarget = nil
            hoveredWindowIndex = nil
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
        selectedWindowTarget == nil || focusedWindowChangedWhileShowing(focusedWindowTarget)
    }

    private static func focusedWindowChangedWhileShowing(_ focusedWindowTarget: String?) -> Bool {
        guard App.app.appIsBeingUsed, Search.normalizedQuery(searchQuery).isEmpty else { return false }
        guard let lastFocusedWindowTarget, let focusedWindowTarget else { return false }
        return focusedWindowTarget != lastFocusedWindowTarget
    }

    private static func restoreSelectionTargetIfVisible() -> Bool {
        guard let selectedWindowTarget else { return false }
        guard let index = list.firstIndex(where: { $0.id == selectedWindowTarget && shouldDisplay($0) }) else { return false }
        updateSelectedAndHoveredWindowIndex(index)
        return true
    }

    private static func adaptSelectionToVisibleIndexes(_ visibleIndexes: [Int], _ firstVisibleIndex: Int) {
        guard let lastVisibleIndex = visibleIndexes.last else { return }
        if !visibleIndexes.contains(selectedWindowIndex) {
            updateSelectedAndHoveredWindowIndex(firstVisibleIndex)
            return
        }
        if selectedWindowIndex > lastVisibleIndex {
            updateSelectedAndHoveredWindowIndex(lastVisibleIndex)
            return
        }
        if selectedWindowIndex < firstVisibleIndex {
            updateSelectedAndHoveredWindowIndex(firstVisibleIndex)
            return
        }
        if selectedWindowTarget == nil {
            selectedWindowTarget = list[selectedWindowIndex].id
        }
    }

    static func updateSelectedAndHoveredWindowIndex(_ newIndex: Int, _ fromMouse: Bool = false) {
        guard newIndex >= 0 && newIndex < list.count else { return }
        guard shouldDisplay(list[newIndex]) else { return }
        var index: Int?
        if fromMouse && (newIndex != hoveredWindowIndex || lastWindowActivityType == .focus) {
            let oldIndex = hoveredWindowIndex
            hoveredWindowIndex = newIndex
            if let oldIndex {
                TilesView.highlight(oldIndex)
            }
            index = hoveredWindowIndex
            lastWindowActivityType = .hover
        }
        if !fromMouse {
            App.app.tilesPanel.tilesView.thumbnailOverView.resetHoveredWindow()
        }
        if (!fromMouse || Preferences.mouseHoverEnabled)
               && (newIndex != selectedWindowIndex || lastWindowActivityType == .hover) {
            let oldIndex = selectedWindowIndex
            selectedWindowIndex = newIndex
            selectedWindowTarget = list[newIndex].id
            TilesView.highlight(oldIndex)
            previewSelectedWindowIfNeeded()
            index = selectedWindowIndex
            lastWindowActivityType = .focus
        }
        guard let index else { return }
        TilesView.highlight(index)
        let focusedView = TilesView.recycledViews[index]
        App.app.tilesPanel.tilesView.scrollView.contentView.scrollToVisible(focusedView.frame)
        voiceOverWindow(index)
    }

    static func cycleSelectedWindowIndex(_ step: Int, allowWrap: Bool = true) {
        guard App.app.appIsBeingUsed else { return }
        guard list.contains(where: { shouldDisplay($0) }) else { return }
        let nextIndex = selectedWindowIndexAfterCycling(step)
        // don't wrap-around at the end, if key-repeat
        if (((step > 0 && nextIndex < selectedWindowIndex) || (step < 0 && nextIndex > selectedWindowIndex)) &&
            (!allowWrap || ATShortcut.lastEventIsARepeat || !KeyRepeatTimer.timerIsSuspended))
               // don't cycle to another row, if !allowWrap
               || (!allowWrap && list[nextIndex].rowIndex != list[selectedWindowIndex].rowIndex) {
            return
        }
        updateSelectedAndHoveredWindowIndex(nextIndex)
    }

    static func selectedWindowIndexAfterCycling(_ step: Int) -> Int {
        if list.count == 0 || !list.contains(where: { shouldDisplay($0) }) { return selectedWindowIndex }
        var iterations = 0
        var targetIndex = selectedWindowIndex
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
        let trimmedQuery = Search.normalizedQuery(searchQuery)
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
            if Preferences.showWindowlessApps[App.app.shortcutIndex] == .showAtTheEnd && $0.isWindowlessApp != $1.isWindowlessApp {
                return $1.isWindowlessApp
            }
            if Preferences.showHiddenWindows[App.app.shortcutIndex] == .showAtTheEnd && $0.isHidden != $1.isHidden {
                return $1.isHidden
            }
            if Preferences.showMinimizedWindows[App.app.shortcutIndex] == .showAtTheEnd && $0.isMinimized != $1.isMinimized {
                return $1.isMinimized
            }
            // sort within each buckets
            let sortType = Preferences.windowOrder[App.app.shortcutIndex]
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
        if let window = (list.first { $0.isEqualRobust(windowAxUiElement, wid) }) {
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
        list.forEach {
            $0.lastFocusOrder += 1
        }
        list.append(window)
        if list.count > TilesView.recycledViews.count {
            TilesView.recycledViews.append(TileView())
        }
    }

    static func removeWindows(_ windows: [Window], _ addWindowlessWindowIfNeeded: Bool) {
        let toRemove = windows.map { $0.lastFocusOrder }
        list.removeAll { w in
            if toRemove.contains(w.lastFocusOrder) {
                return true
            }
            let howManyToShift = toRemove.reduce(0) { $1 < w.lastFocusOrder ? $0 + 1 : $0 }
            w.lastFocusOrder -= howManyToShift
            return false
        }
        if addWindowlessWindowIfNeeded {
            windows.forEach { $0.application.addWindowlessWindowIfNeeded() }
        }
        App.app.refreshOpenUiAfterExternalEvent([], windowRemoved: true)
    }
}

enum WindowActivityType: Int {
    case none = 0
    case hover = 1
    case focus = 2
}
