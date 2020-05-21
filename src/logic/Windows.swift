import Cocoa

class Windows {
    // order in the array is important: most-recently-used elements are first
    static var list = [Window]()
    static var previousFocusedWindowIndex = Int(0)
    static var focusedWindowIndex = Int(0)

    static func updateFocusedWindowIndex(_ newIndex: Int) {
        previousFocusedWindowIndex = focusedWindowIndex
        focusedWindowIndex = newIndex
        let focusedView = ThumbnailsView.recycledViews[focusedWindowIndex]
        ThumbnailsView.recycledViews[previousFocusedWindowIndex].highlight(false)
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

    static func refreshAllThumbnails() {
        list.forEachAsync { window in
            window.refreshThumbnail()
        }
    }

    static func refreshWhichWindowsToShowTheUser(_ screen: NSScreen) {
        Windows.list.forEach { (window: Window) in
            refreshIfWindowShouldBeShownToTheUser(window, screen)
        }
    }

    static func refreshIfWindowShouldBeShownToTheUser(_ window: Window, _ screen: NSScreen) {
        window.shouldShowTheUser = !(!Preferences.showMinimizedWindows && window.isMinimized) &&
            !(!Preferences.showHiddenWindows && window.isHidden) &&
            !(Preferences.appsToShow == .active && window.application.runningApplication != NSWorkspace.shared.frontmostApplication) &&
            !(Preferences.spacesToShow == .active && window.spaceId != Spaces.currentSpaceId) &&
            !(Preferences.screensToShow == .showingAltTab && !isOnScreen(window, screen)) &&
            (Preferences.showTabsAsWindows || !window.isTabbed)
    }

    static func isOnScreen(_ window: Window, _ screen: NSScreen) -> Bool {
        if let position = window.axUiElement.position() {
            var screenFrameInQuartzCoordinates = screen.frame
            screenFrameInQuartzCoordinates.origin.y = NSMaxY(NSScreen.screens[0].frame) - NSMaxY(screen.frame)
            return screenFrameInQuartzCoordinates.contains(position)
        }
        return true
    }
}
