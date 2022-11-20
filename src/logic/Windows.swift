import Cocoa

class Windows {
    static var list = [Window]()
    static var focusedWindowIndex = Int(0)
    static var hoveredWindowIndex: Int?
    // the first few thumbnails are the most commonly looked at; we pay special attention to them
    static let criticalFirstThumbnails = 3

    /// reordered list based on preferences, keeping the original index
    static func reorderList() {
        list.sort {
            // separate buckets for these types of windows
            if $0.isWindowlessApp != $1.isWindowlessApp {
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
                order = sortByAppNameThenWindowTitle($0, $1)
            }
            if sortType == .space {
                order = $0.spaceIndex.compare($1.spaceIndex)
                if order == .orderedSame {
                    order = sortByAppNameThenWindowTitle($0, $1)
                }
            }
            if order == .orderedSame {
                order = $0.lastFocusOrder.compare($1.lastFocusOrder)
            }
            return order == .orderedAscending
        }
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

    static func removeAndUpdateFocus(_ window: Window) {
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
        if fromMouse && newIndex != hoveredWindowIndex {
            let oldIndex = hoveredWindowIndex
            hoveredWindowIndex = newIndex
            if let oldIndex = oldIndex {
                ThumbnailsView.highlight(oldIndex)
            }
            index = hoveredWindowIndex
        }
        if (!fromMouse || Preferences.mouseHoverEnabled) && newIndex != focusedWindowIndex {
            let oldIndex = focusedWindowIndex
            focusedWindowIndex = newIndex
            ThumbnailsView.highlight(oldIndex)
            previewFocusedWindowIfNeeded()
            index = focusedWindowIndex
        }
        guard let index = index else { return }
        ThumbnailsView.highlight(index)
        let focusedView = ThumbnailsView.recycledViews[index]
        App.app.thumbnailsPanel.thumbnailsView.scrollView.contentView.scrollToVisible(focusedView.frame)
        voiceOverWindow(index)
    }

    static func previewFocusedWindowIfNeeded() {
        guard
            Preferences.previewFocusedWindow,
            App.app.appIsBeingUsed && App.app.thumbnailsPanel.isKeyWindow,
            let window = focusedWindow(),
            let preview = window.getPreview(),
            let position = window.position,
            let size = window.size
        else {
            App.app.previewPanel.orderOut(nil)
            return
        }
        App.app.previewPanel.setPreview(preview)
        var frame = NSRect(origin: position, size: size)
        frame.origin.y = NSScreen.screens[0].frame.maxY - frame.maxY
        App.app.previewPanel.setFrame(frame, display: false)
        App.app.previewPanel.order(.below, relativeTo: App.app.thumbnailsPanel.windowNumber)
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

    static func cycleFocusedWindowIndex(_ step: Int) {
        let nextIndex = windowIndexAfterCycling(step)
        if ((step > 0 && nextIndex < focusedWindowIndex) || (step < 0 && nextIndex > focusedWindowIndex)) &&
               (KeyRepeatTimer.isARepeat || KeyRepeatTimer.timer?.isValid ?? false) {
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

    static func moveFocusedWindowIndexAfterWindowDestroyedInBackground(_ index: Int) {
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

    static func updateSpaces() {
        // workaround: when Preferences > Mission Control > "Displays have separate Spaces" is unchecked,
        // switching between displays doesn't trigger .activeSpaceDidChangeNotification; we get the latest manually
        Spaces.refreshCurrentSpaceId()
        list.forEachAsync { $0.updatesWindowSpace() }
    }

    /// tabs detection is a flaky work-around the lack of public API to observe OS tabs
    /// see: https://github.com/lwouis/alt-tab-macos/issues/1540
    static func detectTabbedWindows() {
        lazy var cgsWindowIds = Spaces.windowsInSpaces(Spaces.idsAndIndexes.map { $0.0 })
        lazy var visibleCgsWindowIds = Spaces.windowsInSpaces(Spaces.idsAndIndexes.map { $0.0 }, false)
        list.forEach {
            if let cgWindowId = $0.cgWindowId {
                if $0.isMinimized || $0.isHidden {
                    if #available(macOS 13, *) {
                        // not exact after window merging
                        $0.isTabbed = !cgsWindowIds.contains(cgWindowId)
                    } else {
                        // not known
                        $0.isTabbed = false
                    }
                } else {
                    $0.isTabbed = !visibleCgsWindowIds.contains(cgWindowId)
                }
            }
        }
    }

    static func sortByLevel() {
        var windowLevelMap = [CGWindowID: Int]()
        for (index, cgWindowId) in Spaces.windowsInSpaces([Spaces.currentSpaceId]).enumerated() {
            windowLevelMap[cgWindowId] = index
        }
        var sortedTuples = Windows.list
                .filter { $0.cgWindowId != nil }
                .map { (windowLevelMap[$0.cgWindowId!], $0) }
        sortedTuples.sort(by: {
            if $0.0 == nil {
                return false
            }
            if $1.0 == nil {
                return true
            }
            return $0.0! < $1.0!
        })
        Windows.list = sortedTuples.map { $0.1 }
    }

    static func refreshFirstFewThumbnailsSync() {
        if Preferences.hideThumbnails { return }
        list.filter { $0.shouldShowTheUser }
                .prefix(criticalFirstThumbnails)
                .forEachAsync { window in window.refreshThumbnail() }
    }

    static func refreshThumbnailsAsync(_ screen: NSScreen, _ currentIndex: Int = criticalFirstThumbnails) {
        DispatchQueue.main.async {
            if !App.app.appIsBeingUsed || Preferences.hideThumbnails { return }
            BackgroundWork.mainQueueConcurrentWorkQueue.async {
                if currentIndex < list.count {
                    let window = list[currentIndex]
                    if window.shouldShowTheUser && !window.isWindowlessApp {
                        window.refreshThumbnail()
                    }
                    refreshThumbnailsAsync(screen, currentIndex + 1)
                } else {
                    DispatchQueue.main.async { App.app.refreshOpenUi() }
                }
            }
        }
    }

    static func refreshWhichWindowsToShowTheUser(_ screen: NSScreen) {
        Windows.list.forEach { (window: Window) in
            refreshIfWindowShouldBeShownToTheUser(window, screen)
        }
    }

    static func refreshIfWindowShouldBeShownToTheUser(_ window: Window, _ screen: NSScreen) {
        window.shouldShowTheUser =
            !(window.application.runningApplication.bundleIdentifier.flatMap { id in
                Preferences.blacklist.contains {
                    id.hasPrefix($0.bundleIdentifier) &&
                        ($0.hide == .always || (window.isWindowlessApp && $0.hide != .none))
                }
            } ?? false) &&
            !(Preferences.appsToShow[App.app.shortcutIndex] == .active && window.application.runningApplication.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier) &&
            !(!(Preferences.showHiddenWindows[App.app.shortcutIndex] != .hide) && window.isHidden) &&
            ((!Preferences.hideWindowlessApps && window.isWindowlessApp) ||
                !window.isWindowlessApp &&
                !(!(Preferences.showFullscreenWindows[App.app.shortcutIndex] != .hide) && window.isFullscreen) &&
                !(!(Preferences.showMinimizedWindows[App.app.shortcutIndex] != .hide) && window.isMinimized) &&
                !(Preferences.spacesToShow[App.app.shortcutIndex] == .visible && !Spaces.visibleSpaces.contains(window.spaceId)) &&
                !(Preferences.screensToShow[App.app.shortcutIndex] == .showingAltTab && !window.isOnScreen(screen)) &&
                (Preferences.showTabsAsWindows || !window.isTabbed))
    }
}

func sortByAppNameThenWindowTitle(_ w1: Window, _ w2: Window) -> ComparisonResult {
    var order = w1.application.runningApplication.localizedName.localizedStandardCompare(w2.application.runningApplication.localizedName)
    if order == .orderedSame {
        return w1.title.localizedStandardCompare(w2.title)
    }
    return order
}
