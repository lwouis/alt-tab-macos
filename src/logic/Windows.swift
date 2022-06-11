import Cocoa

class Windows {
    static var list = [Window]()
    static var focusedWindowIndex = Int(0)
    // the first few thumbnails are the most commonly looked at; we pay special attention to them
    static let criticalFirstThumbnails = 3

    // reordered list based on preferences, keeping the original index
    static func reorderList() {
        list.sort {
            if let bool = sortByBooleanAttribute($0.isWindowlessApp, $1.isWindowlessApp) {
                return bool
            }
            if Preferences.showHiddenWindows[App.app.shortcutIndex] == .showAtTheEnd,
               let bool = sortByBooleanAttribute($0.isHidden, $1.isHidden) {
                return bool
            }
            if Preferences.showMinimizedWindows[App.app.shortcutIndex] == .showAtTheEnd,
               let bool = sortByBooleanAttribute($0.isMinimized, $1.isMinimized) {
                return bool
            }
            return $0.lastFocusOrder < $1.lastFocusOrder
        }
    }

    static func setInitialFocusedWindowIndex() {
        if let app = Applications.find(NSWorkspace.shared.frontmostApplication?.processIdentifier),
           app.focusedWindow == nil,
           let lastFocusedWindowIndex = getLastFocusedWindowIndex() {
            updateFocusedWindowIndex(lastFocusedWindowIndex)
        } else {
            updateFocusedWindowIndex(0)
            cycleFocusedWindowIndex(1)
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

    static func updateFocusedWindowIndex(_ newIndex: Int) {
        ThumbnailsView.recycledViews[focusedWindowIndex].highlight(false)
        focusedWindowIndex = newIndex
        let focusedView = ThumbnailsView.recycledViews[focusedWindowIndex]
        focusedView.highlight(true)
        App.app.thumbnailsPanel.thumbnailsView.scrollView.contentView.scrollToVisible(focusedView.frame)
        voiceOverFocusedWindow()
    }

    static func voiceOverFocusedWindow() {
        guard App.app.appIsBeingUsed && App.app.thumbnailsPanel.isKeyWindow else { return }
        // it seems that sometimes makeFirstResponder is called before the view is visible
        // and it creates a delay in showing the main window; calling it with some delay seems to work around this
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
            let window = ThumbnailsView.recycledViews[focusedWindowIndex]
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
            KeyRepeatTimer.timer?.invalidate()
            return
        }
        updateFocusedWindowIndex(nextIndex)
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

    static func detectTabbedWindows() {
        let cgsWindowIds = Spaces.windowsInSpaces(Spaces.idsAndIndexes.map { $0.0 }, [])
        list.forEach {
            if let cgWindowId = $0.cgWindowId {
                $0.isTabbed = !$0.isMinimized && !$0.isHidden && !cgsWindowIds.contains(cgWindowId)
            }
        }
    }

    static func sortByLevel() {
        var windowLevelMap = [CGWindowID: Int]()
        for (index, cgWindowId) in Spaces.windowsInSpaces([Spaces.currentSpaceId], [.minimizedAndTabbed]).enumerated() {
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
                        DispatchQueue.main.async {
                            let view = ThumbnailsView.recycledViews[currentIndex]
                            if view.thumbnail.image != window.thumbnail {
                                let oldSize = view.thumbnail.frame.size
                                view.thumbnail.image = window.thumbnail
                                view.thumbnail.image?.size = oldSize
                                view.thumbnail.frame.size = oldSize
                            }
                        }
                    }
                    refreshThumbnailsAsync(screen, currentIndex + 1)
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

func sortByBooleanAttribute(_ b1: Bool, _ b2: Bool) -> Bool? {
    if b1 && !b2 {
        return false
    }
    if !b1 && b2 {
        return true
    }
    return nil
}

