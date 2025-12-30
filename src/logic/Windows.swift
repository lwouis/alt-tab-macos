import Cocoa

class Windows {
    static var list = [Window]()
    static var focusedWindowIndex = Int(0)
    static var hoveredWindowIndex: Int?
    private static var lastWindowActivityType = WindowActivityType.none

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
        list.sort {
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

    static func updateIsFullscreenOnCurrentSpace() {
        let windowsOnCurrentSpace = Windows.list.filter { !$0.isWindowlessApp }
        for window in windowsOnCurrentSpace {
            AXUIElement.retryAxCallUntilTimeout(context: window.debugId(), after: .now() + humanPerceptionDelay, callType: .updateWindow) { [weak window] in
                guard let window else { return }
                try AccessibilityEvents.updateWindowSizeAndPositionAndFullscreen(window.axUiElement!, window.cgWindowId!, window)
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

    static func setInitialFocusedAndHoveredWindowIndex() {
        let oldIndex = focusedWindowIndex
        focusedWindowIndex = 0
        ThumbnailsView.highlight(oldIndex)
        if let oldIndex = hoveredWindowIndex {
            hoveredWindowIndex = nil
            ThumbnailsView.highlight(oldIndex)
        }
        if let app = Applications.find(NSWorkspace.shared.frontmostApplication?.processIdentifier),
           (app.focusedWindow == nil || Preferences.windowOrder[App.app.shortcutIndex] != .recentlyFocused),
           let lastFocusedWindowIndex = getLastFocusedWindowIndex() {
            updateFocusedAndHoveredWindowIndex(lastFocusedWindowIndex)
        } else {
            cycleFocusedWindowIndex(1)
            if focusedWindowIndex == 0 {
                updateFocusedAndHoveredWindowIndex(0)
            }
        }
    }

    static func getLastFocusedWindowIndex() -> Int? {
        var index: Int? = nil
        var lastFocusOrderMin = Int.max
        Windows.list.enumerated().forEach {
            if !$0.element.isWindowlessApp && $0.element.lastFocusOrder < lastFocusOrderMin {
                lastFocusOrderMin = $0.element.lastFocusOrder
                index = $0.offset
            }
        }
        return index
    }

    static func appendAndUpdateFocus(_ window: Window) {
        list.forEach {
            $0.lastFocusOrder += 1
        }
        list.append(window)
        if list.count > ThumbnailsView.recycledViews.count {
            ThumbnailsView.recycledViews.append(ThumbnailView())
        }
    }

    static func removeWindow(_ index: Int, _ pid: pid_t) {
        let window = Windows.list[index]
        removeAndUpdateFocus(window)
        if window.application.addWindowlessWindowIfNeeded() != nil {
            Applications.find(pid)?.focusedWindow = nil
        }
        if Windows.list.count > 0 {
            moveFocusedWindowIndexAfterWindowDestroyedInBackground(index)
            App.app.refreshOpenUi([], .refreshUiAfterExternalEvent, windowRemoved: true)
        } else {
            App.app.hideUi()
        }
    }

    private static func removeAndUpdateFocus(_ window: Window) {
        let removedWindowOldFocusOrder = window.lastFocusOrder
        list.removeAll {
            if $0.lastFocusOrder == removedWindowOldFocusOrder {
                return true
            }
            if $0.lastFocusOrder > removedWindowOldFocusOrder {
                $0.lastFocusOrder -= 1
            }
            return false
        }
    }

    static func updateLastFocus(_ otherWindowAxUiElement: AXUIElement, _ otherWindowWid: CGWindowID) -> [Window]? {
        if let focusedWindow = (list.first { $0.isEqualRobust(otherWindowAxUiElement, otherWindowWid) }) {
            let focusedWindowOldFocusOrder = focusedWindow.lastFocusOrder
            var windowsToRefresh = [focusedWindow]
            list.forEach {
                if $0.lastFocusOrder == focusedWindowOldFocusOrder {
                    $0.lastFocusOrder = 0
                } else if $0.lastFocusOrder < focusedWindowOldFocusOrder {
                    $0.lastFocusOrder += 1
                }
                if $0.lastFocusOrder == 0 {
                    windowsToRefresh.append($0)
                }
            }
            return windowsToRefresh
        }
        return nil
    }

    static func updateFocusedAndHoveredWindowIndex(_ newIndex: Int, _ fromMouse: Bool = false) {
        var index: Int?
        if fromMouse && (newIndex != hoveredWindowIndex || lastWindowActivityType == .focus) {
            let oldIndex = hoveredWindowIndex
            hoveredWindowIndex = newIndex
            if let oldIndex {
                ThumbnailsView.highlight(oldIndex)
            }
            index = hoveredWindowIndex
            lastWindowActivityType = .hover
        }
        if (!fromMouse || Preferences.mouseHoverEnabled)
               && (newIndex != focusedWindowIndex || lastWindowActivityType == .hover) {
            let oldIndex = focusedWindowIndex
            focusedWindowIndex = newIndex
            ThumbnailsView.highlight(oldIndex)
            previewFocusedWindowIfNeeded()
            index = focusedWindowIndex
            lastWindowActivityType = .focus
        }
        guard let index else { return }
        ThumbnailsView.highlight(index)
        let focusedView = ThumbnailsView.recycledViews[index]
        App.app.thumbnailsPanel.thumbnailsView.scrollView.contentView.scrollToVisible(focusedView.frame)
        voiceOverWindow(index)
    }

    static func previewFocusedWindowIfNeeded() {
        if App.app.appIsBeingUsed && ScreenRecordingPermission.status == .granted
               && Preferences.previewFocusedWindow && !Preferences.onlyShowApplications()
               && App.app.thumbnailsPanel.isKeyWindow,
           let window = focusedWindow(),
           let id = window.cgWindowId,
           let thumbnail = window.thumbnail,
           let position = window.position,
           let size = window.size {
            App.app.previewPanel.show(id, thumbnail, position, size)
        } else {
            App.app.previewPanel.orderOut(nil)
        }
    }

    static func voiceOverWindow(_ windowIndex: Int = focusedWindowIndex) {
        guard App.app.appIsBeingUsed && App.app.thumbnailsPanel.isKeyWindow else { return }
        // it seems that sometimes makeFirstResponder is called before the view is visible
        // and it creates a delay in showing the main window; calling it with some delay seems to work around this
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
            let window = ThumbnailsView.recycledViews[windowIndex]
            if window.window_ != nil && window.window != nil {
                App.app.thumbnailsPanel.makeFirstResponder(window)
            }
        }
    }

    static func focusedWindow() -> Window? {
        return list.count > focusedWindowIndex ? list[focusedWindowIndex] : nil
    }

    static func cycleFocusedWindowIndex(_ step: Int, allowWrap: Bool = true) {
        let nextIndex = windowIndexAfterCycling(step)
        // don't wrap-around at the end, if key-repeat
        if (((step > 0 && nextIndex < focusedWindowIndex) || (step < 0 && nextIndex > focusedWindowIndex)) &&
            (!allowWrap || ATShortcut.lastEventIsARepeat || !KeyRepeatTimer.timerIsSuspended))
               // don't cycle to another row, if !allowWrap
               || (!allowWrap && list[nextIndex].rowIndex != list[focusedWindowIndex].rowIndex) {
            return
        }
        updateFocusedAndHoveredWindowIndex(nextIndex)
    }

    static func windowIndexAfterCycling(_ step: Int) -> Int {
        if list.count == 0 { return 0 }
        var iterations = 0
        var targetIndex = focusedWindowIndex
        repeat {
            let next = (targetIndex + step) % list.count
            targetIndex = next < 0 ? list.count + next : next
            iterations += 1
        } while !list[targetIndex].shouldShowTheUser && iterations <= list.count
        return targetIndex
    }

    private static func moveFocusedWindowIndexAfterWindowDestroyedInBackground(_ index: Int) {
        if index < focusedWindowIndex {
            cycleFocusedWindowIndex(-1)
        }
    }

    static func updateFocusedWindowIndex() {
        if let focusedWindow = focusedWindow() {
            if !focusedWindow.shouldShowTheUser {
                cycleFocusedWindowIndex(windowIndexAfterCycling(1) > focusedWindowIndex ? 1 : -1)
            } else {
                previewFocusedWindowIfNeeded()
            }
        } else {
            cycleFocusedWindowIndex(-1)
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
            updatesWindowSpace(window)
            refreshIfWindowShouldBeShownToTheUser(window)
        }
        refreshWhichWindowsToShowTheUser()
        sort()
        if (!list.contains { $0.shouldShowTheUser }) { return false }
        return true
    }

    static func updatesWindowSpace(_ window: Window) {
        // macOS bug: if you tab a window, then move the tab group to another space, other tabs from the tab group will stay on the current space
        // you can use the Dock to focus one of the other tabs and it will teleport that tab in the current space, proving that it's a macOS bug
        // note: for some reason, it behaves differently if you minimize the tab group after moving it to another space
        if let cgWindowId = window.cgWindowId {
            let spaceIds = cgWindowId.spaces()
            window.spaceIds = spaceIds
            window.spaceIndexes = spaceIds.compactMap { spaceId in Spaces.idsAndIndexes.first { $0.0 == spaceId }?.1 }
            window.isOnAllSpaces = spaceIds.count > 1
        }
    }

    // dispatch screenshot requests off the main-thread, then wait for completion
    static func refreshThumbnailsAsync(_ windows: [Window], _ source: RefreshCausedBy, windowRemoved: Bool = false) {
        guard (!windows.isEmpty || windowRemoved) && ScreenRecordingPermission.status == .granted
               && !Preferences.onlyShowApplications()
               && (!Appearance.hideThumbnails || Preferences.previewFocusedWindow) else { return }
        var eligibleWindows = [Window]()
        for window in windows {
            if !window.isWindowlessApp, let cgWindowId = window.cgWindowId, cgWindowId != CGWindowID(bitPattern: -1) {
                eligibleWindows.append(window)
            }
        }
        guard (!eligibleWindows.isEmpty || windowRemoved) else { return }
        screenshotEligibleWindowsAndUpdateUi(eligibleWindows, source)
    }

    private static func screenshotEligibleWindowsAndUpdateUi(_ eligibleWindows: [Window], _ source: RefreshCausedBy) {
        for window in eligibleWindows {
            BackgroundWork.screenshotsQueue.addOperation { [weak window] in
                if source == .refreshOnlyThumbnailsAfterShowUi && !App.app.appIsBeingUsed { return }
                if let wid = window?.cgWindowId, let cgImage = wid.screenshot() {
                    if source == .refreshOnlyThumbnailsAfterShowUi && !App.app.appIsBeingUsed { return }
                    DispatchQueue.main.async { [weak window] in
                        if source == .refreshOnlyThumbnailsAfterShowUi && !App.app.appIsBeingUsed { return }
                        window?.refreshThumbnail(cgImage)
                    }
                }
            }
        }
    }

    static func refreshWhichWindowsToShowTheUser() {
        if Preferences.onlyShowApplications() {
            // Group windows by application and select the optimal main window
            let windowsGroupedByApp = Dictionary(grouping: list) { $0.application.pid }
            windowsGroupedByApp.forEach { (app, windows) in
                if windows.count > 1, let mainWindow = selectMainWindow(windows) {
                    windows.forEach { window in
                        if window.cgWindowId != mainWindow.cgWindowId {
                            window.shouldShowTheUser = false
                        }
                    }
                }
            }
        }
    }

    private static func refreshIfWindowShouldBeShownToTheUser(_ window: Window) {
        window.shouldShowTheUser =
            !(window.application.bundleIdentifier.flatMap { id in
                Preferences.blacklist.contains {
                    id.hasPrefix($0.bundleIdentifier) &&
                        ($0.hide == .always || (window.isWindowlessApp && $0.hide != .none))
                }
            } ?? false) &&
            !(Preferences.appsToShow[App.app.shortcutIndex] == .active && window.application.pid != NSWorkspace.shared.frontmostApplication?.processIdentifier) &&
            !(Preferences.appsToShow[App.app.shortcutIndex] == .nonActive && window.application.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier) &&
            !(!(Preferences.showHiddenWindows[App.app.shortcutIndex] != .hide) && window.isHidden) &&
            ((Preferences.showWindowlessApps[App.app.shortcutIndex] != .hide && window.isWindowlessApp) ||
                !window.isWindowlessApp &&
                !(!(Preferences.showFullscreenWindows[App.app.shortcutIndex] != .hide) && window.isFullscreen) &&
                !(!(Preferences.showMinimizedWindows[App.app.shortcutIndex] != .hide) && window.isMinimized) &&
                !(Preferences.spacesToShow[App.app.shortcutIndex] == .visible && !Spaces.visibleSpaces.contains { visibleSpace in window.spaceIds.contains { $0 == visibleSpace } }) &&
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
    static func selectMainWindow(_ windows: [Window]) -> Window? {
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
}

enum WindowActivityType: Int {
    case none = 0
    case hover = 1
    case focus = 2
}
