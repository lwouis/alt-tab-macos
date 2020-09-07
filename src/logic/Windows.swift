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
    }

    static func focusedWindow() -> Window? {
        return list.count > focusedWindowIndex ? list[focusedWindowIndex] : nil
    }

    static func cycleFocusedWindowIndex(_ step: Int) {
        updateFocusedWindowIndex(windowIndexAfterCycling(step))
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

    static func moveFocusedWindowIndexAfterWindowDestroyedInBackground(_ destroyedWindowIndex: Int) {
        if focusedWindowIndex > destroyedWindowIndex {
            cycleFocusedWindowIndex(-1)
        } else if focusedWindowIndex == destroyedWindowIndex && !focusedWindow()!.shouldShowTheUser {
            cycleFocusedWindowIndex(1)
        }
    }

    static func updateSpaces() {
        Spaces.updateIsSingleSpace()
        // workaround: when Preferences > Mission Control > "Displays have separate Spaces" is unchecked,
        // switching between displays doesn't trigger .activeSpaceDidChangeNotification; we get the latest manually
        Spaces.refreshCurrentSpaceId()
        list.forEachAsync { (window: Window) in
            updatesWindowSpace(window)
        }
    }

    static func updatesWindowSpace(_ window: Window) {
        // macOS bug: if you tab a window, then move the tab group to another space, other tabs from the tab group will stay on the current space
        // you can use the Dock to focus one of the other tabs and it will teleport that tab in the current space, proving that it's a macOS bug
        // note: for some reason, it behaves differently if you minimize the tab group after moving it to another space
        let spaceIds = window.cgWindowId.spaces()
        if spaceIds.count == 1 {
            window.spaceId = spaceIds.first!
            window.spaceIndex = Spaces.idsAndIndexes.first { $0.0 == spaceIds.first! }!.1
        } else if spaceIds.count > 1 {
            window.spaceId = Spaces.currentSpaceId
            window.spaceIndex = Spaces.currentSpaceIndex
            window.isOnAllSpaces = true
        }
    }

    static func sortByLevel() {
        var windowLevelMap = [CGWindowID: Int]()
        for (index, cgWindowId) in Spaces.windowsInSpaces([Spaces.currentSpaceId]).enumerated() {
            windowLevelMap[cgWindowId] = index
        }
        var sortedTuples = Windows.list.map { (windowLevelMap[$0.cgWindowId], $0) }
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
        guard App.app.appIsBeingUsed else { return }
        if Preferences.hideThumbnails { return }
        BackgroundWork.mainQueueConcurrentWorkQueue.async {
            if currentIndex < list.count {
                let window = list[currentIndex]
                if window.shouldShowTheUser {
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

    static func refreshWhichWindowsToShowTheUser(_ screen: NSScreen) {
        Windows.list.forEach { (window: Window) in
            refreshIfWindowShouldBeShownToTheUser(window, screen)
        }
    }

    static func refreshIfWindowShouldBeShownToTheUser(_ window: Window, _ screen: NSScreen) {
        window.shouldShowTheUser =
            !(window.application.runningApplication.bundleIdentifier.flatMap { id in Preferences.dontShowBlacklist.contains { id.hasPrefix($0) } } ?? false) &&
            !(Preferences.appsToShow[App.app.shortcutIndex] == .active && window.application.runningApplication != NSWorkspace.shared.frontmostApplication) &&
            !(!(Preferences.showHiddenWindows[App.app.shortcutIndex] != .hide) && window.isHidden) &&
            ((!Preferences.hideWindowlessApps && window.isWindowlessApp) ||
                !window.isWindowlessApp &&
                !(!(Preferences.showFullscreenWindows[App.app.shortcutIndex] != .hide) && window.isFullscreen) &&
                !(!(Preferences.showMinimizedWindows[App.app.shortcutIndex] != .hide) && window.isMinimized) &&
                !(Preferences.spacesToShow[App.app.shortcutIndex] == .active && window.spaceId != Spaces.currentSpaceId) &&
                !(Preferences.screensToShow[App.app.shortcutIndex] == .showingAltTab && !isOnScreen(window, screen)) &&
                (Preferences.showTabsAsWindows || !window.isTabbed))
    }

    static func isOnScreen(_ window: Window, _ screen: NSScreen) -> Bool {
        if let position = window.position {
            var screenFrameInQuartzCoordinates = screen.frame
            screenFrameInQuartzCoordinates.origin.y = NSMaxY(NSScreen.screens[0].frame) - NSMaxY(screen.frame)
            return screenFrameInQuartzCoordinates.contains(position)
        }
        return true
    }

    static func checkIfShortcutsShouldBeDisabled() {
        if let activeWindow = list.first {
            App.app.shortcutsShouldBeDisabled = (!Preferences.disableShortcutsBlacklistOnlyFullscreen || activeWindow.isFullscreen) &&
                (Preferences.disableShortcutsBlacklist.first { blacklistedId in
                    if let id = activeWindow.application.runningApplication.bundleIdentifier {
                        return id.hasPrefix(blacklistedId)
                    }
                    return false
                } != nil)
            if App.app.shortcutsShouldBeDisabled && App.app.appIsBeingUsed {
                App.app.hideUi()
            }
        }
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

